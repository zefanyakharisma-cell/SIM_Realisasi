import type { Metadata, Viewport } from 'next';
import localFont from 'next/font/local';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Toaster } from '@/components/ui/toaster';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'SIM Realisasi', template: '%s · SIM Realisasi' },
  description: 'Pelaporan dan verifikasi realisasi kerja sama — Petra Christian University (mockup).',
};

/** Inter, self-hosted from the PCU Design System (mandatory for body text). */
const inter = localFont({
  src: [
    { path: './fonts/Inter-Variable.woff2', weight: '100 900', style: 'normal' },
    { path: './fonts/Inter-Italic-Variable.woff2', weight: '100 900', style: 'italic' },
  ],
  variable: '--font-inter',
  display: 'swap',
});

export const viewport: Viewport = { width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id" className={inter.variable}>
      <body>
        <TooltipProvider delayDuration={300}>{children}</TooltipProvider>
        <Toaster />
      </body>
    </html>
  );
}
