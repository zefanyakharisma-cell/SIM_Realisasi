import type { Metadata } from 'next';
import { Building2, LogIn, Users } from 'lucide-react';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { getSessionUser, isDemoAuthEnabled, listDemoAccounts, type DemoAccount } from '@/lib/session';
import { ROLE_LABEL, TRACK_LABEL } from '@/lib/realisasi/status';
import { loginAs } from '@/lib/realisasi/actions/session';

export const metadata: Metadata = { title: 'Masuk' };
export const dynamic = 'force-dynamic';

async function loadAccounts(): Promise<{ accounts: DemoAccount[]; failed: boolean }> {
  try {
    return { accounts: await listDemoAccounts(), failed: false };
  } catch (e) {
    console.error('[login] cannot load demo accounts', e);
    return { accounts: [], failed: true };
  }
}

export default async function LoginPage(props: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await props.searchParams;
  const [{ accounts, failed }, current] = await Promise.all([loadAccounts(), getSessionUser().catch(() => null)]);
  const demo = isDemoAuthEnabled();

  return (
    <main className="mx-auto flex min-h-screen max-w-4xl flex-col justify-center gap-6 px-4 py-10">
      <div className="space-y-1 text-center">
        <h1 className="text-3xl font-semibold tracking-tight">SIM Realisasi</h1>
        <p className="text-sm text-muted-foreground">
          {demo ? 'Mockup — pilih akun demo untuk masuk. Tidak ada kata sandi.' : 'Masuk demo dinonaktifkan.'}
        </p>
      </div>

      {demo ? (
        <Alert variant="warning" role="note" data-testid="demo-auth-notice">
          <AlertDescription>
            Mode demo: pengalih peran ini tidak memakai autentikasi dan hanya untuk mockup. Nonaktifkan dengan{' '}
            <code>DEMO_AUTH=0</code> dan ganti dengan SSO institusi sebelum dipakai di luar demo.
          </AlertDescription>
        </Alert>
      ) : (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            Login demo dinonaktifkan (<code>DEMO_AUTH=0</code>). Aplikasi memerlukan SSO institusi yang belum terpasang pada mockup ini.
          </AlertDescription>
        </Alert>
      )}

      {sp.error ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            {sp.error === 'nonaktif' ? 'Login demo dinonaktifkan.' : 'Akun tidak dikenal. Silakan pilih salah satu akun di bawah.'}
          </AlertDescription>
        </Alert>
      ) : null}
      {failed ? (
        <Alert variant="destructive" role="alert">
          <AlertDescription>Basis data tidak dapat dihubungi. Jalankan <code>npm run db:reset</code> lalu muat ulang halaman ini.</AlertDescription>
        </Alert>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Pilih akun</CardTitle>
          <CardDescription>
            {current ? (
              <>
                Saat ini masuk sebagai <strong>{current.displayName}</strong>. Pilih akun lain untuk berganti peran.
              </>
            ) : (
              'Setiap akun mewakili satu peran pada matriks akses.'
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <ul className="grid gap-3 sm:grid-cols-2">
            {accounts.map((a) => (
              <li key={a.id}>
                <form action={loginAs.bind(null, a.id)}>
                  <button
                    type="submit"
                    data-testid={`login-${a.email}`}
                    className="flex w-full items-start gap-3 rounded-lg border bg-background p-4 text-left transition-colors hover:border-primary hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    aria-label={`Masuk sebagai ${a.displayName}, ${ROLE_LABEL[a.role]}${a.unitName ? `, ${a.unitName}` : ''}`}
                  >
                    <LogIn className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
                    <span className="min-w-0 flex-1 space-y-1.5">
                      <span className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">{a.displayName}</span>
                        <Badge variant={a.role === 'io_admin' ? 'purple' : a.role === 'io_staff' ? 'blue' : a.role === 'viewer' ? 'neutral' : 'green'}>
                          {ROLE_LABEL[a.role]}
                        </Badge>
                        {current?.id === a.id ? <Badge variant="outline">Aktif</Badge> : null}
                      </span>
                      <span className="block truncate text-xs text-muted-foreground">{a.email}</span>
                      <span className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
                        {a.unitName ? (
                          <span className="inline-flex items-center gap-1">
                            <Building2 className="size-3.5" aria-hidden="true" />
                            {a.unitName}
                          </span>
                        ) : null}
                        {a.teams.length > 0 ? (
                          <span className="inline-flex items-center gap-1">
                            <Users className="size-3.5" aria-hidden="true" />
                            Tim {a.teams.map((t) => TRACK_LABEL[t]).join(' & ')}
                          </span>
                        ) : null}
                      </span>
                    </span>
                  </button>
                </form>
              </li>
            ))}
          </ul>
          {demo && !failed && accounts.length === 0 ? (
            <p className="text-sm text-muted-foreground" role="status">
              Belum ada akun demo. Jalankan <code>npm run db:reset</code>.
            </p>
          ) : null}
        </CardContent>
      </Card>
    </main>
  );
}
