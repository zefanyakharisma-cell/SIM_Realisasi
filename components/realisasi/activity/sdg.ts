/**
 * UN Sustainable Development Goals: official colours (UN brand guide) and Indonesian names.
 * `text` is the foreground with ≥ 4.5:1 contrast on the goal colour (dark text on the light goals).
 */
export interface SdgStyle {
  id: number;
  name: string;
  color: string;
  text: string;
}

const WHITE = '#FFFFFF';
const DARK = '#111827';

export const SDGS: readonly SdgStyle[] = [
  { id: 1, name: 'Tanpa Kemiskinan', color: '#E5243B', text: WHITE },
  { id: 2, name: 'Tanpa Kelaparan', color: '#DDA63A', text: DARK },
  { id: 3, name: 'Kehidupan Sehat dan Sejahtera', color: '#4C9F38', text: DARK },
  { id: 4, name: 'Pendidikan Berkualitas', color: '#C5192D', text: WHITE },
  { id: 5, name: 'Kesetaraan Gender', color: '#FF3A21', text: DARK },
  { id: 6, name: 'Air Bersih dan Sanitasi Layak', color: '#26BDE2', text: DARK },
  { id: 7, name: 'Energi Bersih dan Terjangkau', color: '#FCC30B', text: DARK },
  { id: 8, name: 'Pekerjaan Layak dan Pertumbuhan Ekonomi', color: '#A21942', text: WHITE },
  { id: 9, name: 'Industri, Inovasi dan Infrastruktur', color: '#FD6925', text: DARK },
  { id: 10, name: 'Berkurangnya Kesenjangan', color: '#DD1367', text: WHITE },
  { id: 11, name: 'Kota dan Permukiman yang Berkelanjutan', color: '#FD9D24', text: DARK },
  { id: 12, name: 'Konsumsi dan Produksi yang Bertanggung Jawab', color: '#BF8B2E', text: DARK },
  { id: 13, name: 'Penanganan Perubahan Iklim', color: '#3F7E44', text: WHITE },
  { id: 14, name: 'Ekosistem Lautan', color: '#0A97D9', text: DARK },
  { id: 15, name: 'Ekosistem Daratan', color: '#56C02B', text: DARK },
  { id: 16, name: 'Perdamaian, Keadilan dan Kelembagaan yang Tangguh', color: '#00689D', text: WHITE },
  { id: 17, name: 'Kemitraan untuk Mencapai Tujuan', color: '#19486A', text: WHITE },
];

export function sdgStyle(id: number): SdgStyle {
  return SDGS[id - 1] ?? { id, name: `SDG ${id}`, color: '#6B7280', text: WHITE };
}
