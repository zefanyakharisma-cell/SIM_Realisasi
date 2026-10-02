/** Pure conversions from `ActivityDetail` to form inputs (WP-SUBMIT). Client/server safe. */
import type { ActivityDetail, ActivityDetailPayload, DocumentOption } from '@/lib/realisasi/types';

export function detailToPayload(d: ActivityDetail): ActivityDetailPayload {
  return {
    name: d.name,
    agenda_id: d.agenda.id,
    direction: d.direction,
    start_date: d.start_date,
    end_date: d.end_date,
    mode: d.mode,
    venue: d.venue,
    country_code: d.country_code,
    sks_recognized: d.sks_recognized,
    description: d.description,
    submitter_unit_id: d.submitter_unit.id,
    co_unit_ids: d.units.filter((u) => !u.is_submitter).map((u) => u.id),
    document_id: d.documents[0]?.original_document_id ?? null,
    sdg_ids: d.sdg_ids,
    external_persons: d.external_persons.map((p) => ({
      full_name: p.full_name,
      institution: p.institution,
      country_code: p.country_code,
      role: p.role,
      notes: p.notes,
    })),
  };
}

export function detailDocumentsAsOptions(d: ActivityDetail): DocumentOption[] {
  return d.documents.map((x) => ({
    document_id: x.original_document_id,
    doc_number: x.original_doc_number,
    title: x.title,
    kind: x.kind,
    status: x.is_archived ? 'archived' : 'active',
    start_date: x.start_date,
    end_date: x.end_date,
    auto_renewed: false,
    is_archived: x.is_archived,
    chain_id: x.chain_id,
    current_doc_number: x.current_doc_number,
    partners: x.partners.map((p) => ({ ...p, is_lead: false })),
    in_scope: !x.out_of_scope_warning,
  }));
}

/** Latest version summary (draft included when visible) for counts on the review step. */
export function latestVersionSummary(d: ActivityDetail) {
  return [...d.participants.versions].sort((a, b) => b.version - a.version)[0] ?? null;
}
