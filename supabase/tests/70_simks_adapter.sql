-- 70_simks_adapter: the kerjasama.* adapter over the SIMKS-shaped tables (local stub = SIMKS shapes), its access model,
-- and the rule that Realisasi creates nothing in schema public.
\ir _helpers.inc

-- ---- countries: SIMKS negara.kode is ISO alpha-3, Realisasi sees alpha-2 -----------------------------------------
select pg_temp.ok((select count(*) from kerjasama.iso3166) >= 249, 'iso3166 seeded with the full ISO list');
select pg_temp.eq((select code from kerjasama.countries where alpha3 = 'IDN'), 'ID', 'IDN -> ID (Indonesia)');
select pg_temp.eq((select name from kerjasama.countries where code = 'JP'), 'Jepang', 'JPN -> JP, name = negara.nama');
select pg_temp.eq((select code from kerjasama.countries where alpha3 = 'TWN'), 'TW', 'TWN -> TW');
select pg_temp.ok((select bool_and(code ~ '^[A-Z]{2}$') from kerjasama.countries), 'every exposed country code is alpha-2');
select pg_temp.eq((select count(*) from kerjasama.countries), (select count(*) from public.negara), 'one country per negara row');
select pg_temp.ok((select is_domestic from kerjasama.countries where code = 'ID'), 'is_domestic carried over');
-- an unmappable kode is left out instead of leaking a 3-letter code
insert into public.negara (id, kode, nama) values (99, 'ZZZ', 'Negeri Antah');
select pg_temp.ok(not exists (select 1 from kerjasama.countries where name = 'Negeri Antah'), 'unmappable alpha-3 not exposed');
-- lower-case / padded codes still map
insert into public.negara (id, kode, nama) values (98, ' vnm', 'Vietnam');
select pg_temp.eq((select code from kerjasama.countries where name = 'Vietnam'), 'VN', 'kode normalised (trim/upper) before mapping');

-- ---- partners -----------------------------------------------------------------------------------------------------
select pg_temp.eq((select country_code from kerjasama.partners where id = 1), 'JP', 'partner country via negara (alpha-2)');
select pg_temp.eq((select country_code from kerjasama.partners where id = 10), 'ID', 'domestic partner -> ID');
insert into public.partner (id, nama, is_international, id_negara) values (90, 'Mitra Tanpa Negara', false, null),
                                                                         (91, 'Foreign No Country', true, null),
                                                                         (92, 'Merged Into KIT', true, 2);
update public.partner set id_merged_into = 1, is_active = false where id = 92;
select pg_temp.eq((select country_code from kerjasama.partners where id = 90), 'ID', 'domestic partner without negara -> ID');
select pg_temp.ok((select country_code is null from kerjasama.partners where id = 91), 'international partner without negara -> null');
select pg_temp.eq((select merged_into_id::text || '/' || is_active::text from kerjasama.partners where id = 92), '1/false',
                  'merged partner kept, merged_into_id exposed');

-- ---- units ----------------------------------------------------------------------------------------------------------
select pg_temp.eq((select string_agg(id || ':' || kind, ',' order by id) from kerjasama.units where id in (1, 2, 10, 11, 20, 21, 30, 31)),
                  '1:up,2:up,10:faculty,11:prodi,20:faculty,21:prodi,30:faculty,31:prodi', 'unit kind from jenis_unit + hierarchy');
select pg_temp.eq((select parent_id from kerjasama.units where id = 11), 10, 'unit parent_id = id_parent_unit');
-- an academic university root above faculties is 'up', not 'faculty'
insert into public.unit (id, nama, id_jenis_unit) values (500, 'Universitas Uji', 1);
insert into public.unit (id, nama, id_parent_unit, id_jenis_unit) values (501, 'Fakultas Uji', 500, 1);
insert into public.unit (id, nama, id_parent_unit, id_jenis_unit) values (502, 'Prodi Uji', 501, 1);
select pg_temp.eq((select string_agg(kind, ',' order by id) from kerjasama.units where id between 500 and 502), 'up,faculty,prodi',
                  'academic root / faculty / prodi');

-- ---- documents ------------------------------------------------------------------------------------------------------
select pg_temp.eq((select count(*) from kerjasama.documents), (select count(*) from public.dokumen_kerja_sama), 'one document per dokumen_kerja_sama');
select pg_temp.eq((select proposal_id from kerjasama.documents where id = 905), 1905, 'document id = dokumen.no, proposal id differs');
select pg_temp.eq((select predecessor_id from kerjasama.documents where id = 905), 904,
                  'renewal predecessor resolved via proposal.id_dokumen_sebelumnya (proposal 1904 -> dokumen 904)');
select pg_temp.ok((select predecessor_id is null from kerjasama.documents where id = 904), 'chain root has no predecessor');
select pg_temp.eq((select status || '/' || archived_reason from kerjasama.documents where id = 904), 'archived/superseded_by_renewal',
                  'Diarsipkan -> archived, alasan_arsip verbatim');
select pg_temp.eq((select status from kerjasama.documents where id = 115), 'active', 'Akan Berakhir -> active');
select pg_temp.eq((select status from kerjasama.documents where id = 101), 'active', 'Aktif -> active');
select pg_temp.eq((select status from kerjasama.documents where id = 906), 'in_process', 'other SIMKS status -> in_process');
select pg_temp.eq((select status || '|' || doc_number || '|' || coalesce(start_date::text, '-') from kerjasama.documents where id = 907),
                  'rejected|Tanpa nomor #907|-', 'alasan_arsip rejected -> rejected; null number gets a placeholder');
select pg_temp.eq((select kind from kerjasama.documents where id = 104), 'MoA', 'kind from proposal jenis_kerjasama');
select pg_temp.eq((select title from kerjasama.documents where id = 101), 'Kerja Sama Pendidikan dan Riset Teknik', 'title from tujuan_kerjasama');
select pg_temp.ok((select auto_renewed from kerjasama.documents where id = 903), 'auto_renewed from realisasi.document_overrides');
select pg_temp.ok(not (select bool_or(auto_renewed) from kerjasama.documents where id <> 903), 'no override -> auto_renewed false');
select pg_temp.eq((select terminated_at from kerjasama.documents where id = 119), '2025-06-30 10:00+07'::timestamptz, 'terminated_at from overrides');
select pg_temp.ok((select terminated_at is null from kerjasama.documents where id = 101), 'no override -> terminated_at null');
-- a document without tujuan gets "<kind> <lead partner>"; renewal created later in SIMKS joins the chain
select pg_temp.simks_doc(960, 'TEST/MoU/960', 'MoU', 'Aktif', '2031-06-15', '2036-06-14', p_prev_no => 901, p_partners => '{17}', p_units => '{10}');
select pg_temp.eq((select title from kerjasama.documents where id = 960), 'MoU Chulalongkorn University', 'title fallback = kind + lead partner');
select pg_temp.eq(realisasi.chain_root(960), 901, 'chain_root follows the proposal-based predecessor');
select pg_temp.eq(realisasi.chain_current(901), 960, 'chain_current follows the renewal');

-- ---- document partners / scope (keyed by proposal in SIMKS) ----------------------------------------------------------
select pg_temp.eq((select array_agg(unit_id order by unit_id) from kerjasama.document_scope_units where document_id = 101), array[10, 11, 12],
                  'scope units via proposal_dokumen_unit');
select pg_temp.eq((select partner_id::text || '/' || is_lead::text from kerjasama.document_partners where document_id = 905), '14/true',
                  'document partners via partner_pengusul');
select pg_temp.eq((select array_agg(partner_id) from kerjasama.document_partners where document_id = 960), array[17], 'new doc partners');

-- ---- profiles: SIMKS akun + realisasi.account_roles ----------------------------------------------------------------
select pg_temp.eq((select count(*) from kerjasama.profiles), 8::bigint, 'only accounts with an account_roles row');
select pg_temp.ok(not exists (select 1 from kerjasama.profiles where akun_id = 9), 'SIMKS-only akun 9 is not a Realisasi user');
select pg_temp.eq((select id from kerjasama.profiles where akun_id = 1), :'ADMIN'::uuid, 'profile id = akun.auth_user_id');
select pg_temp.eq((select display_name || '/' || app_role || '/' || unit_id from kerjasama.profiles where akun_id = 6),
                  'Kaprodi Informatika/submitter/11', 'display_name = jabatan.nama, unit from jabatan');
insert into realisasi.account_roles (akun_id, app_role, unit_id) values (9, 'viewer', 30);
select pg_temp.eq((select id from kerjasama.profiles where akun_id = 9), md5('simks-akun:9')::uuid, 'no auth user -> stable md5 uuid');
select pg_temp.eq((select unit_id from kerjasama.profiles where akun_id = 9), 30, 'account_roles.unit_id overrides jabatan unit');
update public.jabatan set nama = ' ' where id = 9;
select pg_temp.eq((select display_name from kerjasama.profiles where akun_id = 9), 'sekretariat.simks@demo.petra.ac.id', 'blank jabatan -> email');
-- deactivated SIMKS account keeps its name (history) but loses access
update public.akun set is_active = false where id = 4;
select pg_temp.ok((select app_role is null and display_name is not null from kerjasama.profiles where akun_id = 4), 'inactive akun -> app_role null');
:as_fti
select pg_temp.ok(realisasi.my_role() is null, 'inactive account has no role');
select pg_temp.throws($$select realisasi.save_activity_draft(null, '{"name":"x"}')$$, 'AUTH_REQUIRED', 'inactive account cannot act');
reset role;
update public.akun set is_active = true where id = 4;

-- ---- RPC validation replaces the dropped FKs ------------------------------------------------------------------------
create function pg_temp.payload(p_extra jsonb default '{}') returns jsonb language sql as $$
  select '{"name":"Uji Adapter","type_id":5,"start_date":"2026-09-01","end_date":"2026-09-05","mode":"offline","venue":"PCU",
           "city":"Surabaya","country_code":"ID","funding_source":"pcu","description":"Uji adapter.","submitter_unit_id":10,
           "co_unit_ids":[],"document_ids":[101],"sdg_ids":[4],"external_persons":[]}'::jsonb || p_extra $$;
grant execute on function pg_temp.payload(jsonb) to authenticated;
:as_fti
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"co_unit_ids":[424242]}'))$$, 'VALIDATION_INVALID',
                      'unknown co-unit rejected without an FK');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"country_code":"IDN"}'))$$, 'VALIDATION_INVALID',
                      'alpha-3 country code rejected (alpha-2 only)');
select pg_temp.ok(realisasi.save_activity_draft(null, pg_temp.payload()) is not null, 'valid ids accepted');
select pg_temp.throws($$select realisasi.save_activity_draft(null, pg_temp.payload('{"document_ids":[424242]}'))$$, 'R04_AGREEMENT_NOT_VALID',
                      'unknown document rejected');
reset role;
select pg_temp.ok(pg_temp.err(format($$insert into realisasi.activity_documents (activity_id, original_document_id) values (%L, 424242)$$,
                                     pg_temp.aid(1))) like '%is not in kerjasama.documents%', 'trigger rejects an unknown document id');
select pg_temp.ok(exists (select 1 from pg_constraint k where k.conrelid = c.attrelid and k.contype = 'c'
                          and c.attnum = any(k.conkey) and pg_get_constraintdef(k.oid) like '%[A-Z]{2}%'),
                  'alpha-2 check on ' || c.attrelid::regclass || '.country_code')
  from pg_attribute c where c.attname = 'country_code' and c.attnum > 0 and not c.attisdropped
   and c.attrelid in (select oid from pg_class where relnamespace = 'realisasi'::regnamespace and relkind = 'r');

-- ---- access model --------------------------------------------------------------------------------------------------
select pg_temp.ok(not has_table_privilege('authenticated', 'public.' || t, 'SELECT') and not has_table_privilege('anon', 'public.' || t, 'SELECT'),
                  'no API-role grant on SIMKS public.' || t)
  from unnest(array['unit','jenis_unit','negara','partner','proposal_dokumen','dokumen_kerja_sama','partner_pengusul',
                    'proposal_dokumen_unit','jabatan','akun']) t;
select pg_temp.ok(not has_table_privilege('authenticated', t, 'SELECT'), 'no grant on ' || t)
  from unnest(array['kerjasama.iso3166', 'realisasi.account_roles', 'realisasi.document_overrides']) t;
select pg_temp.ok(not has_table_privilege('anon', 'kerjasama.' || v, 'SELECT') and has_table_privilege('authenticated', 'kerjasama.' || v, 'SELECT'),
                  'kerjasama.' || v || ': authenticated only')
  from unnest(array['units','countries','partners','documents','document_partners','document_scope_units','profiles']) v;
select pg_temp.ok(not coalesce((select reloptions from pg_class where oid = ('kerjasama.' || v)::regclass) @> array['security_invoker=true'], false),
                  'kerjasama.' || v || ' reads with the owner''s rights')
  from unnest(array['units','countries','partners','documents','document_partners','document_scope_units','profiles']) v;
create temp table _cnt as
select (select count(*) from public.dokumen_kerja_sama) d, (select count(*) from public.unit) u, (select count(*) from public.partner) p;
grant select on _cnt to authenticated;
:as_view
select pg_temp.ok(pg_temp.err('select count(*) from public.' || t) like 'permission denied%', 'authenticated cannot read public.' || t)
  from unnest(array['unit','negara','partner','proposal_dokumen','dokumen_kerja_sama','partner_pengusul','proposal_dokumen_unit','jabatan','akun']) t;
select pg_temp.eq((select count(*) from kerjasama.documents), (select d from _cnt), 'authenticated sees all documents through the adapter');
select pg_temp.eq((select count(*) from kerjasama.units), (select u from _cnt), 'authenticated sees all units through the adapter');
select pg_temp.eq((select count(*) from kerjasama.partners), (select p from _cnt), 'authenticated sees all partners through the adapter');
select pg_temp.ok(pg_temp.err($$update kerjasama.documents set start_date = null where id = 101$$) <> '', 'adapter views are read-only');
select pg_temp.ok(pg_temp.err($$select * from realisasi.account_roles$$) like 'permission denied%', 'account_roles not readable');
reset role;

-- ---- Realisasi creates nothing in schema public -------------------------------------------------------------------
-- Everything in public must be an extension member or one of the SIMKS (stub) objects; locally those are exactly the
-- tables of supabase/local/00_simks_stub.sql (+ their indexes) and the jenis_kerjasama enum.
create temp table _simks(name text);
insert into _simks values ('unit'),('jenis_unit'),('negara'),('partner'),('proposal_dokumen'),('dokumen_kerja_sama'),
  ('partner_pengusul'),('proposal_dokumen_unit'),('jabatan'),('akun');
select pg_temp.eq((select string_agg(c.relname, ',' order by c.relname) from pg_class c
                    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','f','p','S')
                      and c.relname not in (select name from _simks)
                      and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')),
                  null, 'no Realisasi tables/views/sequences in public');
select pg_temp.eq((select string_agg(i.relname, ',') from pg_index x join pg_class i on i.oid = x.indexrelid join pg_class t on t.oid = x.indrelid
                    where i.relnamespace = 'public'::regnamespace and t.relname not in (select name from _simks)
                      and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = t.oid and d.deptype = 'e')),
                  null, 'no Realisasi indexes in public');
select pg_temp.eq((select string_agg(p.oid::regprocedure::text, ',') from pg_proc p
                    where p.pronamespace = 'public'::regnamespace
                      and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')),
                  null, 'no Realisasi functions in public');
select pg_temp.eq((select string_agg(t.typname, ',') from pg_type t
                    where t.typnamespace = 'public'::regnamespace and t.typtype in ('e','d','c','r','m') and t.typrelid = 0
                      and t.typname <> 'jenis_kerjasama'
                      and not exists (select 1 from pg_depend d where d.classid = 'pg_type'::regclass and d.objid = t.oid and d.deptype = 'e')),
                  null, 'no Realisasi types in public');
select pg_temp.eq((select string_agg(tgname, ',') from pg_trigger g join pg_class c on c.oid = g.tgrelid
                    where c.relnamespace = 'public'::regnamespace and not g.tgisinternal), null, 'no triggers on SIMKS tables');
select pg_temp.eq((select string_agg(polname, ',') from pg_policy p join pg_class c on c.oid = p.polrelid
                    where c.relnamespace = 'public'::regnamespace), null, 'no policies on SIMKS tables');
rollback;
