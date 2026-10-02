-- 0004_views (CONTRACTS §2.7). All security_invoker except v_chains (public data only).

create view realisasi.v_activity_documents with (security_invoker = true) as
select ad.activity_id, ad.original_document_id, ad.chain_id, ad.out_of_scope_warning,
       realisasi.chain_current(ad.original_document_id) as current_document_id,
       od.doc_number as original_doc_number,
       cd.doc_number as current_doc_number
  from realisasi.activity_documents ad
  join kerjasama.documents od on od.id = ad.original_document_id
  left join kerjasama.documents cd on cd.id = realisasi.chain_current(ad.original_document_id);

-- v_chains: one row per renewal chain. Chain membership comes from one recursive pass (_chain_map; H6).
-- auto_renewed / terminated_at describe the chain's CURRENT valid document (deepest non in_process/rejected document),
-- so a terminated or replaced auto-renewed agreement stops being open-ended (H2). terminated_at is an additive column.
create view realisasi.v_chains as
with m as (
  select * from realisasi._chain_map()
), docs as (
  select d.*, m.root_id as chain_id, m.depth
    from kerjasama.documents d join m on m.doc_id = d.id
   where d.start_date is not null and d.status not in ('in_process','rejected')
), agg as (
  select chain_id,
         min(start_date) as chain_start,
         max(coalesce(terminated_at::date, end_date)) as chain_end,
         (array_agg(auto_renewed order by depth desc, id desc))[1] as auto_renewed,
         (array_agg(terminated_at order by depth desc, id desc))[1] as terminated_at,
         array_agg(id order by start_date, id) as document_ids,
         array_agg(doc_number order by start_date, id) as doc_numbers
    from docs group by chain_id
), cur as (                                   -- = chain_current(root): deepest document of any status
  select distinct on (root_id) root_id, doc_id from m order by root_id, depth desc, doc_id desc
), prt as (
  select dc.chain_id, bool_or(p.country_code <> 'ID') as is_international,
         array_agg(distinct p.name order by p.name) as partner_names,
         array_agg(distinct p.country_code order by p.country_code) as country_codes
    from docs dc join kerjasama.document_partners dp on dp.document_id = dc.id join kerjasama.partners p on p.id = dp.partner_id
   group by dc.chain_id
)
select a.chain_id, a.chain_start, a.chain_end, a.auto_renewed,
       coalesce(prt.is_international, false) as is_international,
       a.document_ids, a.doc_numbers,
       cd.id as current_document_id, cd.doc_number as current_doc_number, cd.kind, cd.title,
       coalesce(prt.partner_names, '{}') as partner_names,
       coalesce(prt.country_codes, '{}') as country_codes,
       a.terminated_at
  from agg a
  left join cur on cur.root_id = a.chain_id
  left join kerjasama.documents cd on cd.id = cur.doc_id
  left join prt on prt.chain_id = a.chain_id;

create view realisasi.v_activity_list with (security_invoker = true) as
select a.id, a.code, a.name, a.agenda_id, ag.name as agenda_name, a.direction,
       r.mobility_category, (r.mobility_category is not null) as is_mobility,
       a.start_date, a.end_date, a.academic_year_id, ay.label as ay_label,
       a.semester_id, case when s.id is null then null else initcap(s.term::text) || ' ' || ay.label end as semester_label,
       a.mode, a.status, a.mobility_status, a.mobility_since,
       a.submitter_unit_id, su.name as submitter_unit_name,
       coalesce(u.unit_ids, '{}') as unit_ids, coalesce(u.unit_names, '{}') as unit_names,
       coalesce(d.document_ids, '{}') as document_ids, coalesce(d.document_numbers, '{}') as document_numbers,
       coalesce(d.chain_ids, '{}') as chain_ids,
       coalesce(ps.partner_names, '{}') as partner_names, coalesce(ps.country_codes, '{}') as country_codes,
       coalesce(ps.is_international, false) as is_international,
       a.country_code,
       a.is_late, a.reporting_deadline, a.submitted_at, a.verified_at,
       a.created_at, a.updated_at, a.created_by,
       coalesce(d.out_of_scope, false) as out_of_scope,
       realisasi.activity_open_conflicts(a.id) as open_conflicts
  from realisasi.activities a
  left join kerjasama.agendas ag on ag.id = a.agenda_id
  left join realisasi.agenda_rules r on r.agenda_id = a.agenda_id
  left join realisasi.academic_years ay on ay.id = a.academic_year_id
  left join realisasi.semesters s on s.id = a.semester_id
  left join kerjasama.units su on su.id = a.submitter_unit_id
  left join lateral (
    select array_agg(au.unit_id order by au.is_submitter desc, un.name) as unit_ids,
           array_agg(un.name order by au.is_submitter desc, un.name) as unit_names
      from realisasi.activity_units au join kerjasama.units un on un.id = au.unit_id
     where au.activity_id = a.id) u on true
  left join lateral (
    select array_agg(ad.original_document_id order by doc.doc_number) as document_ids,
           array_agg(doc.doc_number order by doc.doc_number) as document_numbers,
           array_agg(distinct ad.chain_id) as chain_ids,
           bool_or(ad.out_of_scope_warning) as out_of_scope
      from realisasi.activity_documents ad join kerjasama.documents doc on doc.id = ad.original_document_id
     where ad.activity_id = a.id) d on true
  left join lateral (
    select array_agg(distinct p.partner_name) as partner_names,
           array_agg(distinct p.country_code) as country_codes,
           bool_or(p.country_code <> 'ID') as is_international
      from realisasi.activity_partner_snapshot p where p.activity_id = a.id) ps on true;
