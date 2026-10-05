import { pcu, tones } from '@/lib/design/tokens';

// Chart tokens from the PCU Design System. Series are told apart by lightness, not hue alone:
// blue 4.1:1 and midnight 13.4:1 on white (both clear the 3:1 graphics minimum; brand orange, 2.9:1, does not).
// The app shell is light-only; the dark set is kept so charts follow `.dark` / prefers-color-scheme if the
// shell adopts a dark theme later.
export const VIZ = {
  light: {
    series1: tones.info.DEFAULT, // PCU blue — Outbound / single-series bars
    series2: pcu.midnight, // midnight — Inbound
    grid: pcu.border,
    axis: '#c3c9d0',
    textSecondary: pcu.textSecondary,
    textMuted: pcu.textMuted,
    surface: pcu.white,
  },
  dark: {
    series1: '#3987e5',
    series2: '#d95926',
    grid: '#2c2c2a',
    axis: '#383835',
    textSecondary: '#c3c2b7',
    textMuted: '#898781',
    surface: '#1a1a19',
  },
} as const;

/** Sequential blue ramp (100 → 700) for the SDG heatmap; index 0 = "no activity". */
export const SEQ_BLUE = [pcu.smoke, '#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95', '#0d366b'] as const;

/** Picks a ramp step for `value` within [0, max]; zero always maps to the neutral cell. */
export function seqStep(value: number, max: number): number {
  if (value <= 0 || max <= 0) return 0;
  const steps = SEQ_BLUE.length - 1;
  return Math.max(1, Math.min(steps, Math.ceil((value / max) * steps)));
}

/** Ink for text set inside a filled cell: white on dark steps, primary ink on light ones. */
export function inkOn(step: number): string {
  return step >= 4 ? pcu.white : pcu.black;
}
