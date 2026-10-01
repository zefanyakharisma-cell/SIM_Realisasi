-- 0006_rls: RLS on every realisasi table; SELECT policies only (writes go through definer RPCs).
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'realisasi' loop
    execute format('alter table realisasi.%I enable row level security', t);
  end loop;
end $$;

-- Activity visibility (Rules §10) is evaluated once per statement: role checks are (select …) initplans and the
-- visible-id sets are hashed subplans, instead of a definer call per row (M10). Same semantics as can_view_activity().
create policy activities_select on realisasi.activities for select to authenticated
  using ((select realisasi.is_io())
         or ((select realisasi.my_role()) = 'viewer' and status = 'verified')
         or id in (select realisasi.my_activity_ids()));

create policy activity_units_select on realisasi.activity_units for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
create policy activity_documents_select on realisasi.activity_documents for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
create policy activity_partner_snapshot_select on realisasi.activity_partner_snapshot for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
create policy activity_sdgs_select on realisasi.activity_sdgs for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
create policy activity_external_persons_select on realisasi.activity_external_persons for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
create policy activity_files_select on realisasi.activity_files for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));

create policy event_groups_select on realisasi.event_groups for select to authenticated using (true);

create policy participant_set_versions_select on realisasi.participant_set_versions for select to authenticated
  using ((select realisasi.is_io()) or activity_id in (select realisasi.visible_activity_ids()));
-- = can_view_participants(activity): io_admin, mobility team, submitter of an own/co-unit activity
create policy participant_students_select on realisasi.participant_students for select to authenticated
  using ((select realisasi.my_role()) = 'io_admin'
         or ((select realisasi.my_role()) = 'io_staff' and (select realisasi.in_team('mobility')))
         or set_version_id in (select realisasi.my_pset_ids()));
create policy participant_staff_select on realisasi.participant_staff for select to authenticated
  using ((select realisasi.my_role()) = 'io_admin'
         or ((select realisasi.my_role()) = 'io_staff' and (select realisasi.in_team('mobility')))
         or set_version_id in (select realisasi.my_pset_ids()));

-- Log rows carrying participant identifiers (mobility edits / row notes) only for callers who may see participants (M6)
create policy activity_log_select on realisasi.activity_log for select to authenticated
  using (((select realisasi.is_io()) or activity_id in (select realisasi.my_activity_ids()))
         and (not (coalesce(diff ? 'students', false) or coalesce(diff ? 'staff', false) or coalesce(diff ? 'row_notes', false))
              or (select realisasi.sees_participant_identifiers())));

create policy duplicate_candidates_select on realisasi.duplicate_candidates for select to authenticated
  using ((select realisasi.is_io()));
create policy known_activities_select on realisasi.known_activities for select to authenticated
  using ((select realisasi.is_io()));

create policy notifications_select on realisasi.notifications for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy settings_select on realisasi.settings for select to authenticated using (true);
create policy academic_years_select on realisasi.academic_years for select to authenticated using (true);
create policy semesters_select on realisasi.semesters for select to authenticated using (true);
create policy holidays_select on realisasi.holidays for select to authenticated using (true);
create policy activity_types_select on realisasi.activity_types for select to authenticated using (true);
create policy sdgs_select on realisasi.sdgs for select to authenticated using (true);
create policy team_members_select on realisasi.team_members for select to authenticated using (true);

create policy kpi_snapshots_select on realisasi.kpi_snapshots for select to authenticated
  using ((select realisasi.my_role()) in ('io_staff','io_admin','viewer'));
create policy kpi_snapshot_items_select on realisasi.kpi_snapshot_items for select to authenticated
  using ((select realisasi.my_role()) in ('io_staff','io_admin','viewer'));

create policy email_outbox_select on realisasi.email_outbox for select to authenticated
  using ((select realisasi.my_role()) = 'io_admin');
create policy export_log_select on realisasi.export_log for select to authenticated
  using ((select realisasi.my_role()) = 'io_admin');
-- file_blobs, job_marks: RLS enabled, no policy, no grant.
