/**
 * PCU Design System tokens, app layer (Formal register): the one place colour values live.
 * Source: "PCU Design System" (Brand Guideline Petra 2026, DRAFT 3; hex values provisional until MRD confirms).
 * Tailwind (tailwind.config.ts) and the charts (components/realisasi/dashboard/viz.ts) both read from here;
 * the shadcn HSL variables in app/globals.css carry the same values.
 *
 * Rules carried over from the design system:
 * - `midnight` leads; secondary hues are accents and never replace it.
 * - Every colour has one meaning, and every status also has a text label.
 * - Signal hues (`DEFAULT`) are for dots, borders and fills. Anything read uses the `fg` variant (≥ 4.5:1 on
 *   white and on its own `subtle` tint).
 * - Red is reserved for errors and irreversible actions.
 */

export const pcu = {
  midnight: '#19304b',
  black: '#000000',
  white: '#ffffff',
  smoke: '#f1f1f1',
  border: '#e2e5e9',
  textPrimary: '#000000',
  textSecondary: '#46505c',
  /** 5.4:1 on white, 4.8:1 on smoke. */
  textMuted: '#5f6b78',
  statusDraft: '#7b8794',
  /** White text on it: 6:1. Also the focus ring. */
  progressStrong: '#2a64a8',
  emerald: '#135d50',
  amber: '#ffbc00',
} as const;

/**
 * Tone families. `DEFAULT` = the design system's signal hue; `fg` = text-safe ink; `subtle` / `line` = the tinted
 * ground and hairline for notes and highlighted rows.
 * `danger.fg` and `renewal.fg` are additions: the design system has no text-safe red or purple for tinted grounds
 * (`red` is 4.1:1 on its tint).
 */
export const tones = {
  /** status-progress — submitted, waiting, in verification; informational notes. */
  info: { DEFAULT: '#3880d0', fg: '#2a64a8', subtle: '#edf4fb', line: '#b9d3f0' },
  /** status-pending — Perlu Revisi; consequential, rare, loud. */
  pending: { DEFAULT: '#f37121', fg: '#b34700', subtle: '#fef1e8', line: '#f8c4a2' },
  /** sla-yellow — approaching a limit; cautions. */
  warning: { DEFAULT: '#ffbc00', fg: '#8a6100', subtle: '#fff8e1', line: '#f5d77a' },
  /** status-active — verified, approved, done. Ink is `emerald`, the design system's text-safe green. */
  success: { DEFAULT: '#6aaa43', fg: '#135d50', subtle: '#eff6ea', line: '#bcdba8' },
  /** action-danger / sla-red — errors, blocking problems, irreversible actions. */
  danger: { DEFAULT: '#e31f26', fg: '#b3161c', subtle: '#fdeced', line: '#f4b3b5' },
  /** renewal-request — duplicates and other "look at this pair" cases; never confused with blue. */
  renewal: { DEFAULT: '#be93e4', fg: '#6b3fa0', subtle: '#f6f0fc', line: '#d9c3f0' },
  /** status-draft / status-archived — inert. */
  neutral: { DEFAULT: '#7b8794', fg: '#46505c', subtle: '#f1f1f1', line: '#e2e5e9' },
} as const;
