import type { Metadata, Viewport } from 'next';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Toaster } from '@/components/ui/toaster';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'SIM Realisasi', template: '%s · SIM Realisasi' },
  description: 'Pelaporan dan verifikasi realisasi kerja sama — Petra Christian University (mockup).',
};

export const viewport: Viewport = { width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <body>
        <TooltipProvider delayDuration={300}>{children}</TooltipProvider>
        <Toaster />
      </body>
    </html>
  );
}
