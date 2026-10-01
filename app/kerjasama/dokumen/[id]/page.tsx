import { redirect } from 'next/navigation';

export default async function DocumentPage(props: { params: Promise<{ id: string }> }) {
  const { id } = await props.params;
  const n = /^\d{1,9}$/.test(id) ? id : '0';
  redirect(`/kerjasama/dokumen/${n}/realisasi`);
}
