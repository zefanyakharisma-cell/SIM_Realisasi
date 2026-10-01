/**
 * Shared domain types (CONTRACTS §6.5). Field-for-field mirrors of the SQL enums, RPC payloads
 * and JSON read models in CONTRACTS §2–§5. Pure types: safe to import from client components.
 *
 * Wire conventions: `date` → DateString 'YYYY-MM-DD'; `timestamptz` → Timestamp (ISO-8601);
 * bigint/numeric → number (see lib/db.ts).
 */
import type { Role as SessionRole, Team as SessionTeam } from '@/lib/session';

// ---------------------------------------------------------------------------
// Aliases & enums
// ---------------------------------------------------------------------------

export type DateString = string;
export type Timestamp = string;
export type Uuid = string;

export type ActivityStatus = 'draft' | 'in_verification' | 'revision_requested' | 'verified' | 'rejected';
export type TrackStatus = 'not_required' | 'pending' | 'revision_requested' | 'approved' | 'rejected';
export type Direction = 'inbound' | 'outbound' | 'none';
export type ActivityMode = 'offline' | 'online' | 'hybrid';
export type FundingSource = 'pcu' | 'partner' | 'government' | 'participant' | 'mixed' | 'none';
export type FileKind = 'ia' | 'ir' | 'evidence';
export type PersonRole = 'speaker' | 'visiting_lecturer' | 'researcher' | 'staff_visitor' | 'other';
export type StudentSection = 'internal' | 'inbound';
export type PsetStatus = 'draft' | 'pending' | 'revision_requested' | 'approved' | 'superseded';
export type KnownSource = 'surat_tugas' | 'news' | 'faculty_report' | 'loa_visa_letter' | 'email' | 'other';
export type KnownStatus = 'unmatched' | 'matched' | 'dismissed';
export type SemesterTerm = 'ganjil' | 'genap';
export type SnapshotKind = 'ganjil_ytd' | 'genap_full_year';
export type DupStatus = 'open' | 'linked' | 'dismissed';
export type LogKind = 'verification' | 'revision' | 'update' | 'system';
export type Team = SessionTeam;
export type Role = SessionRole;
export type SlaLevel = 'ok' | 'yellow' | 'red';
export type Period = 'ganjil' | 'full' | 'live';
export type KpiCode = '1.1' | '1.19.S1' | '1.19.24' | '1.19.S8';
export type DrilldownKpi = KpiCode | 'base';
export type RejectReason = 'duplicate' | 'not_partnership' | 'wrong_agreement' | 'other';
export type RegistryStudentStatus = 'active' | 'graduated' | 'inactive';
export type RegistryEmployeeStatus = 'active' | 'inactive';

export type ExportKind =
  | 'activities'
  | 'participants'
  | 'kpi-summary'
  | 'kpi-drilldown'
  | 'chart'
  | 'snapshot'
  | 'snapshot-archive'
  | 'realization-by-agreement'
  | 'sla'
  | 'known-activities'
  | 'duplicates'
  | 'agreement-activities';

export type ActionResult<T> = { ok: true; data: T } | { ok: false; code: string; message: string; detail?: unknown };

// ---------------------------------------------------------------------------
// Payloads (client → RPC)
// ---------------------------------------------------------------------------

export interface ExternalPersonPayload {
  full_name: string;
  institution: string;
  country_code: string;
  role: PersonRole;
  notes: string | null;
}

/** `save_activity_draft` / `edit_verified_activity` payload (CONTRACTS §3.2). */
export interface ActivityDetailPayload {
  name: string;
  type_id: number;
  start_date: DateString;
  end_date: DateString;
  mode: ActivityMode;
  venue: string | null;
  city: string | null;
  country_code: string | null;
  sks_recognized: number | null;
  funding_source: FundingSource | null;
  description: string;
  submitter_unit_id: number;
  co_unit_ids: number[];
  document_ids: number[];
  sdg_ids: number[];
  external_persons: ExternalPersonPayload[];
}

export interface StudentRowPayload {
  section: StudentSection;
  nrp: string;
  home_institution?: string | null;
  home_student_number?: string | null;
  home_country_code?: string | null;
  transcript_path?: string | null;
}

export interface StaffRowPayload {
  employee_id: string;
}

export interface RowNotePayload {
  kind: 'student' | 'staff';
  id: string;
  note: string;
}

export interface KnownActivityPayload {
  title: string;
  activity_date: DateString;
  unit_id: number | null;
  partner_name: string | null;
  country_code: string | null;
  is_international: boolean;
  source: KnownSource;
  source_reference: string | null;
  notes: string | null;
}

export interface ActivityTypePayload {
  name: string;
  direction: Direction;
  counts_as_mobility: boolean;
  counts_for_s1: boolean;
  requires_mobility_review: boolean;
  is_active: boolean;
  sort_order: number;
}

/** All `realisasi.settings` keys (CONTRACTS §2.3). */
export interface SettingsValues {
  grace_period_months: number;
  reporting_deadline_days: number;
  sla_yellow_days: number;
  sla_red_days: number;
  revision_reminder_days: number;
  revision_escalate_days: number;
  dup_date_window_days: number;
  dup_name_similarity: number;
  known_match_window_days: number;
  known_name_similarity: number;
  nudge_resend_days: number;
  deadline_reminder_before_days: number;
  demo_today: DateString | null;
}

// ---------------------------------------------------------------------------
// RPC results (CONTRACTS §3)
// ---------------------------------------------------------------------------

export interface ActivityStatusResult {
  id: Uuid;
  status: ActivityStatus;
  partnership_status: TrackStatus;
  mobility_status: TrackStatus;
  verified_at: Timestamp | null;
}

export type SubmitResult = ActivityStatusResult & { is_late: boolean; duplicates_found: number };

export interface SaveParticipantsWarning {
  section: StudentSection | 'staff';
  id: string;
  status: RegistryStudentStatus | RegistryEmployeeStatus;
}

export interface SaveParticipantsResult {
  version_id: Uuid;
  version: number;
  students: number;
  staff: number;
  warnings: SaveParticipantsWarning[];
}

export interface ChecklistItem {
  code: string;
  ok: boolean;
  message: string;
  /** Only on the trailing `LATE_NOTICE` item. */
  late?: boolean;
}

export interface RegisteredFile {
  id: number;
  kind: FileKind;
  version: number;
  storage_path: string | null;
  href: string;
}

export interface DocumentPartnerOption {
  partner_id: number;
  name: string;
  country_code: string;
  country_name: string;
  is_lead: boolean;
}

/** Row of `documents_valid_between()`. */
export interface DocumentOption {
  document_id: number;
  doc_number: string;
  title: string;
  kind: 'MoU' | 'MoA';
  status: string;
  start_date: DateString | null;
  end_date: DateString | null;
  auto_renewed: boolean;
  is_archived: boolean;
  chain_id: number;
  current_doc_number: string;
  partners: DocumentPartnerOption[];
  in_scope: boolean;
}

/** `mock_baak.students` row (via `lookup_students`). */
export interface StudentRecord {
  nrp: string;
  full_name: string;
  faculty_code: string;
  faculty_name: string;
  prodi_name: string;
  category: 'regular' | 'inbound_exchange';
  home_institution: string | null;
  home_country_code: string | null;
  intake_year: number;
  status: RegistryStudentStatus;
}

/** `mock_hr.employees` row (via `lookup_employees`). */
export interface EmployeeRecord {
  employee_id: string;
  full_name: string;
  unit_name: string;
  position: string | null;
  status: RegistryEmployeeStatus;
}

// ---------------------------------------------------------------------------
// Views (CONTRACTS §2.7)
// ---------------------------------------------------------------------------

/** `realisasi.v_activity_list`. */
export interface ActivityListRow {
  id: Uuid;
  code: string;
  name: string;
  type_id: number;
  type_name: string;
  direction: Direction;
  start_date: DateString;
  end_date: DateString;
  academic_year_id: number | null;
  ay_label: string | null;
  semester_id: number | null;
  semester_label: string | null;
  mode: ActivityMode;
  status: ActivityStatus;
  partnership_status: TrackStatus;
  mobility_status: TrackStatus;
  partnership_since: Timestamp | null;
  mobility_since: Timestamp | null;
  partnership_sla_days: number | null;
  partnership_sla_level: SlaLevel | null;
  mobility_sla_days: number | null;
  mobility_sla_level: SlaLevel | null;
  submitter_unit_id: number;
  submitter_unit_name: string;
  unit_ids: number[];
  unit_names: string[];
  document_ids: number[];
  document_numbers: string[];
  chain_ids: number[];
  partner_names: string[];
  country_codes: string[];
  is_international: boolean;
  is_late: boolean;
  reporting_deadline: DateString | null;
  submitted_at: Timestamp | null;
  verified_at: Timestamp | null;
  created_at: Timestamp;
  updated_at: Timestamp;
  created_by: Uuid;
  out_of_scope: boolean;
  duplicate_open: boolean;
  event_group_id: Uuid;
  linked_count: number;
}

/** `realisasi.v_known_activities`. */
export interface KnownActivityRow {
  id: number;
  title: string;
  activity_date: DateString;
  unit_id: number | null;
  partner_name: string | null;
  country_code: string | null;
  is_international: boolean;
  source: KnownSource;
  source_reference: string | null;
  notes: string | null;
  status: KnownStatus;
  matched_activity_id: Uuid | null;
  nudged_at: Timestamp | null;
  created_by: Uuid | null;
  created_at: Timestamp;
  unit_name: string | null;
  country_name: string | null;
  matched_activity_code: string | null;
  matched_activity_name: string | null;
  created_by_name: string | null;
  can_nudge: boolean;
}

/** `known_match_suggestions()` element. */
export interface KnownSuggestion {
  activity_id: Uuid;
  code: string;
  name: string;
  start_date: DateString;
  end_date: DateString;
  unit_names: string[];
  status: ActivityStatus;
  score: number;
}

/** `realisasi.v_duplicate_candidates`. */
export interface DuplicateCandidateRow {
  id: number;
  score: number;
  status: DupStatus;
  resolved_by_name: string | null;
  resolved_at: Timestamp | null;
  a_id: Uuid;
  a_code: string;
  a_name: string;
  a_unit_name: string;
  a_start_date: DateString;
  a_end_date: DateString;
  a_status: ActivityStatus;
  a_documents: string[];
  a_participants: number;
  b_id: Uuid;
  b_code: string;
  b_name: string;
  b_unit_name: string;
  b_start_date: DateString;
  b_end_date: DateString;
  b_status: ActivityStatus;
  b_documents: string[];
  b_participants: number;
}

// ---------------------------------------------------------------------------
// Activity detail & participants (CONTRACTS §4.7)
// ---------------------------------------------------------------------------

export interface ActivityPermissions {
  can_edit_draft: boolean;
  can_delete_draft: boolean;
  can_edit_detail: boolean;
  can_edit_files: boolean;
  can_edit_participants: boolean;
  can_submit: boolean;
  can_partnership_verify: boolean;
  can_reject: boolean;
  can_mobility_verify: boolean;
  can_edit_verified_detail: boolean;
  can_edit_verified_participants: boolean;
  can_link_duplicate: boolean;
  can_unlink_duplicate: boolean;
  can_view_participants: boolean;
  can_view_log: boolean;
}

export interface ParticipantCounts {
  version: number;
  status: PsetStatus;
  internal_students: number;
  inbound_students: number;
  staff: number;
}

export interface ActivityLogEntry {
  id: number;
  kind: LogKind;
  track: Team | null;
  action: string;
  actor_name: string | null;
  note: string | null;
  diff: Record<string, unknown> | null;
  in_frozen_period: boolean;
  created_at: Timestamp;
}

export interface ActivityFile {
  id: number;
  kind: FileKind;
  version: number;
  storage_path: string | null;
  url: string | null;
  filename: string | null;
  size_bytes: number | null;
  mime: string | null;
  is_current: boolean;
  uploaded_by_name: string | null;
  uploaded_at: Timestamp;
  href: string;
}

export interface ParticipantVersionSummary {
  id: Uuid;
  version: number;
  status: PsetStatus;
  submitted_at: Timestamp | null;
  submitted_by_name: string | null;
  reviewed_at: Timestamp | null;
  reviewed_by_name: string | null;
  review_note: string | null;
  internal_students: number;
  inbound_students: number;
  staff: number;
}

export interface TrackSla {
  days: number;
  level: SlaLevel;
}

export interface TrackRevision {
  note: string | null;
  requested_by_name: string | null;
  requested_at: Timestamp;
}

export interface ActivityDetail {
  id: Uuid;
  code: string;
  name: string;
  type: {
    id: number;
    name: string;
    direction: Direction;
    counts_as_mobility: boolean;
    counts_for_s1: boolean;
    requires_mobility_review: boolean;
  };
  start_date: DateString;
  end_date: DateString;
  duration_days: number;
  academic_year: { id: number; label: string } | null;
  semester: { id: number; term: SemesterTerm; label: string } | null;
  mode: ActivityMode;
  venue: string | null;
  city: string | null;
  country_code: string | null;
  country_name: string | null;
  sks_recognized: number | null;
  funding_source: FundingSource | null;
  description: string;
  submitter_unit: { id: number; name: string };
  units: Array<{ id: number; name: string; is_submitter: boolean }>;
  status: ActivityStatus;
  partnership_status: TrackStatus;
  mobility_status: TrackStatus;
  partnership_since: Timestamp | null;
  mobility_since: Timestamp | null;
  submitted_at: Timestamp | null;
  verified_at: Timestamp | null;
  rejection_reason: RejectReason | null;
  reporting_deadline: DateString | null;
  is_late: boolean;
  event_group_id: Uuid;
  linked_activities: Array<{ id: Uuid; code: string; name: string; unit_name: string; status: ActivityStatus }>;
  documents: Array<{
    original_document_id: number;
    original_doc_number: string;
    current_document_id: number;
    current_doc_number: string;
    kind: 'MoU' | 'MoA';
    title: string;
    chain_id: number;
    start_date: DateString | null;
    end_date: DateString | null;
    is_archived: boolean;
    out_of_scope_warning: boolean;
    partners: Array<{ partner_id: number; name: string; country_code: string; country_name: string }>;
  }>;
  partners: Array<{ document_id: number; partner_id: number; partner_name: string; country_code: string; country_name: string }>;
  is_international: boolean;
  sdg_ids: number[];
  external_persons: Array<{
    id: number;
    full_name: string;
    institution: string;
    country_code: string;
    role: PersonRole;
    notes: string | null;
  }>;
  files: ActivityFile[];
  participants: {
    can_view_rows: boolean;
    counts: ParticipantCounts | null;
    versions: ParticipantVersionSummary[];
  };
  sla: { partnership: TrackSla | null; mobility: TrackSla | null };
  revision: { partnership: TrackRevision | null; mobility: TrackRevision | null };
  rejection: { reason: RejectReason; note: string | null; rejected_by_name: string | null; rejected_at: Timestamp } | null;
  log: ActivityLogEntry[];
  duplicates: Array<{
    candidate_id: number;
    other_activity_id: Uuid;
    other_code: string;
    other_name: string;
    score: number;
    status: DupStatus;
  }>;
  flags: { late: boolean; out_of_scope: boolean; duplicate_open: boolean; late_addition: boolean };
  checklist: ChecklistItem[] | null;
  permissions: ActivityPermissions;
}

export interface ParticipantStudentRow {
  id: number;
  section: StudentSection;
  nrp: string;
  full_name: string;
  faculty_name: string | null;
  prodi_name: string | null;
  home_institution: string | null;
  home_student_number: string | null;
  home_country_code: string | null;
  transcript_path: string | null;
  transcript_href: string | null;
  row_note: string | null;
  registry_status: RegistryStudentStatus;
}

export interface ParticipantStaffRow {
  id: number;
  employee_id: string;
  full_name: string;
  unit_name: string | null;
  row_note: string | null;
  registry_status: RegistryEmployeeStatus;
}

export interface ParticipantVersion {
  id: Uuid;
  activity_id: Uuid;
  version: number;
  status: PsetStatus;
  submitted_at: Timestamp | null;
  submitted_by_name: string | null;
  reviewed_at: Timestamp | null;
  reviewed_by_name: string | null;
  review_note: string | null;
  students: ParticipantStudentRow[];
  staff: ParticipantStaffRow[];
}

// ---------------------------------------------------------------------------
// KPI engine & dashboard (CONTRACTS §4.3–§4.6)
// ---------------------------------------------------------------------------

export interface KpiTriple {
  numerator: number;
  denominator: number;
  grace_excluded: number;
  pct: number | null;
}

export interface MobilityBySemester {
  semester_id: number;
  term: SemesterTerm;
  label: string;
  inbound: number;
  outbound: number;
}

export interface KpiCharts {
  mobility_by_semester: MobilityBySemester[];
  by_country: Array<{ country_code: string; country_name: string; activities: number }>;
  by_unit: Array<{ unit_id: number; unit_name: string; activities: number }>;
  by_sdg: Array<{ sdg_id: number; name: string; activities: number }>;
  realization_by_unit: Array<{ unit_id: number; unit_name: string; numerator: number; denominator: number; pct: number | null }>;
  top_partners: Array<{ partner_id: number; partner_name: string; country_code: string; activities: number }>;
}

export interface KpiParams {
  from: DateString;
  to: DateString;
  cutoff: DateString;
  ay_id: number | null;
  as_of: Timestamp | null;
  unit_id: number | null;
  grace_period_months: number;
}

interface KpiBlocks {
  kpi_1_1: { inbound: number; outbound: number; total: number; by_semester: MobilityBySemester[] };
  kpi_1_19_s1: { international: number; domestic: number };
  kpi_1_19_24: { all: KpiTriple; international: KpiTriple; domestic: KpiTriple };
  kpi_1_19_s8: { reported: number; unmatched_known: number; pct: number | null };
  charts: KpiCharts;
}

export interface UnitKpiValues extends KpiBlocks {
  unit_id: number;
  unit_name: string;
}

export interface KpiValues extends KpiBlocks {
  params: KpiParams;
  /** Present only at university level (p_unit_id null). */
  by_unit?: UnitKpiValues[];
}

export interface PeriodInfo {
  ay_id: number;
  ay_label: string;
  period: Period;
  kind: SnapshotKind | null;
  label: string;
  window_start: DateString;
  window_end: DateString;
  cutoff: DateString;
  frozen: boolean;
  snapshot_id: Uuid | null;
  frozen_at: Timestamp | null;
  frozen_by_name: string | null;
  today: DateString;
  academic_years: Array<{ id: number; label: string }>;
}

export interface KpiScope {
  level: 'university' | 'unit';
  unit_id: number | null;
  unit_name: string | null;
}

export interface DashboardData {
  period: PeriodInfo;
  scope: KpiScope;
  values: KpiValues;
  previous: {
    ay_label: string;
    kpi_1_1: { total: number; inbound: number; outbound: number };
    kpi_1_19_s1: { international: number };
    kpi_1_19_24: { pct: number | null };
    kpi_1_19_s8: { pct: number | null };
  } | null;
  late_additions: number;
  drafts_near_deadline: Array<{
    id: Uuid;
    code: string;
    name: string;
    end_date: DateString;
    reporting_deadline: DateString;
    days_left: number;
  }>;
}

export interface ActivityKpiRow {
  row_type: 'activity';
  activity_id: Uuid;
  code: string;
  name: string;
  type_name: string;
  direction: Direction;
  unit_names: string[];
  partner_names: string[];
  country_codes: string[];
  start_date: DateString;
  semester_label: string | null;
  event_group_id: Uuid;
  linked_count: number;
  bucket: 'outbound' | 'inbound' | 'international' | 'domestic' | 'reported' | 'verified_activity';
  students: number | null;
  is_late_addition: boolean;
}

export interface ChainKpiRow {
  row_type: 'chain';
  chain_id: number;
  current_document_id: number;
  current_doc_number: string;
  doc_numbers: string[];
  kind: 'MoU' | 'MoA';
  title: string;
  partner_names: string[];
  country_codes: string[];
  is_international: boolean;
  chain_start: DateString;
  chain_end: DateString | null;
  auto_renewed: boolean;
  bucket: 'realized' | 'not_realized' | 'grace_excluded';
  grace_until: DateString | null;
  activities: Array<{ id: Uuid; code: string; name: string; start_date: DateString; original_doc_number: string }>;
  is_late_addition: boolean;
}

export interface KnownKpiRow {
  row_type: 'known';
  known_id: number;
  title: string;
  activity_date: DateString;
  unit_name: string | null;
  partner_name: string | null;
  country_code: string | null;
  source: KnownSource;
  source_reference: string | null;
}

export interface DrilldownResult {
  period: PeriodInfo;
  scope: KpiScope;
  kpi: DrilldownKpi;
  bucket: string | null;
  rows: Array<ActivityKpiRow | ChainKpiRow | KnownKpiRow>;
}

/** `kpi_participant_rows()` element (personal data). */
export interface KpiParticipantRow {
  activity_id: Uuid;
  code: string;
  name: string;
  direction: Direction;
  event_group_id: Uuid;
  section: StudentSection;
  nrp: string;
  full_name: string;
  faculty_name: string | null;
  prodi_name: string | null;
  home_institution: string | null;
  home_country_code: string | null;
  start_date: DateString;
  semester_label: string | null;
}

// ---------------------------------------------------------------------------
// Snapshots (CONTRACTS §4.4)
// ---------------------------------------------------------------------------

export interface SnapshotListRow {
  id: Uuid;
  ay_id: number;
  ay_label: string;
  kind: SnapshotKind;
  label: string;
  window_start: DateString;
  window_end: DateString;
  cutoff_date: DateString;
  frozen_at: Timestamp;
  frozen_by_name: string;
  is_live: boolean;
  superseded_by: Uuid | null;
  refreeze_reason: string | null;
  summary: {
    kpi_1_1_total: number;
    kpi_1_19_s1_international: number;
    kpi_1_19_24_pct: number | null;
    kpi_1_19_s8_pct: number | null;
  };
  late_additions: number;
  post_freeze_changes: number;
}

export interface LateAdditionRow {
  activity_id: Uuid;
  code: string;
  name: string;
  unit_names: string[];
  start_date: DateString;
  verified_at: Timestamp;
  previous_snapshot_id: Uuid | null;
  previous_snapshot_label: string | null;
  counted_in_this_snapshot: boolean;
  kpi_codes: string[];
}

export interface PostFreezeChangeRow {
  log_id: number;
  activity_id: Uuid;
  code: string;
  name: string;
  kind: LogKind;
  track: Team | null;
  action: string;
  actor_name: string | null;
  note: string | null;
  diff: Record<string, unknown> | null;
  created_at: Timestamp;
}

export interface SnapshotDetail {
  snapshot: SnapshotListRow;
  values: KpiValues;
  settings_used: Record<string, unknown>;
  late_additions: LateAdditionRow[];
  post_freeze_changes: PostFreezeChangeRow[];
}

// ---------------------------------------------------------------------------
// Agreements (CONTRACTS §4.8, §3.9)
// ---------------------------------------------------------------------------

export interface AgreementRealization {
  document: {
    id: number;
    doc_number: string;
    title: string;
    kind: 'MoU' | 'MoA';
    status: string;
    start_date: DateString | null;
    end_date: DateString | null;
    auto_renewed: boolean;
  };
  chain: {
    chain_id: number;
    chain_start: DateString | null;
    chain_end: DateString | null;
    auto_renewed: boolean;
    is_international: boolean;
    documents: Array<{
      id: number;
      doc_number: string;
      kind: 'MoU' | 'MoA';
      status: string;
      start_date: DateString | null;
      end_date: DateString | null;
      predecessor_id: number | null;
    }>;
  };
  current_ay: { id: number; label: string };
  summary: {
    total_activities: number;
    activities_this_ay: number;
    students_inbound: number;
    students_outbound: number;
    last_activity_date: DateString | null;
  };
  grace: { in_grace: boolean; grace_until: DateString | null };
  activities: Array<{
    id: Uuid;
    code: string;
    name: string;
    type_name: string;
    start_date: DateString;
    end_date: DateString;
    status: ActivityStatus;
    unit_names: string[];
    original_doc_number: string;
    current_doc_number: string;
  }>;
}

export interface AgreementFlag {
  document_id: number;
  chain_id: number;
  flag: 'realized' | 'not_realized' | 'grace' | 'inactive';
  grace_until: DateString | null;
  activities_this_ay: number;
  last_activity_date: DateString | null;
}

// ---------------------------------------------------------------------------
// Shell, notifications, jobs
// ---------------------------------------------------------------------------

/** `nav_counts()` — zeros where the role has no access. */
export interface NavCounts {
  partnership_queue: number;
  mobility_queue: number;
  duplicates_open: number;
  revision_inbox: number;
  unread_notifications: number;
}

/** `realisasi.notifications` row (own rows under RLS). */
export interface NotificationRow {
  id: number;
  recipient_id: Uuid;
  kind: string;
  title: string;
  body: string | null;
  link: string | null;
  read_at: Timestamp | null;
  created_at: Timestamp;
}

/** `run_daily_jobs()` (CONTRACTS §5.1). */
export interface DailyJobsResult {
  today: DateString;
  sla_notices: number;
  revision_reminders: number;
  revision_escalations: number;
  deadline_reminders: number;
  frozen: Array<{ snapshot_id: Uuid; ay_label: string; kind: SnapshotKind }>;
}
