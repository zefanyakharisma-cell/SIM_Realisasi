-- 0005_triggers (CONTRACTS §2.6)

-- Period derivation: academic year + semester from start_date (NULL when outside the calendar; R-09 at submit)
create function realisasi._trg_derive_period() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  select ay.id into new.academic_year_id from realisasi.academic_years ay
   where new.start_date between ay.start_date and ay.end_date order by ay.start_date limit 1;
  select s.id into new.semester_id from realisasi.semesters s
   where new.start_date between s.start_date and s.end_date order by s.start_date limit 1;
  if not found then new.semester_id := null; end if;
  return new;
end $$;
create trigger trg_activities_derive_period
  before insert or update of start_date on realisasi.activities
  for each row execute function realisasi._trg_derive_period();

-- Reporting deadline + lateness (R-10)
create function realisasi._trg_derive_deadline() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  new.reporting_deadline := new.end_date + coalesce(realisasi.setting_int('reporting_deadline_days'), 30);
  new.is_late := new.submitted_at is not null
                 and (new.submitted_at at time zone 'Asia/Jakarta')::date > new.reporting_deadline;
  return new;
end $$;
create trigger trg_activities_derive_deadline
  before insert or update of end_date, submitted_at on realisasi.activities
  for each row execute function realisasi._trg_derive_deadline();

-- Overall status (R-25), verified_at (R-28), track clocks
create function realisasi._trg_activity_status() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  new.status := case
    when new.submitted_at is null then 'draft'
    when new.partnership_status = 'rejected' then 'rejected'
    when new.partnership_status = 'revision_requested' or new.mobility_status = 'revision_requested' then 'revision_requested'
    when new.partnership_status = 'approved' and new.mobility_status in ('approved','not_required') then 'verified'
    else 'in_verification' end::realisasi.activity_status;

  if tg_op = 'UPDATE' and old.verified_at is not null then
    new.verified_at := old.verified_at;                       -- R-28: never cleared / changed
  elsif new.status = 'verified' and new.verified_at is null then
    new.verified_at := realisasi.now_ts();
  end if;

  if tg_op = 'INSERT' then
    new.partnership_since := coalesce(new.partnership_since, realisasi.now_ts());
    new.mobility_since    := coalesce(new.mobility_since, realisasi.now_ts());
  else
    if new.partnership_status is distinct from old.partnership_status
       and new.partnership_since is not distinct from old.partnership_since then
      new.partnership_since := realisasi.now_ts();
    end if;
    if new.mobility_status is distinct from old.mobility_status
       and new.mobility_since is not distinct from old.mobility_since then
      new.mobility_since := realisasi.now_ts();
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger trg_activities_status
  before insert or update on realisasi.activities
  for each row execute function realisasi._trg_activity_status();

-- Agreement link: chain id + partner snapshot (R-03, R-06)
create function realisasi._trg_activity_documents_chain() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  new.chain_id := realisasi.chain_root(new.original_document_id);
  return new;
end $$;
create trigger trg_activity_documents_snapshot
  before insert on realisasi.activity_documents
  for each row execute function realisasi._trg_activity_documents_chain();

create function realisasi._trg_activity_documents_partners() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    insert into realisasi.activity_partner_snapshot (activity_id, document_id, partner_id, partner_name, country_code, captured_at)
    select new.activity_id, new.original_document_id, p.id, p.name, p.country_code, realisasi.now_ts()
      from public.document_partners dp join public.partners p on p.id = dp.partner_id
     where dp.document_id = new.original_document_id
     order by dp.is_lead desc, p.id;
    return new;
  else
    delete from realisasi.activity_partner_snapshot
     where activity_id = old.activity_id and document_id = old.original_document_id;
    return old;
  end if;
end $$;
create trigger trg_activity_documents_snapshot_after
  after insert or delete on realisasi.activity_documents
  for each row execute function realisasi._trg_activity_documents_partners();

-- Participant versions: approving a version supersedes the previous approved one (R-21)
create function realisasi._trg_pset_supersede() returns trigger
language plpgsql security definer set search_path = realisasi, public, extensions, pg_temp as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update realisasi.participant_set_versions
       set status = 'superseded'
     where activity_id = new.activity_id and status = 'approved' and id <> new.id;
  end if;
  return new;
end $$;
create trigger trg_pset_supersede
  before update of status on realisasi.participant_set_versions
  for each row execute function realisasi._trg_pset_supersede();

-- settings.updated_at
create function realisasi._trg_touch_updated_at() returns trigger
language plpgsql set search_path = realisasi, public, extensions, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger trg_touch_updated_at
  before insert or update on realisasi.settings
  for each row execute function realisasi._trg_touch_updated_at();
