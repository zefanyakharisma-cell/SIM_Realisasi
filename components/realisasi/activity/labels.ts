/**
 * WP-SUBMIT display helpers shared by the wizard and the activity detail page. Pure; client-safe.
 */
import { agendaRequirement } from '@/lib/realisasi/status';
import type { AgendaProgram, Direction } from '@/lib/realisasi/types';

// Diff field labels live in lib so the Excel builders share them (requirements review L-2).
export { DIFF_FIELD_LABEL, diffFieldLabel } from '@/lib/realisasi/diff-format';

/** Helper line under the Jenis select: the Keterangan, then what the Jenis requires (program + direction). */
export function agendaHelper(
  a: { program: AgendaProgram; description: string | null; counts_for_s1: boolean },
  direction?: Direction | null,
): string {
  const parts: string[] = [];
  if (a.description) parts.push(a.description);
  parts.push(agendaRequirement(a.program, direction));
  if (a.counts_for_s1) parts.push('Dihitung untuk RENSTRA 1.19.S1 bila bermitra internasional.');
  return parts.join(' ');
}

/** Which participant panels apply and which are mandatory (R-11 / R-12), by the Jenis program and direction. */
export interface ParticipantRequirements {
  /** At least one participant row is needed. */
  any: boolean;
  internal: boolean;
  inbound: boolean;
  /** PETRA staff mandatory (Faculty Mobility outbound). */
  staff: boolean;
  /** Student panels apply (not for Faculty Mobility). */
  students: boolean;
}

export const NO_PARTICIPANT_REQUIREMENTS: ParticipantRequirements = { any: false, internal: false, inbound: false, staff: false, students: true };

export function participantRequirements(a: { program: AgendaProgram; direction: Direction | null } | null | undefined): ParticipantRequirements {
  if (!a || a.program === 'other') return NO_PARTICIPANT_REQUIREMENTS;
  if (a.program === 'faculty_mobility') {
    // inbound: the external persons (Detail) are the participants; PETRA staff stay optional
    const out = a.direction === 'outbound';
    return { any: out, internal: false, inbound: false, staff: out, students: false };
  }
  return { any: true, internal: a.direction === 'outbound', inbound: a.direction === 'inbound', staff: false, students: true };
}
