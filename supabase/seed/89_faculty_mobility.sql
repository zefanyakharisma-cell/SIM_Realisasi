-- 89_faculty_mobility: the seed scenarios were written when Jenis Kegiatan came from SIM Kerjasama's agendas; their
-- former non-mobility kegiatan are now Faculty Mobility (Jenis Kegiatan 5-9). The kegiatan helpers keep the old
-- behaviour for them (verified on submit, no participants), and this file completes them under the new rule:
--   * outbound: an approved participant set v1 with one PETRA staff member (HR registry)
--   * inbound: one external person (from the partner snapshot) when the scenario lists none
--   * Mobility track approved one minute after the submission (verified_at, and so every RENSTRA count, is unchanged)
-- Drafts are left as they are (an incomplete draft is allowed). Idempotent; applied to Supabase by
-- seed-supabase/89_faculty_mobility.sql.

do $$
declare a record; v_set uuid; v_staff text; v_mob uuid; v_at timestamptz;
begin
  select account_id into v_mob from realisasi.team_members where team = 'mobility' order by account_id limit 1;
  for a in
    select x.* from realisasi.activities x join realisasi.agendas g on g.id = x.agenda_id
     where g.program = 'faculty_mobility' and x.submitted_at is not null and x.mobility_status = 'not_required'
     order by x.code
  loop
    v_at := a.submitted_at + interval '1 minute';
    if a.direction = 'outbound' then
      -- prefer a lecturer of the submitting unit, else any active employee (stable per kegiatan)
      select e.employee_id into v_staff from mock_hr.employees e
        left join kerjasama.units u on u.id = a.submitter_unit_id
       where e.status = 'active'
       order by (e.unit_name = u.name) desc nulls last, md5(a.id::text || e.employee_id) limit 1;
      v_set := md5(a.id::text || ':v1')::uuid;
      insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at,
                                                      reviewed_by, reviewed_at)
      values (v_set, a.id, 1, 'approved', a.created_by, a.submitted_at, v_mob, v_at)
      on conflict (id) do nothing;
      insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
      select v_set, e.employee_id, e.full_name, e.unit_name from mock_hr.employees e where e.employee_id = v_staff
      on conflict (set_version_id, employee_id) do nothing;
    elsif not exists (select 1 from realisasi.activity_external_persons where activity_id = a.id) then
      insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role)
      select a.id, 'Delegasi ' || ps.partner_name, ps.partner_name, coalesce(ps.country_code, 'ID'), 'staff_visitor'
        from realisasi.activity_partner_snapshot ps where ps.activity_id = a.id
       order by ps.partner_name limit 1;
    end if;
    update realisasi.activities set mobility_status = 'approved', mobility_since = v_at where id = a.id;
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, diff, created_at)
    values (a.id, 'verification', 'mobility', 'approve', v_mob,
            case when a.direction = 'outbound' then '{"version":1}'::jsonb end, v_at);
  end loop;
end $$;
