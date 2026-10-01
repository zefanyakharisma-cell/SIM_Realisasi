-- 0016_grants: least privilege. Reads via RLS-protected selects; writes only via definer RPCs.
revoke all on all tables in schema realisasi, mock_baak, mock_hr from public, anon, authenticated;
revoke all on all sequences in schema realisasi from public, anon, authenticated;
revoke execute on all functions in schema realisasi from public;
revoke all on schema mock_baak, mock_hr from public, anon, authenticated;
alter default privileges in schema realisasi revoke execute on functions from public;

grant usage on schema realisasi to authenticated;

grant select on
  realisasi.team_members, realisasi.settings, realisasi.academic_years, realisasi.semesters, realisasi.holidays,
  realisasi.activity_types, realisasi.sdgs, realisasi.event_groups, realisasi.activities, realisasi.activity_units,
  realisasi.activity_documents, realisasi.activity_partner_snapshot, realisasi.activity_sdgs,
  realisasi.activity_external_persons, realisasi.activity_files, realisasi.participant_set_versions,
  realisasi.participant_students, realisasi.participant_staff, realisasi.duplicate_candidates, realisasi.activity_log,
  realisasi.known_activities, realisasi.notifications, realisasi.email_outbox, realisasi.export_log,
  realisasi.kpi_snapshots, realisasi.kpi_snapshot_items
  to authenticated;
grant select on realisasi.v_activity_documents, realisasi.v_chains, realisasi.v_activity_list,
                realisasi.v_known_activities, realisasi.v_duplicate_candidates to authenticated;

-- Helpers called by RLS policies and security_invoker views
grant execute on function
  realisasi.today(), realisasi.now_ts(), realisasi.setting_int(text), realisasi.setting_num(text), realisasi.settings_json(),
  realisasi.business_days_between(date, date), realisasi.sla_days(timestamptz), realisasi.sla_level(int),
  realisasi.chain_root(int), realisasi.chain_current(int), realisasi.semester_label(int),
  realisasi.my_role(), realisasi.my_unit(), realisasi.in_team(realisasi.team), realisasi.is_io(),
  realisasi.can_view_activity(uuid), realisasi.can_view_participants(uuid),
  realisasi.in_frozen_period(uuid), realisasi.is_late_addition(uuid),
  realisasi.activity_linked_count(uuid), realisasi.activity_participant_total(uuid),
  realisasi.demo_time_travel_enabled(),
  realisasi.my_activity_ids(), realisasi.visible_activity_ids(), realisasi.my_pset_ids(),
  realisasi.sees_participant_identifiers()
  to authenticated;

-- RPC catalogue (CONTRACTS §3)
grant execute on function
  realisasi.lookup_students(text[]), realisasi.lookup_employees(text[]),
  realisasi.documents_valid_between(date, date, int),
  realisasi.save_activity_draft(uuid, jsonb), realisasi.delete_draft(uuid), realisasi.ensure_participant_draft(uuid),
  realisasi.save_participants(uuid, jsonb, jsonb), realisasi.submission_checklist(uuid), realisasi.submit_activity(uuid),
  realisasi.can_read_file(text), realisasi.storage_put(text, text, bytea), realisasi.storage_get(text),
  realisasi.register_activity_file(uuid, realisasi.file_kind, text, text, int, text),
  realisasi.add_evidence_link(uuid, text, text), realisasi.remove_activity_file(bigint),
  realisasi.partnership_approve(uuid, text), realisasi.partnership_request_revision(uuid, text),
  realisasi.partnership_reject(uuid, text, text), realisasi.mobility_approve(uuid, text),
  realisasi.mobility_request_revision(uuid, text, jsonb), realisasi.edit_verified_activity(uuid, jsonb, text),
  realisasi.commit_participant_edit(uuid, text),
  realisasi.link_duplicates(bigint, text), realisasi.link_activities(uuid, uuid, text), realisasi.dismiss_duplicate(bigint, text),
  realisasi.unlink_activity(uuid, text),
  realisasi.create_known_activity(jsonb), realisasi.update_known_activity(bigint, jsonb), realisasi.known_match_suggestions(bigint),
  realisasi.match_known_activity(bigint, uuid), realisasi.unmatch_known_activity(bigint),
  realisasi.dismiss_known_activity(bigint, text), realisasi.nudge_known_activity(bigint),
  realisasi.update_settings(jsonb), realisasi.upsert_academic_year(int, text, date, date),
  realisasi.upsert_semester(int, int, realisasi.semester_term, date, date, date),
  realisasi.upsert_activity_type(int, jsonb), realisasi.upsert_holiday(date, text), realisasi.delete_holiday(date),
  realisasi.freeze_snapshot(int, realisasi.snapshot_kind, timestamptz, uuid), realisasi.refreeze_snapshot(uuid, text),
  realisasi.run_daily_jobs(),
  realisasi.mark_notifications_read(bigint[]), realisasi.log_export(text, jsonb, int, boolean),
  realisasi.period_info(int, text), realisasi.dashboard(int, text, int),
  realisasi.kpi_drilldown(int, text, text, text, int, uuid), realisasi.kpi_participant_rows(int, text, int, uuid),
  realisasi.activity_detail(uuid), realisasi.participant_version(uuid, int), realisasi.participant_counts(uuid),
  realisasi.nav_counts(), realisasi.agreement_realization(int), realisasi.agreement_flags(int),
  realisasi.snapshot_list(int), realisasi.snapshot_detail(uuid),
  realisasi.snapshot_late_additions(uuid), realisasi.snapshot_post_freeze_changes(uuid)
  to authenticated;
