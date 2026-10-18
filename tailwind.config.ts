import type { Config } from 'tailwindcss';
import animate from 'tailwindcss-animate';
import { pcu, tones } from './lib/design/tokens';

/**
 * Design tokens: PCU Design System, app layer (lib/design/tokens.ts).
 * - shadcn names (primary, muted, …) are CSS variables in app/globals.css, set to PCU values.
 * - Brand colours (`midnight`, `smoke`, …) and tone families (`info`, `pending`, `warning`, `success`, `danger`,
 *   `renewal`, `neutral`; each with DEFAULT · fg · subtle · line) come straight from the token file.
 * Use these instead of Tailwind's stock palette (`red-700`, `amber-50`, …).
 */
const config: Config = {
  darkMode: ['class'],
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: {
    container: { center: true, padding: '1rem', screens: { '2xl': '1400px' } },
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: { DEFAULT: 'hsl(var(--primary))', foreground: 'hsl(var(--primary-foreground))' },
        secondary: { DEFAULT: 'hsl(var(--secondary))', foreground: 'hsl(var(--secondary-foreground))' },
        destructive: { DEFAULT: 'hsl(var(--destructive))', foreground: 'hsl(var(--destructive-foreground))' },
        muted: { DEFAULT: 'hsl(var(--muted))', foreground: 'hsl(var(--muted-foreground))' },
        accent: { DEFAULT: 'hsl(var(--accent))', foreground: 'hsl(var(--accent-foreground))' },
        popover: { DEFAULT: 'hsl(var(--popover))', foreground: 'hsl(var(--popover-foreground))' },
        card: { DEFAULT: 'hsl(var(--card))', foreground: 'hsl(var(--card-foreground))' },
        sidebar: { DEFAULT: 'hsl(var(--sidebar))', foreground: 'hsl(var(--sidebar-foreground))', accent: 'hsl(var(--sidebar-accent))' },
        midnight: pcu.midnight,
        smoke: pcu.smoke,
        emerald: pcu.emerald,
        amber: pcu.amber,
        'status-draft': pcu.statusDraft,
        'text-secondary': pcu.textSecondary,
        ...tones,
      },
      borderRadius: {
        /** radius-app-panel: panels and cards. */
        xl: '12px',
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      backgroundImage: {
        /** gradient-midnight: brand surfaces only (login header); takes white text. */
        'gradient-midnight': 'linear-gradient(135deg, #245484, #133256)',
      },
      boxShadow: {
        /** shadow-popover: menus, popovers, dialogs. Panels and cards carry no shadow. */
        popover: '0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -4px rgba(0,0,0,0.1)',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      keyframes: {
        'collapsible-down': { from: { height: '0' }, to: { height: 'var(--radix-collapsible-content-height)' } },
        'collapsible-up': { from: { height: 'var(--radix-collapsible-content-height)' }, to: { height: '0' } },
      },
      animation: {
        'collapsible-down': 'collapsible-down 0.2s ease-out',
        'collapsible-up': 'collapsible-up 0.2s ease-out',
      },
    },
  },
  plugins: [animate],
};

export default config;
