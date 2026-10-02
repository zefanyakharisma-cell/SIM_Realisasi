import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/realisasi/empty-state';
import { Forbidden } from '@/components/realisasi/forbidden';
import { PageHeader } from '@/components/realisasi/page-header';
import { participantRequirements } from '@/components/realisasi/activity/labels';
import { ParticipantCommit } from '@/components/realisasi/wizard/participant-commit';
import { withUser } from '@/lib/db';
import { requireUser } from '@/lib/session';
import { getActivityDetail, getParticipantVersion } from '@/lib/realisasi/queries/activity';
import { getFormOptions } from '@/lib/realisasi/queries/lookups';

export const metadata = { title: 'Edit Peserta · SIM Realisasi' };

/** IO Mobility post-verification participants edit (`can_edit_verified_participants`, R-29). */
export default async function EditParticipantsPage(props: { params: Promise<{ id: string }> }) {
  const user = await requireUser();
  const { id } = await props.params;
  const data = await withUser(user.id, async (tx) => {
    const detail = await getActivityDetail(tx, id);
    if (!detail || !detail.permissions.can_edit_verified_participants) return { detail, version: null, countries: [] };
    const [version, options] = [await getParticipantVersion(tx, id), await getFormOptions(tx)];
    return { detail, version, countries: options.countries };
  });
  if (!data.detail) return <EmptyState title="Kegiatan tidak ditemukan" />;
  const { detail, version, countries } = data;
  if (!detail.permissions.can_edit_verified_participants) return <Forbidden />;

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader
        title={`Edit Peserta ${detail.code}`}
        description={detail.name}
        actions={
          <Button asChild variant="outline" size="sm">
            <Link href={`/realisasi/kegiatan/${detail.id}?tab=peserta`}>Batal</Link>
          </Button>
        }
      />
      <ParticipantCommit activityId={detail.id} version={version} countries={countries} required={participantRequirements({ is_mobility: detail.agenda.is_mobility, direction: detail.direction })} />
    </div>
  );
}
