# Database review: SIM Realisasi (`supabase/`, `scripts/db-*.sh`)

**Reviewer:** ECC database-reviewer agent · **Date:** 2026-10-01 · **Scope:** migrations 0000–0017, seeds, SQL tests, `scripts/db-reset.sh`, `scripts/db-test.sh`
**Binding docs:** `docs/spec/Rules.md` (authoritative), `docs/spec/Schema.md`, `docs/CONTRACTS.md` (including the amendments)
**Method:** I read every migration. I built a private DB (`sim_realisasi_review`) with `scripts/db-reset.sh`; the existing suite passes there (10/10 files, 868 checks). I then reproduced each finding in that DB with SQL scripts that end in `rollback`. The shared DB was not touched, and the review DB was dropped afterwards.

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 6 |
| MEDIUM | 10 |
| LOW | 10 |

### What is in good shape (checked and verified)
- **Definer functions:** every `security definer` function sets `search_path` (catalog query returned 0 without it). `authenticated` cannot run any `_`-prefixed helper, and `anon` cannot run anything in `realisasi`.
- **Table privileges:** RLS is on for every `realisasi` table. `authenticated`/`anon` have no INSERT/UPDATE/DELETE on any `realisasi`, `mock_*` or `public` table.
- **Dynamic SQL:** there is none, so no SQL-injection surface (only `format(... %I ...)` in the 0006 DO block).
- **Locking:** state-changing RPCs lock the activity row with `_get_activity(... for update)`. Double submit and concurrent approve/reject therefore serialise correctly: the second caller gets `STATE_INVALID`/`TRACK_NOT_PENDING`. `one_draft_pset`, `one_approved_pset`, `one_current_ia_ir` and `one_live_snapshot` back the invariants.
- **Seeds:** re-running all seed files on a seeded DB changed no row counts (activities, logs, notifications, snapshots, partner snapshots, blobs, participants).
- **Rules that hold:** the R-25 status derivation, R-28 `verified_at` immutability, the R-21 supersede trigger and the AT-01…AT-12 DB paths all behave as specified.

---

## HIGH

### H1. Unit-level KPIs double count one event when a unit is on two linked activities (R-38/R-39)
**File:** `supabase/migrations/0012_kpi.sql:17` (`dedupe_key = case when p_unit_id is null then event_group_id else id end`), used by `k11` (l.27), `ks1` (l.30–36) and `ks8` (l.37–39).

**Problem:** at unit level the dedupe key is the activity id. If a unit is the submitter or a co-unit on two activities of the same event group, the same student or event counts twice for that unit. R-38 defines the count as distinct (NRP, **event group**). R-39 allows the double count only *across* units.

**Repro:** add FTI as co-unit of S-14, which is linked with FTI's own S-13 (same 12 students):
```sql
insert into realisasi.activity_units values ('a0000000-0000-4000-8000-000000000014', 10, false);
select realisasi.compute_kpis('2026-08-01','2026-10-01','2026-10-01',2,null,10) #> '{kpi_1_1,outbound}';
-- before: 12   after: 24   (distinct students: 12); kpi_1_19_s1.international 2 -> 3
```

**Fix:** use `event_group_id` as the dedupe key at both levels. The unit filter already sits in `qa`, so each unit still counts a linked event once and both units count it (R-39).
```sql
win as (select *, event_group_id as dedupe_key from qa where start_date between p_from and p_to)
```
Pick the representative activity per (unit, group) the same way. Also update the "Unit: one row per distinct (nrp, activity_id)" wording in CONTRACTS §4.2, because it contradicts R-38. Add a test with a co-unit on a linked pair.

### H2. Auto-renewed chains count as active forever, even after termination or replacement (R-04, R-43)
**Files:**
- `0004_views.sql:21`: `bool_or(auto_renewed)` over *all* docs of the chain.
- `0012_kpi.sql:52`: `(c.auto_renewed or c.chain_end >= p_from)`.
- `0007_rpc_submission.sql:38`: `documents_valid_between` uses `d.auto_renewed or …` and ignores `terminated_at`.

**Problem:** an auto-renewed agreement that SIM Kerjasama later terminates stays in the KPI 1.19.24 denominator every year. It also stays selectable for new activities. The same happens when an old auto-renewed document is replaced by a fixed-term renewal that has since expired: `bool_or` still marks the whole chain auto-renewed and exempt from grace.

**Repro:**
```sql
update public.documents set status='archived', archived_reason='terminated', terminated_at='2024-03-01' where id=903;
select chain_end, auto_renewed from realisasi.v_chains where chain_id=903;          -- 2024-03-01 | t
select bucket from realisasi.kpi_items('2026-08-01','2026-10-01','2026-10-01',2)
 where kpi_code='1.19.24' and ref_id='903';                                         -- denominator
select document_id from realisasi.documents_valid_between('2026-09-01','2026-09-05') where document_id=903; -- 903
```

**Fix:**
- In `v_chains`, take `auto_renewed` from the **current** document of the chain, not `bool_or`. Expose `terminated_at` of the current doc.
- The active test becomes `(c.auto_renewed and c.terminated_at is null) or c.chain_end >= p_from`.
- In `documents_valid_between`, use `(d.auto_renewed and d.terminated_at is null) or coalesce(d.terminated_at::date, d.end_date) >= p_start`. Optionally also require `d.terminated_at::date >= p_start` for auto-renewed docs.

### H3. KPI 1.19.S8 gap entries disappear when matched to a non-verified, later-rejected or domestic activity (R-49/R-50, R-53)
**Files:** `0010_rpc_duplicates_known.sql:201-213` (`match_known_activity` accepts any non-draft, non-rejected activity) and `0012_kpi.sql:40-45` (the gap counts only `status='unmatched'`). `partnership_reject` (`0009:71-86`) does not revert matches.

**Problem:** R-50 drops matched entries because they are "already represented by their SIM activity". That only holds if the matched activity is verified, international and in the window. A known entry matched to an `in_verification` activity that is then rejected (the typical *duplicate* case) is in neither Reported nor Gap, and S8 goes up.

**Repro:**
```sql
-- as io.partnership
select realisasi.match_known_activity(6, 'a0000000-0000-4000-8000-000000000025');   -- S-25, in_verification
select realisasi.partnership_reject('a0000000-0000-4000-8000-000000000025','not_partnership','x');
-- S8 live 2026/2027: before {"reported":4,"unmatched_known":2,"pct":66.7}  after {"reported":4,"unmatched_known":1,"pct":80.0}
```

**Fix:**
- In `kknown`, count a known entry as a gap unless it is matched to an activity that is a qualifying `reported` item (verified as of `p_as_of`, international). That is, gap = `status='unmatched' or (status='matched' and not exists (… matched activity in qa and intl …))`.
- In `partnership_reject`, revert matches to `unmatched` and log it.
- Optionally, restrict `match_known_activity` to verified (or in-verification) activities only.

### H4. Changing Jenis during a Partnership revision can deadlock the unit, and leaves orphan pending versions (R-24, R-11/R-12)
**Files:**
- `0003_core.sql:224-231` (`_can_edit_participants`): the unit may edit participants only when `mobility_status='revision_requested'`, or when partnership is in revision *and* mobility is `not_required`.
- `0007_rpc_submission.sql:742-754`: resubmit copies the latest version into a new pending version.

**Problem:** suppose mobility is `pending` or `approved` and the unit fixes Jenis from outbound to inbound in a Partnership revision. Then:
- R-12 fails at resubmit.
- The unit cannot edit participants, so it can neither resubmit nor fix the data. Only reverting the Jenis gets it out.

For an outbound→outbound change (type 1→7), resubmit creates v2 `pending` while v1 stays `pending`. `mobility_approve` approves v2 and v1 stays `pending` forever.

**Repro:**
```sql
-- FTI: draft type 1 + 1 internal student + IA/IR, submit; Partnership: request_revision; FTI: save_activity_draft(id,'{"type_id":2}')
select realisasi.submit_activity(id);       -- R12_INBOUND_STUDENT_REQUIRED
select realisasi.save_participants(id, '[{"section":"inbound","nrp":"X01260012","home_institution":"Kyoto"}]','[]');
                                            -- STATE_INVALID  -> stuck
-- with type 1 -> 7: versions after resubmit = v1 pending, v2 pending; after mobility_approve = v1 pending, v2 approved
```

**Fix:**
- Allow unit participant edits whenever `partnership_status='revision_requested'`, whatever the mobility status. `submit_activity` already promotes a draft version and resets mobility.
- When promoting a new version, mark any older `pending` version `superseded`. Alternatively, add a partial unique index `one_pending_pset (activity_id) where status='pending'` to enforce it.

### H5. `storage_put` silently overwrites already-registered files, including IA/IR of verified and frozen activities (R-30, R-31, R-64)
**File:** `0008_rpc_files.sql:58-61` (`on conflict (path) do update set data = …`).

**Problem:** anyone with file-write permission can re-PUT the path of an existing registered IA/IR/evidence blob. The bytes are replaced with no new version, no `activity_files` row and no log. This includes Partnership on any verified activity, including activities inside a frozen window, and the unit during revision. That breaks the update log (R-30), "Perubahan Pasca-Beku" (R-31) and "no hard deletes" (R-64).

**Repro:**
```sql
-- as io.partnership, S-05 (verified, Ganjil 2025/2026 = frozen)
select realisasi.storage_put('<current IA path of S-05>','application/pdf', convert_to('%PDF-1.4 SILENTLY REPLACED','UTF8'));
-- md5 changed 360af7cd… -> f909ea08…, activity_log rows 4 -> 4, IA versions 1 -> 1
```

**Fix:** make blobs immutable. Use plain `insert` and raise `VALIDATION_INVALID`/`FILE_FORBIDDEN` on conflict, or allow overwrite only while no `activity_files` / `participant_students.transcript_path` row references the path. Paths already contain a fresh uuid, so legitimate clients never need an overwrite.

### H6. Dashboard and freeze scale with units × documents: the per-unit recursion re-evaluates `v_chains` (a recursive function per document) every time
**Files:**
- `0012_kpi.sql:174-185`: `compute_kpis` calls itself once per unit. Each call runs `_kpi_items`, whose `ch` CTE scans `v_chains`, and `_kpi_values` joins `v_chains` again.
- `0004_views.sql:12-39`: `v_chains` calls `chain_root()` (a recursive CTE) for every document and `chain_current()` for every chain.

**Measured** (`dashboard(2,'live',null)` as admin):

| Data | Time | Notes |
|---|---|---|
| Seed: 26 docs, 9 units | 96 ms | 816 `chain_root` calls, 16 `compute_kpis` calls |
| +1,500 docs, +50 units | **4.9 s** | |
| `v_chains` alone | 12 ms | |

Production SIM Kerjasama data will be in the second range. The landing page, `freeze_snapshot` and `refreeze` all pay this cost. `agreement_realization` (`0014:546`, `chain_root(x.id) = v_chain` over all documents) and `agreement_flags` (`0014:596`) also call `chain_root` per document.

**Fix:**
- Compute the chain map once per call: a single recursive CTE over `public.documents` giving `(doc_id, root_id, depth)`, or a materialised `realisasi.chain_map` refreshed by trigger or job. Load it into a temp table at the start of `compute_kpis`.
- Build `by_unit` from **one** item computation that carries `unit_id` (join `activity_units` and `document_scope_units` once, group by unit) instead of N recursive `compute_kpis` calls.
- Add a regression timing test with ~1,000 documents.

---

## MEDIUM

### M1. `edit_verified_activity` can change Jenis without R-11/R-12/R-24 checks, silently changing KPI 1.1
**File:** `0009_rpc_verification.sql:142-167`.

**Problem:** Partnership can change `type_id` of a verified activity. Nothing re-validates the participant set and mobility is not reset:
- S-24 (Joint Seminar, no participants) becomes a verified *Student Outbound* activity with 0 students.
- S-15 (outbound, 3 internal students) becomes *Inbound*, and its students quietly drop out of KPI 1.1.

**Repro:**
```sql
select realisasi.edit_verified_activity('…24','{"type_id":1}','x');
select realisasi.edit_verified_activity('…15','{"type_id":2}','x');
-- KPI 1.1 AY 2025/2026 outbound 14 -> 11; S-24 verified, mobility not_required, 0 versions
```

**Fix:** when `type_id` changes on a verified activity, require the approved set (or a mobility draft committed in the same flow) to satisfy R-11/R-12 for the new type. Otherwise raise `R12_*`/`R11_*`. Alternatively, forbid Jenis changes post-verification for Partnership and route them through io_admin with the same checks.

### M2. Frozen snapshot participant exports drift after post-freeze edits (R-56, R-59, AT-12)
**File:** `0014_reads.sql:277-302`. `kpi_participant_rows` joins the **current** `approved` version (`v.status='approved'`) to the snapshot's `activity:nrp` items.

**Problem:** after a post-freeze participant edit, removed students vanish from the frozen snapshot's export, while the snapshot still counts them.

**Repro:** Genap 2025/2026 snapshot: kpi_1_1.total 19, export rows 19. Commit a participant edit on S-15 that removes 2 students: total 19, export rows **17**.

**Fix:** store the pset version id in the item, e.g. `ref_id = '<activity>:<nrp>:<version_id>'`, or add an `activity_id`/`set_version_id` column to `kpi_snapshot_items`, and join on that version. Superseded versions are kept read-only, so the rows remain available.

### M3. "Previous snapshot" = latest `frozen_at` of any AY, so one re-freeze breaks late-addition reporting (R-57, R-58)
**Files:** `0013_snapshots.sql:4-9` (`_prev_snapshot`), used at l.44 and l.98.

**Problem:** re-freezing an old snapshot gives it a new `frozen_at = now`. It then becomes "P" for the next scheduled freeze. Genap activities verified late are then no longer listed.

**Repro:** S-08 (Genap 2025/2026) gets `verified_at = 2026-10-15`.

| Scenario | Ganjil 2026/2027 freeze lists S-08 as late? |
|---|---|
| (A) No re-freeze | Yes, previous = "Genap 2025/2026 (Setahun)" |
| (B) Ganjil 2025/2026 re-frozen on 2026-10-01 first | **No** (0 late rows) |

**Fix:** define P by period order, not by `frozen_at`. P = the live snapshot of the immediately preceding period: (AY, ganjil) → (AY-1, genap), (AY, genap) → (AY, ganjil). A re-freeze keeps its period's P.

### M4. `freeze_snapshot` trusts caller-supplied `p_as_of` and `p_actor` (audit spoofing, future-dated freezes)
**Files:** `0013_snapshots.sql:71-78` and `0015_jobs.sql:18`.

**Problem:** an io_admin can freeze a period before its cutoff, with `frozen_at` in the future and attributed to any profile.

**Repro:**
```sql
select realisasi.freeze_snapshot(2,'ganjil_ytd','2027-03-02 01:00+07','…0003');
-- frozen_at 2027-03-01 18:00Z (future), frozen_by_name "IO Mobility"
```

Both functions also skip all checks when `auth.uid()` is null. That includes any `authenticated` connection with empty claims (amendment 1 notes this happens on pooled connections).

**Fix:**
- Honour `p_as_of`/`p_actor` only for the system caller (`auth.uid() is null` **and** `current_user` not in (`authenticated`,`anon`)). For users, force `as_of = now_ts()`, `actor = auth.uid()` and `cutoff_date <= today()` (or require a reason).
- Use the same `current_user` guard in `run_daily_jobs`.

### M5. Linking activities in a frozen window changes KPIs but is not a "post-freeze change" (R-31)
**File:** `0010_rpc_duplicates_known.sql:30-33`. `_merge_groups` logs kind `verification`, so `_log` sets `in_frozen_period=false`. `unlink_activity` uses kind `update` and *is* flagged, which is inconsistent.

**Repro:** `link_activities(S-15, S-15b)` changes live AY 2025/2026 outbound from 14 to 13. Both logs have `in_frozen_period = f`, so the change is absent from the next report.

**Fix:** compute `in_frozen_period` for `link_duplicate` when the activity is verified. One option is `_log` computing it for any kind when `status='verified'`; another is logging the merge on verified activities as kind `update`.

### M6. Partnership (counts only) can read NRPs and row notes through `activity_log`
**Files:** `0009_rpc_verification.sql:135-136` (diff `row_notes` with NRP and note) and `:200-210` (`commit_participant_edit` diff of added/removed NRPs and employee ids). The log is readable by Partnership through the RLS policy at `0006_rls.sql:278` and through `activity_detail.log` (`0014:450-453`).

**Repro:** as io.partnership, `select diff from activity_log where action='edit'` after a mobility edit returns `{"students":{"removed":["D31245931","D32237864"]}…}`. `participant_students` returns 0 rows for the same user.

**Fix:** store participant diffs as counts in the shared log (e.g. `{"students":{"added":2,"removed":1}}`) and keep identifiers in a mobility-only table/column. Alternatively, mask `diff`/`note` for `track='mobility'` rows unless `can_view_participants`.

### M7. Read RPCs disclose data that Rules §10 / Schema §6 hide
**Files:** `0014_reads.sql:519-576` (`agreement_realization`) and `0014_reads.sql:231-241` (`kpi_drilldown` S8 known rows).

**Problems:**
- `agreement_realization` lists every verified activity on the chain (code, name, units) to any submitter. As FSD, `agreement_realization(905)` returns FTI's S-20, while RLS shows FSD 0 activities on that chain. Rules: submitters view own and co-unit activities only.
- `kpi_drilldown(...,'1.19.S8','unmatched_known')` returns known-activity titles, partners and source references to viewers and submitters. Rules §10: the Known Activities register is not available to these roles; the `known_activities` RLS is `is_io()`.

**Fix:**
- In `agreement_realization`, filter `v_acts` with `can_view_activity(a.id)` for non-IO users, or return counts only.
- Return known rows only when `is_io()`, otherwise counts, or titles without `source_reference`.

### M8. `register_activity_file` trusts the caller's `p_mime`/`p_size_bytes` (R-13 bypass)
**File:** `0008_rpc_files.sql:120-134`. The code uses `coalesce(p_mime, b.mime)`.

**Repro:** upload a PNG to `…/ia/x.png` (mime `image/png` is allowed for that bucket), then register it as IA with `p_mime => 'application/pdf'`. Result: an IA with `registered_mime=application/pdf`, `blob_mime=image/png`, magic `89504e47`.

**Fix:** always use `b.mime` and `b.size_bytes` from `file_blobs` and ignore the caller's values. For `ia`/`ir`, additionally require the blob to start with `%PDF-`.

### M9. `demo_today` is a production hazard: one admin setting shifts `today()`/`now_ts()` for everyone
**Files:** `0003_core.sql:4-18` and `0011_rpc_admin.sql:34-39`.

**Problem:** with `demo_today = '2027-09-01'`:
- `run_daily_jobs` immediately freezes 2026/2027 Ganjil and Genap with as-of = their cutoffs. These are permanent snapshots of incomplete data.
- Every `verified_at`, `submitted_at` and log is stamped in the future, and R-08 accepts activities that have not ended.

**Fix:** allow `demo_today` only when a deployment flag is set (e.g. `current_setting('app.demo_mode', true) = 'on'` or an env-provisioned row the RPC cannot write). In `run_daily_jobs`, freeze only when the real date has passed the cutoff (`cutoff_date <= (now() at time zone 'Asia/Jakarta')::date`).

### M10. RLS and list views call per-row definer helpers, giving O(rows) role lookups
**Files:**
- `0006_rls.sql:251-279`: `can_view_activity(id)` per row, which itself runs `my_role()`/`my_unit()` lookups per call.
- `0004_views.sql:41-86`: per row `sla_days` → `business_days_between` (generate_series), `activity_linked_count` and a `duplicate_open` subquery.

**Measured** at 6.2k activities:

| Query | Time |
|---|---|
| `v_activity_list` as FTI | 635 ms |
| `v_activity_list` as viewer | 388 ms |
| Partnership queue | 303 ms |

**Fix:**
- Inline policies so the role and unit are evaluated once as initplans. Example: `using ((select realisasi.my_role()) in ('io_staff','io_admin') or ((select realisasi.my_role())='viewer' and status='verified') or exists (select 1 from realisasi.activity_units au where au.activity_id = id and au.unit_id = (select realisasi.my_unit())))`.
- Mark `business_days_between` `parallel safe` and compute it from a calendar table, or a closed-form weekday count minus a holidays count.
- Replace `activity_linked_count` with a window `count(*) over (partition by event_group_id)`.

---

## LOW

### L1. A rejected (terminal) activity's participants remain editable
**Files:** `0003_core.sql:224-231` and `0014_reads.sql:356`.

**Problem:** `_can_edit_participants` does not exclude `status='rejected'`. If Mobility requested a revision before Partnership rejected, the unit can still create v2 and save rows. Repro: S-16 with P pending → reject → `ensure_participant_draft` and `save_participants` succeed, leaving v2 `draft` on a rejected activity. `activity_detail.permissions.can_submit` is also true there.

**Fix:** add `a.status <> 'rejected'` to both.

### L2. Orphan `pending` participant versions
**File:** `0007_rpc_submission.sql:742-767` (see H4).

**Fix:** supersede older pending versions on promotion, or add a unique partial index on `status='pending'`.

### L3. Duplicate detection gaps (R-33)
**File:** `0007_rpc_submission.sql:731`.

**Problems:**
- `_scan_duplicates` runs only on the first submit. It does not run on resubmit after name, date or agreement changes, nor after `edit_verified_activity`.
- Two activities submitted concurrently each see the other as `draft` (READ COMMITTED), so neither scan finds the pair.

**Fix:** rescan on resubmit and on verified edits. Add a daily rescan in `run_daily_jobs`, or take `pg_advisory_xact_lock(chain_id)` for every chain of the activity before scanning.

### L4. Event-group edge cases
**File:** `0010_rpc_duplicates_known.sql`.

**Problems:**
- `unlink_activity` on the middle member of a 3-member group dismisses A–B and B–C, but A and C stay in the same group with no `linked` candidate.
- `link_duplicates` (l.37-48) does not check that both activities are still non-rejected, unlike `link_activities`.
- An `open` candidate whose pair is already in one group raises `DUP_SAME_GROUP` and can never be linked, only dismissed.

**Fix:**
- On unlink, recompute group membership from the remaining `linked` candidates (connected components).
- Add the status check to `link_duplicates`.
- Auto-resolve open candidates whose pair already shares a group.

### L5. Granted definer helpers allow probing any activity id; registry lookup is open to every role
**Files:** `0016_grants.sql:125-133` and `0007_rpc_submission.sql:4-16`.

**Problems:**
- `activity_participant_total`, `activity_linked_count`, `in_frozen_period` and `is_late_addition` accept any uuid and ignore `can_view_activity`.
- `lookup_students` returns full name, faculty and status for arbitrary NRP arrays to viewers and Partnership. NRPs follow a guessable pattern, so the registry can be enumerated.

**Fix:**
- Return null unless `can_view_activity(p)`.
- Restrict `lookup_students`/`lookup_employees` to submitter, mobility and io_admin, and cap the array length.

### L6. `search_path` order puts `public` before `extensions`
**Files:** all functions (`set search_path = realisasi, public, extensions, pg_temp`).

**Problem:** on Supabase, `pg_trgm` lives in `extensions`. If any role ever gets CREATE on `public`, a `public.similarity(text,text)` would shadow it inside definer functions.

**Fix:** use `realisasi, extensions, public, pg_temp`, or schema-qualify `extensions.similarity`. Keep CREATE on `public` revoked.

### L7. Concurrency nits
- **Deadlock risk:** `_merge_groups` (`0010:16-17`) locks `a` then `b` in argument order. `link_activities(A,B)` running concurrently with `link_activities(B,A)` or `link_duplicates` can deadlock. Lock both with `order by id for update`.
- **Freeze/verify race:** a verification whose `verified_at` is earlier than a concurrent freeze's `as_of` but commits after the freeze's snapshot is neither in the snapshot nor a late addition. Take `lock table realisasi.kpi_snapshots in share row exclusive mode` in `_freeze`, plus a matching lock in the verify RPCs, or use `verified_at = clock_timestamp()` at commit time via a deferred trigger.

### L8. Derived values that never refresh
- `activity_documents.chain_id` (`0005:187-195`) is stored once. If SIM Kerjasama later sets `predecessor_id` on a root document, the stored id no longer matches `v_chains.chain_id`, and the KPI 1.19.24 numerator misses the activity. Resolve it via the chain map at query time, or refresh it with a job.
- `reporting_deadline` is only recomputed when `end_date` changes. Changing the `reporting_deadline_days` setting leaves existing drafts' deadlines and reminders on the old value. Recompute drafts in `update_settings`.

### L9. Rule nits
- **R-52:** `known_match_suggestions` (`0010:195-196`) compares only `start_date`. A multi-week activity whose span contains the known date is missed if it started more than 7 days earlier. Use `k.activity_date between a.start_date - w and a.end_date + w`.
- **R-11:** not enforced in `commit_participant_edit` (`0009:192-197`). Mobility can commit an empty set for a `requires_mobility_review` type with direction `none`, e.g. Staff Outbound.
- **R-63:** `kpi_participant_rows` returns personal data without writing `export_log` itself. It relies on the app calling `log_export`. Consider logging inside the RPC.

### L10. Missing indexes on FKs and audit columns
These are small today but need to be indexed before production volumes:
- `activities.created_by`
- `activity_log.actor_id`
- `known_activities.created_by`, `known_activities(status) where is_international`
- `activity_files.uploaded_by`
- `participant_set_versions.submitted_by`, `participant_set_versions.reviewed_by`
- `event_groups.created_by`
- `kpi_snapshots.frozen_by`
- `activity_external_persons.country_code`

`activity_log (activity_id, action, created_at)` would also help the R-24 lookups and the `activity_detail` revision lookups.

---

## Repro notes
- **Repro location:** all SQL was run in `postgresql://postgres@localhost:54322/sim_realisasi_review`. Each script used `supabase/tests/_helpers.inc` (`:as_part`, `:as_fti`, …) inside `begin … rollback`.
- **H6/M10 timings:** synthetic rows were added inside a rolled-back transaction: 1,500 documents, 50 units and 6,200 cloned activities.
- **Seed idempotency:** checked by re-running every `supabase/seed/*.sql` on the seeded review DB. Row counts were unchanged.
