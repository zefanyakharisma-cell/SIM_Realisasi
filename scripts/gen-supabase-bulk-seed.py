#!/usr/bin/env python3
"""Generates the bulk demo seed for the simks-partnership Supabase project (supabase/seed-supabase/05..08_*.sql).

120 kegiatan submitted by Program Studi units of the live SIM Kerjasama tree: 100 in AY 2025/2026 and 20 in AY 2026/2027
up to the demo "today" (2026-10-03), with peserta (PETRA students, inbound exchange students, internal staff and
external persons), files, logs and verification states. Deterministic (fixed random seed): re-running this script
rewrites identical files. Each output file is self-contained (it defines the pg_temp helpers it needs) and idempotent,
so it can be pasted into the Supabase SQL Editor or sent as one statement batch, one step at a time.

    python3 scripts/gen-supabase-bulk-seed.py

Inputs are the live facts read on 2026-10-03: units (ids/names), documents 11-52 with partners and validity, agendas
with their Realisasi mobility rules, and the Realisasi accounts (akun 1 io_admin, akun 4 Prodi Manajemen submitter,
akun 10/11 Mobility team). Data rules follow the app: participants only on mobility kegiatan, external persons on any.
"""
from __future__ import annotations

import datetime as dt
import random
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "supabase" / "seed-supabase"
R = random.Random(2026)
D = dt.date
TODAY = D(2026, 10, 3)
GENAP_FREEZE = D(2026, 8, 30)  # genap_full_year snapshot (as of 2026-08-30 01:00 WIB)

# ---------------------------------------------------------------------------------------------------------- units
# Program Studi (kind 'prodi' in kerjasama.units): id, unit name, BAAK prodi name, faculty name, NRP prefix, weight
@dataclass(frozen=True)
class Prodi:
    id: int
    unit: str
    baak: str
    faculty: str
    nrp: str      # faculty letter + 2-digit prodi code
    weight: int
    area: str     # topic area for kegiatan names


SBM, FTI, FTSP, FHIK, FKIP, FK, FKG = (
    "School of Business and Management", "Fakultas Teknologi Industri", "Fakultas Teknik Sipil dan Perencanaan",
    "Fakultas Humaniora dan Industri Kreatif", "Fakultas Keguruan dan Ilmu Pendidikan", "Fakultas Kedokteran",
    "Fakultas Kedokteran Gigi")
PRODI = [
    Prodi(5, "Program Studi Manajemen", "Manajemen", SBM, "D31", 12, "bisnis"),
    Prodi(6, "Program Studi Akuntansi", "Akuntansi", SBM, "D32", 8, "akuntansi"),
    Prodi(48, "Program Studi Magister Manajemen", "Magister Manajemen", SBM, "H71", 3, "bisnis"),
    Prodi(51, "Program Studi Doktor Ilmu Manajemen", "Doktor Ilmu Manajemen", SBM, "H72", 1, "bisnis"),
    Prodi(54, "Program Studi Arsitektur", "Arsitektur", FTSP, "A12", 5, "arsitektur"),
    Prodi(53, "Program Studi Magister Arsitektur", "Magister Arsitektur", FTSP, "A13", 1, "arsitektur"),
    Prodi(55, "Program Studi Teknik Sipil", "Teknik Sipil", FTSP, "A11", 5, "sipil"),
    Prodi(56, "Program Studi Magister Teknik Sipil", "Magister Teknik Sipil", FTSP, "A14", 1, "sipil"),
    Prodi(57, "Program Studi Ilmu Komunikasi", "Ilmu Komunikasi", FHIK, "E42", 4, "komunikasi"),
    Prodi(58, "Program Studi Bahasa Mandarin", "Bahasa Mandarin", FHIK, "E43", 3, "bahasa"),
    Prodi(59, "Program Studi Desain Interior", "Desain Interior", FHIK, "C22", 4, "desain"),
    Prodi(61, "Program Studi Sastra Inggris", "Sastra Inggris", FHIK, "E41", 4, "bahasa"),
    Prodi(63, "Program Studi Desain Komunikasi Visual", "Desain Komunikasi Visual", FHIK, "C21", 6, "desain"),
    Prodi(64, "Program Studi Magister Sastra", "Magister Sastra", FHIK, "E44", 1, "bahasa"),
    Prodi(65, "Program Studi Teknik Elektro", "Teknik Elektro", FTI, "B12", 5, "elektro"),
    Prodi(67, "Program Studi Teknik Industri", "Teknik Industri", FTI, "B13", 6, "industri"),
    Prodi(68, "Program Studi Informatika", "Informatika", FTI, "B11", 9, "informatika"),
    Prodi(69, "Program Studi Teknik Mesin", "Teknik Mesin", FTI, "B14", 4, "mesin"),
    Prodi(70, "Program Studi Magister Teknik Industri", "Magister Teknik Industri", FTI, "B15", 1, "industri"),
    Prodi(72, "Program Studi Pendidikan Guru Pendidikan Anak Usia Dini", "Pendidikan Guru Pendidikan Anak Usia Dini", FKIP, "F52", 2, "pendidikan"),
    Prodi(73, "Program Studi Pendidikan Guru Sekolah Dasar", "Pendidikan Guru Sekolah Dasar", FKIP, "F51", 3, "pendidikan"),
    Prodi(76, "Program Studi Kedokteran", "Kedokteran", FK, "G61", 3, "kesehatan"),
    Prodi(74, "Program Studi Kedokteran Gigi", "Kedokteran Gigi", FKG, "G62", 2, "kesehatan"),
]
PRODI_BY_ID = {p.id: p for p in PRODI}
GRADUATE = {48, 51, 53, 56, 64, 70}  # smaller cohorts, no long exchanges

TOPICS = {
    "bisnis": ["Manajemen Rantai Pasok", "Kewirausahaan Digital", "Pemasaran Berkelanjutan", "Strategi Bisnis Asia",
               "Manajemen SDM Global", "Bisnis Keluarga", "Inovasi Model Bisnis"],
    "akuntansi": ["Akuntansi Forensik", "Pelaporan Keberlanjutan", "Perpajakan Internasional", "Audit Berbasis Data",
                  "Akuntansi Manajemen"],
    "arsitektur": ["Arsitektur Tropis", "Konservasi Bangunan Bersejarah", "Desain Kota Pesisir", "Hunian Terjangkau"],
    "sipil": ["Rekayasa Gempa", "Manajemen Konstruksi", "Infrastruktur Hijau", "Transportasi Perkotaan"],
    "komunikasi": ["Jurnalisme Digital", "Komunikasi Krisis", "Produksi Media Kreatif", "Public Relations Global"],
    "bahasa": ["Linguistik Terapan", "Penerjemahan Sastra", "Budaya Tionghoa Kontemporer", "Pengajaran Bahasa"],
    "desain": ["Desain Berkelanjutan", "Ilustrasi dan Narasi Visual", "Desain Ruang Publik", "Branding Budaya Lokal",
               "Desain Interaksi"],
    "elektro": ["Sistem Energi Terbarukan", "Internet of Things", "Kendali Cerdas", "Elektronika Daya"],
    "industri": ["Lean Manufacturing", "Logistik dan Rantai Pasok", "Ergonomi Industri", "Optimasi Produksi"],
    "informatika": ["Kecerdasan Buatan", "Keamanan Siber", "Rekayasa Perangkat Lunak", "Data Science",
                    "Komputasi Awan"],
    "mesin": ["Manufaktur Aditif", "Kendaraan Listrik", "Termodinamika Terapan", "Robotika Industri"],
    "pendidikan": ["Pembelajaran Anak Usia Dini", "Literasi Dasar", "Pendidikan Inklusif", "Kurikulum Merdeka"],
    "kesehatan": ["Kesehatan Masyarakat", "Pendidikan Klinis", "Kesehatan Gigi Komunitas", "Telemedisin"],
}

# ------------------------------------------------------------------------------------------------------ documents
@dataclass(frozen=True)
class Doc:
    id: int
    partner: str
    short: str
    country: str
    start: dt.date
    end: dt.date
    scope: frozenset


ALL = frozenset({5, 6, 48, 51} | set(range(53, 77)))
SBMS = frozenset({4, 5, 6, 48, 51})
DOCS = [
    Doc(11, "Kyoto Sangyo University", "Kyoto Sangyo", "JP", D(2024, 8, 15), D(2029, 8, 14), frozenset({7})),
    Doc(12, "PT Astra International Tbk", "Astra", "ID", D(2025, 12, 1), D(2026, 12, 1), frozenset({4})),
    Doc(15, "National Taiwan University", "NTU", "TW", D(2026, 2, 19), D(2027, 12, 21), frozenset({5})),
    Doc(17, "University of Amsterdam", "Amsterdam", "NL", D(2026, 2, 19), D(2028, 2, 29), frozenset({7})),
    Doc(19, "National University of Singapore", "NUS", "SG", D(2026, 2, 19), D(2026, 11, 6), frozenset({4})),
    Doc(21, "PT Unilever Indonesia Tbk", "Unilever", "ID", D(2026, 2, 19), D(2026, 8, 16), frozenset({6})),
    Doc(23, "PT Astra International Tbk", "Astra", "ID", D(2026, 2, 19), D(2028, 9, 26), frozenset({8})),
    Doc(25, "Chulalongkorn University", "Chulalongkorn", "TH", D(2026, 2, 19), D(2028, 12, 5), frozenset({5})),
    Doc(27, "Kyoto Sangyo University", "Kyoto Sangyo", "JP", D(2026, 2, 19), D(2027, 1, 1), frozenset({7})),
    Doc(28, "Universitas Gadjah Mada", "UGM", "ID", D(2025, 10, 17), D(2026, 10, 27), frozenset({5})),
    Doc(29, "Chulalongkorn University", "Chulalongkorn", "TH", D(2025, 10, 17), D(2026, 10, 22), frozenset({4})),
    Doc(30, "National Taiwan University", "NTU", "TW", D(2025, 10, 17), D(2026, 11, 6), frozenset({5})),
    Doc(31, "Yonsei University", "Yonsei", "KR", D(2025, 10, 17), D(2026, 11, 1), frozenset({4})),
    Doc(32, "University of Amsterdam", "Amsterdam", "NL", D(2025, 10, 17), D(2026, 11, 11), frozenset({1})),
    Doc(33, "Universitas Gadjah Mada", "UGM", "ID", D(2026, 9, 22), D(2031, 9, 17), frozenset({5})),
    Doc(34, "Chulalongkorn University", "Chulalongkorn", "TH", D(2026, 9, 22), D(2028, 9, 17), frozenset({4})),
    Doc(36, "National University of Singapore", "NUS", "SG", D(2026, 8, 28), D(2028, 2, 24), frozenset({28})),
    Doc(38, "Chulalongkorn University", "Chulalongkorn", "TH", D(2026, 8, 28), D(2028, 5, 24), frozenset({55})),
    Doc(40, "Universitas Gadjah Mada", "UGM", "ID", D(2026, 8, 28), D(2028, 8, 22), frozenset({8})),
    Doc(42, "Ludwig Maximilian University of Munich", "LMU Munich", "DE", D(2026, 8, 28), D(2028, 11, 20), frozenset({1})),
    Doc(44, "Ateneo de Manila University", "Ateneo de Manila", "PH", D(2026, 8, 28), D(2029, 2, 18), frozenset({36})),
    Doc(51, "University of Sydney", "Sydney", "AU", D(2026, 9, 23), D(2026, 10, 23), SBMS | {7, 8} | set(range(40, 53))),
    Doc(52, "National Taiwan University", "NTU", "TW", D(2026, 9, 24), D(2026, 10, 24), ALL | {4, 28, 30, 32, 34, 35, 36}),
]
CITY = {"Kyoto Sangyo": "Kyoto", "NTU": "Taipei", "Amsterdam": "Amsterdam", "NUS": "Singapura", "Chulalongkorn": "Bangkok",
        "Yonsei": "Seoul", "LMU Munich": "München", "Ateneo de Manila": "Manila", "Sydney": "Sydney", "UGM": "Yogyakarta",
        "Astra": "Jakarta", "Unilever": "Jakarta"}
FACULTY_UNIT = {SBM: 4, FTI: 28, FTSP: 35, FHIK: 32, FKIP: 36, FK: 30, FKG: 34}


def docs_for(start: dt.date, end: dt.date, *, domestic: bool | None) -> list[Doc]:
    """Documents valid for the whole kegiatan (a little stricter than R-04's overlap rule)."""
    out = [d for d in DOCS if d.start <= start and end <= d.end]
    if domestic is True:
        out = [d for d in out if d.country == "ID"]
    elif domestic is False:
        out = [d for d in out if d.country != "ID"]
    return out


def pick_doc(cands: list[Doc], prodi: Prodi) -> Doc:
    fac = FACULTY_UNIT[prodi.faculty]
    scoped = [d for d in cands if prodi.id in d.scope or fac in d.scope]
    return R.choice(scoped if scoped and R.random() < 0.8 else cands)

# ------------------------------------------------------------------------------------------------------- people
FIRST = ["Andreas", "Bella", "Christian", "Daniel", "Elisabeth", "Felicia", "Gabriel", "Hana", "Ivana", "Jonathan",
         "Kevin", "Laurensia", "Michelle", "Nathaniel", "Olivia", "Patricia", "Rafael", "Stefani", "Theresia", "Vincent",
         "Wilson", "Yohanes", "Agnes", "Bryan", "Clarissa", "Devina", "Evan", "Grace", "Irene", "Jessica", "Kezia",
         "Lukas", "Marcella", "Natasha", "Priscilla", "Rachel", "Samuel", "Timothy", "Valencia", "Yosef", "Aurelia",
         "Benaya", "Cornelius", "Dionisius", "Eunike", "Filbert", "Gloria", "Hizkia", "Jesslyn", "Kristo"]
LAST = ["Wijaya", "Halim", "Santoso", "Gunawan", "Tanoto", "Kurniawan", "Setiawan", "Hartono", "Pranoto", "Sutanto",
        "Lesmana", "Tjahjono", "Hidayat", "Salim", "Wibowo", "Susanto", "Liem", "Handoko", "Sugianto", "Wirawan",
        "Kusuma", "Tanjung", "Budiman", "Saputra", "Hermawan", "Chandra", "Lim", "Siswanto", "Purnomo", "Effendi"]
TITLE_PRE = ["Dr.", "Dr.", "", "", "Prof. Dr.", "Ir.", ""]
INBOUND_NAMES = {
    "JP": ["Haruka Tanaka", "Sota Yamamoto", "Yuna Kobayashi", "Ren Ito", "Aoi Nakamura", "Kaito Suzuki"],
    "TW": ["Wei-Lun Chang", "Yi-Chen Huang", "Po-Han Liu", "Hsin-Yi Wu", "Chun-Kai Lee"],
    "NL": ["Sanne de Jong", "Lars Bakker", "Femke Visser", "Thijs Mulder"],
    "SG": ["Rachel Tan", "Marcus Lim", "Priya Nair", "Darren Ong", "Shu Hui Goh"],
    "TH": ["Natcha Srisuk", "Pakorn Chaiyasit", "Siriporn Wong", "Thanawat Boonmee", "Kanya Rattanakorn"],
    "KR": ["Ji-woo Kim", "Seo-jun Lee", "Ha-eun Park", "Min-seo Choi", "Do-yoon Jung"],
    "DE": ["Lena Hoffmann", "Jonas Weber", "Mia Schulz", "Felix Wagner"],
    "PH": ["Andrea Santos", "Miguel Reyes", "Bea Cruz", "Paolo Garcia"],
    "AU": ["Olivia Brown", "Jack Wilson", "Chloe Taylor"],
}
EXT_NAMES = {
    "JP": ["Prof. Kenji Watanabe", "Assoc. Prof. Mika Sato", "Dr. Hiroshi Kato", "Dr. Emi Fujita"],
    "TW": ["Prof. Chen Yu-Ting", "Dr. Lin Chia-Hao", "Assoc. Prof. Wang Mei-Ling", "Dr. Huang Jun-Wei"],
    "NL": ["Prof. Pieter van Dijk", "Dr. Anouk Smit", "Dr. Bram Janssen"],
    "SG": ["Prof. Tan Wee Kiat", "Dr. Lim Hui Min", "Assoc. Prof. Rajesh Kumar"],
    "TH": ["Asst. Prof. Kanokwan Srisuk", "Prof. Somchai Thongchai", "Dr. Ploy Charoenkul"],
    "KR": ["Prof. Park Jae-hyun", "Dr. Kim Soo-yeon", "Assoc. Prof. Lee Dong-hoon"],
    "DE": ["Prof. Dr. Markus Klein", "Dr. Katharina Braun", "Prof. Dr. Stefan Richter"],
    "PH": ["Dr. Maria Lourdes Ramos", "Prof. Jose Mendoza", "Dr. Carla Villanueva"],
    "AU": ["Prof. Sarah Mitchell", "Dr. James Cooper"],
    "ID": ["Dr. Rina Kartikasari", "Prof. Bambang Wicaksono", "Ir. Dimas Prakoso, M.T.", "Dra. Sri Wahyuni, M.Si.",
           "Hendro Saputro, S.E., M.M.", "Dr. Ayu Lestari", "Ir. Yudi Hartanto", "Dewi Anggraini, S.T., M.B.A."],
}


@dataclass
class Student:
    nrp: str
    name: str
    prodi: Prodi | None
    intake: int
    home: tuple[str, str] | None = None  # inbound: (institution, country)
    busy: list = field(default_factory=list)

    def free(self, a: dt.date, b: dt.date) -> bool:
        return all(b < s or e < a for s, e in self.busy)


KNOWN_NRPS = set("""A11235253 A11252034 A12223059 A12231277 B11200005 B11227366 B11234310 B11235580 B11235901 B11237182
B11238623 B11240422 B11244167 B11252003 B11256252 B11257273 B12222426 B12223137 B12229323 B12249536 B12251882 B12252182
B12254341 B12257991 C21233005 C21233140 C21233729 C21247286 C21257355 D31238836 D31239872 D31240187 D31242651 D31243593
D31245931 D31246584 D31252983 D32210044 D32233592 D32237864 D32250736 E41251767 F51245128 G61248918 H71235980 X01250003
X01250017 X01250024 X01260012 X01260027 X01260035 X01260044 X01260051 X01260068 X02250031 X02250042 X02250056 X02250063
X02260008 X02260015""".split())
KNOWN_EMPS = set("""PG124885 PG190875 PG204517 PG214411 PG217839 PG295222 PG378607 PG413450 PG427328 PG452412 PG488192
PG561867 PG564518 PG637448 PG657970 PG703063 PG707752 PG710955 PG712740 PG760736 PG761401 PG780858 PG803275 PG818524
PG974721""".split())


def person_name(used: set) -> str:
    while True:
        n = f"{R.choice(FIRST)} {R.choice(LAST)}"
        if n not in used:
            used.add(n)
            return n


students: list[Student] = []
by_prodi: dict[int, list[Student]] = {}
used_names: set = set()
used_nrp: set = set(KNOWN_NRPS)
for p in PRODI:
    n = 4 + p.weight * 2 if p.id not in GRADUATE else 6
    for _ in range(n):
        intake = R.choice([2022, 2023, 2023, 2024, 2024, 2025]) if p.id not in GRADUATE else R.choice([2024, 2025])
        while True:
            nrp = f"{p.nrp}{intake % 100:02d}{R.randint(6000, 8999):04d}"
            if nrp not in used_nrp:
                used_nrp.add(nrp)
                break
        s = Student(nrp, person_name(used_names), p, intake)
        students.append(s)
        by_prodi.setdefault(p.id, []).append(s)

inbound: dict[str, list[Student]] = {}
INST = {"JP": "Kyoto Sangyo University", "TW": "National Taiwan University", "NL": "University of Amsterdam",
        "SG": "National University of Singapore", "TH": "Chulalongkorn University", "KR": "Yonsei University",
        "DE": "Ludwig Maximilian University of Munich", "PH": "Ateneo de Manila University", "AU": "University of Sydney"}
seq = 300
for cc, names in INBOUND_NAMES.items():
    for nm in names:
        for term, yy in ((1, 25), (2, 26)):
            seq += 1
            nrp = f"X{term + 2:02d}{yy}{seq:04d}"
            s = Student(nrp, nm if term == 1 else nm.split()[0] + " " + R.choice(names).split()[-1], None, 2000 + yy,
                        (INST[cc], cc))
            inbound.setdefault(cc, []).append(s)

# employees: 2-4 per prodi (dosen, kaprodi), Mobility/IO staff
@dataclass
class Employee:
    id: str
    name: str
    unit: str
    position: str


employees: list[Employee] = []
emp_by_prodi: dict[int, list[Employee]] = {}
used_emp: set = set(KNOWN_EMPS)
for p in PRODI:
    for i in range(2 + (p.weight >= 5) + (p.weight >= 9)):
        while True:
            eid = f"PG{R.randint(500000, 699999)}"
            if eid not in used_emp:
                used_emp.add(eid)
                break
        title = R.choice(["Dr. ", "", "", "Ir. "])
        e = Employee(eid, f"{title}{person_name(used_names)}, " + R.choice(["M.T.", "M.M.", "M.Sc.", "M.Ds.", "M.Pd.", "Ph.D."]),
                     p.unit, "Ketua Program Studi" if i == 0 else R.choice(["Dosen", "Dosen", "Lektor Kepala"]))
        employees.append(e)
        emp_by_prodi.setdefault(p.id, []).append(e)

# ----------------------------------------------------------------------------------------------------- kegiatan
# agenda id -> (label, mobility category or None)
MOB_OUT_ABROAD = [  # agenda, label, min/max days, students min/max
    (2, "Student Exchange", 100, 140, 2, 5),
    (20, "Study Abroad", 80, 120, 1, 3),
    (23, "Short Program", 12, 21, 4, 12),
    (22, "Immersion Program", 7, 12, 5, 15),
    (29, "Cultural Exchange", 5, 10, 4, 10),
    (33, "Credit Transfer", 90, 120, 2, 4),
    (17, "Double Degree", 150, 170, 1, 3),
    (21, "Magang Internasional", 30, 56, 2, 4),
    (24, "Studi Ekskursi", 4, 9, 8, 15),
]
MOB_OUT_DOMESTIC = [
    (38, "MBKM Pertukaran Mahasiswa", 90, 120, 2, 5),
    (21, "Magang Industri", 30, 60, 2, 6),
    (24, "Studi Ekskursi", 3, 6, 10, 15),
]
MOB_IN = [
    (28, "Academic Exchange (Inbound)", 90, 120, 2, 4),
    (23, "Short Program (Inbound)", 10, 18, 3, 6),
    (29, "Cultural Exchange (Inbound)", 5, 9, 3, 5),
]
NON_MOB = [  # agenda, label, min/max days, direction, abroad possible
    (15, "Kuliah Tamu", 1, 2, "inbound"),
    (34, "Kuliah Bersama", 1, 3, "inbound"),
    (4, "Riset Bersama", 60, 150, "outbound"),
    (10, "Seminar Internasional", 1, 2, "inbound"),
    (35, "Workshop Bersama", 2, 3, "inbound"),
    (40, "Pengabdian Masyarakat", 3, 7, "outbound"),
    (3, "Staff Exchange", 5, 14, "outbound"),
    (11, "Pengembangan Kurikulum Bersama", 20, 60, "outbound"),
    (27, "Academic Visit", 1, 3, "outbound"),
    (5, "Publikasi Bersama", 60, 120, "outbound"),
]
MOB_AGENDAS = {a for a, *_ in MOB_OUT_ABROAD + MOB_OUT_DOMESTIC + MOB_IN}
VENUE_PCU = ["Kampus PCU Siwalankerto", "Auditorium Radius Prawiro PCU", "Gedung Q PCU", "Gedung P PCU",
             "Gedung T PCU", "Ruang Seminar Gedung W PCU"]


@dataclass
class Keg:
    n: int
    name: str
    unit: int
    agenda: int
    direction: str
    start: dt.date
    end: dt.date
    mode: str
    venue: str
    country: str | None
    doc: int
    sdgs: list
    submitted: dt.datetime | None
    mstatus: str | None
    msince: dt.datetime | None
    files: str = "{ia,ir}"
    mnote: str | None = None
    ext: list = field(default_factory=list)
    internal: list = field(default_factory=list)
    inbound: list = field(default_factory=list)
    staff: list = field(default_factory=list)
    pset_status: str | None = None
    reviewed: dt.datetime | None = None
    conflict: bool = False


def at(d: dt.date, h: int = 9, m: int = 0) -> dt.datetime:
    return dt.datetime(d.year, d.month, d.day, h, m)


def weighted_prodi() -> Prodi:
    return R.choices(PRODI, weights=[p.weight for p in PRODI])[0]


def rand_date(a: dt.date, b: dt.date) -> dt.date:
    return a + dt.timedelta(days=R.randint(0, (b - a).days))


SDG_BY_AREA = {"bisnis": [8, 9, 12], "akuntansi": [8, 16, 17], "arsitektur": [11, 9, 13], "sipil": [9, 11, 6],
               "komunikasi": [4, 16, 5], "bahasa": [4, 10, 17], "desain": [11, 12, 9], "elektro": [7, 9, 13],
               "industri": [9, 12, 8], "informatika": [9, 4, 8], "mesin": [9, 7, 12], "pendidikan": [4, 5, 10],
               "kesehatan": [3, 6, 4]}


def sdgs_for(p: Prodi) -> list:
    base = SDG_BY_AREA[p.area]
    out = sorted(set([4] * (R.random() < 0.5) + R.sample(base, R.randint(1, 2)) + [17] * (R.random() < 0.3)))
    return out


def make_kegiatan(n: int, window: tuple[dt.date, dt.date], *, kind: str, prodi: Prodi | None = None,
                  end_by: dt.date | None = None) -> Keg:
    """kind: 'out_abroad' | 'out_domestic' | 'in' | 'non'."""
    for _ in range(400):
        p = prodi or weighted_prodi()
        if kind == "out_abroad":
            agenda, label, dmin, dmax, smin, smax = R.choice(MOB_OUT_ABROAD)
            if p.id in GRADUATE and dmax > 60:
                continue
            direction, domestic = "outbound", False
        elif kind == "out_domestic":
            agenda, label, dmin, dmax, smin, smax = R.choice(MOB_OUT_DOMESTIC)
            direction, domestic = "outbound", True
        elif kind == "in":
            agenda, label, dmin, dmax, smin, smax = R.choice(MOB_IN)
            direction, domestic = "inbound", False
        else:
            agenda, label, dmin, dmax, direction = R.choice(NON_MOB)
            domestic = True if agenda == 40 else (None if direction == "inbound" else R.random() < 0.25)
            smin = smax = 0
        dur = R.randint(dmin, dmax)
        last_start = (end_by or window[1]) - dt.timedelta(days=dur - 1)
        if last_start < window[0]:
            continue
        start = rand_date(window[0], last_start)
        # a mobility semester starts on a Monday
        start -= dt.timedelta(days=start.weekday()) if dur > 4 else dt.timedelta()
        if start < window[0]:
            start += dt.timedelta(days=7)
        end = start + dt.timedelta(days=dur - 1)
        cands = docs_for(start, end, domestic=domestic)
        if not cands:
            continue
        doc = pick_doc(cands, p)
        topic = R.choice(TOPICS[p.area])
        city = CITY[doc.short]
        ext: list = []
        if kind in ("out_abroad", "out_domestic"):
            country = doc.country
            mode = "offline"
            venue = doc.partner if R.random() < 0.7 or doc.country == "ID" else f"{doc.partner}, {city}"
            if agenda == 24 and domestic:
                venue = R.choice(["Bali", "Yogyakarta", "Bandung", "Malang", "Labuan Bajo"])
            name = f"{label} {topic} di {doc.partner}" if agenda not in (24, 21) else \
                   (f"{label} {p.baak} ke {venue}" if agenda == 24 else f"{label} {p.baak} di {doc.partner}")
            if agenda == 38:
                name = f"{label} {p.baak} di {doc.partner}"
        elif kind == "in":
            country = "ID"
            mode = "offline"
            venue = R.choice(VENUE_PCU)
            name = f"{label} {doc.short} – {topic}"
        else:
            if direction == "inbound":
                country, mode = "ID", R.choice(["offline", "offline", "hybrid", "online"])
                venue = "Zoom Meeting" if mode == "online" else R.choice(VENUE_PCU)
                if mode == "online":
                    country = None
                speakers = EXT_NAMES[doc.country]
                k = 1 if agenda in (15, 34) else R.randint(1, 3)
                role = "visiting_lecturer" if agenda == 34 else "speaker"
                ext = [{"full_name": nm, "institution": doc.partner, "country_code": doc.country, "role": role}
                       for nm in R.sample(speakers, min(k, len(speakers)))]
                name = {15: f"Kuliah Tamu {topic} dari {doc.partner}", 34: f"Kuliah Bersama {topic} dengan {doc.short}",
                        10: f"Seminar Internasional {topic} bersama {doc.short}",
                        35: f"Workshop {topic} bersama {doc.short}"}[agenda]
            else:
                mode = R.choice(["offline", "hybrid"]) if agenda not in (4, 5, 11) else R.choice(["online", "hybrid", "offline"])
                if agenda == 40:
                    country, venue = "ID", R.choice(["Desa Wisata Nglanggeran", "Kelurahan Kenjeran", "Desa Sumberbrantas",
                                                      "Kampung Batik Jetis", "SDN Siwalankerto I", "Puskesmas Wonokromo"])
                elif mode == "online":
                    country, venue = None, "Zoom Meeting"
                else:
                    country, venue = doc.country, doc.partner
                ext = [{"full_name": nm, "institution": doc.partner, "country_code": doc.country,
                        "role": "researcher" if agenda in (4, 5) else R.choice(["staff_visitor", "other"])}
                       for nm in R.sample(EXT_NAMES[doc.country], R.randint(1, 2))]
                name = {4: f"Riset Bersama {topic} dengan {doc.partner}", 40: f"Pengabdian Masyarakat {topic} bersama {doc.short}",
                        3: f"Staff Exchange Dosen {p.baak} ke {doc.partner}", 11: f"Pengembangan Kurikulum {topic} bersama {doc.short}",
                        27: f"Academic Visit {p.baak} ke {doc.partner}", 5: f"Publikasi Bersama {topic} dengan {doc.short}"}[agenda]
        k = Keg(n, name, p.id, agenda, direction, start, end, mode, venue, country, doc.id, sdgs_for(p),
                None, None, None, ext=ext)
        # peserta
        if kind != "non":
            want = R.randint(smin, smax)
            if kind == "in":
                pool = [s for s in inbound.get(doc.country, []) if s.free(start, end) and s.intake <= start.year]
                if len(pool) < max(1, smin):
                    continue
                chosen = R.sample(pool, min(want, len(pool)))
                k.inbound = chosen
            else:
                pool = [s for s in by_prodi[p.id] if s.free(start, end)]
                if len(pool) < smin:
                    continue
                chosen = R.sample(pool, min(want, len(pool)))
                k.internal = chosen
            for s in chosen:
                s.busy.append((start, end))
            if R.random() < 0.55 or agenda in (24, 22, 29):
                k.staff = R.sample(emp_by_prodi[p.id], min(len(emp_by_prodi[p.id]), R.randint(1, 2)))
            if kind == "in" or R.random() < 0.3:
                k.ext = [{"full_name": R.choice(EXT_NAMES[doc.country]), "institution": doc.partner,
                          "country_code": doc.country, "role": R.choice(["staff_visitor", "other"]),
                          "notes": "Koordinator program dari mitra"}]
        return k
    raise RuntimeError(f"could not place kegiatan {n} ({kind}) in {window}")


def submit(k: Keg, *, late: bool = False) -> dt.datetime:
    days = R.randint(35, 55) if late else R.randint(2, 21)
    return at(k.end + dt.timedelta(days=days), R.randint(8, 16), R.choice([0, 15, 30, 45]))


def approve_after(t: dt.datetime, lo: int = 3, hi: int = 18) -> dt.datetime:
    d = t + dt.timedelta(days=R.randint(lo, hi))
    return dt.datetime(d.year, d.month, d.day, R.randint(9, 16), R.choice([0, 30]))


REVISION_NOTES = [
    "Transkrip/poster/dokumentasi belum memuat seluruh peserta; mohon unggah ulang berkas mobilitas.",
    "Dua NRP tidak sesuai surat tugas; mohon perbarui data peserta.",
    "Tanggal kegiatan pada IA berbeda dengan data kegiatan; mohon disesuaikan.",
    "Mohon lengkapi daftar dosen pendamping sesuai surat tugas.",
]

kegiatan: list[Keg] = []
n = 100
# ---- AY 2025/2026: 100 kegiatan. Ganjil Aug 2025 - Jan 2026, Genap Feb - Jul 2026.
AY1 = [
    ((D(2025, 8, 4), D(2025, 10, 16)), [("out_abroad", 3), ("in", 2), ("non", 3)]),
    ((D(2025, 10, 17), D(2026, 1, 31)), [("out_abroad", 11), ("out_domestic", 5), ("in", 6), ("non", 16)]),
    ((D(2026, 2, 2), D(2026, 7, 24)), [("out_abroad", 17), ("out_domestic", 6), ("in", 8), ("non", 23)]),
]
for window, plan in AY1:
    for kind, count in plan:
        for _ in range(count):
            n += 1
            kegiatan.append(make_kegiatan(n, window, kind=kind))
ay1 = list(kegiatan)
R.shuffle(ay1)
mob1 = [k for k in ay1 if k.agenda in MOB_AGENDAS]
revision1 = [k for k in mob1 if k.end.month in (11, 12, 5, 6)][:2]
late_add = [k for k in mob1 if k.end >= D(2026, 6, 1) and k not in revision1][:3]
late_submit = set(id(k) for k in R.sample([k for k in ay1 if k not in revision1 and k not in late_add], 6))
for k in ay1:
    mob = k.agenda in MOB_AGENDAS
    k.submitted = submit(k, late=id(k) in late_submit)
    if not mob:
        continue
    if k in revision1:
        k.mstatus, k.msince = "revision_requested", approve_after(k.submitted, 4, 10)
        k.mnote = R.choice(REVISION_NOTES)
        k.pset_status, k.reviewed = "revision_requested", k.msince
    elif k in late_add:
        k.submitted = at(D(2026, 8, R.randint(24, 28)), 10)
        k.mstatus = "approved"
        k.msince = at(D(2026, 9, R.randint(2, 12)), 14)
        k.pset_status, k.reviewed = "approved", k.msince
    else:
        k.mstatus = "approved"
        k.msince = approve_after(k.submitted)
        if k.msince.date() >= GENAP_FREEZE:  # keep everything else inside the full-year freeze
            k.submitted = at(min(k.submitted.date(), D(2026, 8, 20)), 10)
            k.msince = at(D(2026, 8, R.randint(21, 28)), 14)
        k.pset_status, k.reviewed = "approved", k.msince

# ---- AY 2026/2027 YTD: 20 kegiatan (Aug 1 - Oct 3, 2026)
W2 = (D(2026, 8, 3), D(2026, 9, 30))
ay2_plan = [("non", 5, "verified"), ("out_abroad", 3, "approved"), ("in", 1, "approved"),
            ("out_abroad", 3, "pending"), ("in", 1, "pending"), ("out_domestic", 1, "pending"),
            ("out_abroad", 1, "revision"), ("out_domestic", 1, "revision"),
            ("non", 2, "draft"), ("out_abroad", 1, "draft"), ("in", 1, "draft")]
ay2: list[Keg] = []
for kind, count, state in ay2_plan:
    for _ in range(count):
        n += 1
        end_by = D(2026, 9, 26) if state in ("verified", "approved") else (D(2026, 9, 30) if state != "draft" else D(2026, 10, 2))
        k = make_kegiatan(n, W2, kind=kind, end_by=end_by)
        if state == "draft":
            k.files = "{ia}" if R.random() < 0.6 else "{}"
        else:
            # submitted 1-12 days after the end, never after today
            k.submitted = min(at(k.end + dt.timedelta(days=R.randint(1, 10)), R.randint(8, 16)), at(TODAY - dt.timedelta(days=1), 10))
            if k.submitted.date() <= k.end:
                k.submitted = at(k.end + dt.timedelta(days=1), 15)
            if k.submitted.date() >= TODAY:
                raise RuntimeError("submitted in the future")
        if state == "approved":
            k.mstatus = "approved"
            k.msince = min(approve_after(k.submitted, 2, 8), at(TODAY - dt.timedelta(days=1), 15))
            k.pset_status, k.reviewed = "approved", k.msince
        elif state == "pending":
            k.mstatus, k.msince, k.pset_status = "pending", k.submitted, "pending"
        elif state == "revision":
            k.mstatus = "revision_requested"
            k.msince = min(approve_after(k.submitted, 1, 4), at(TODAY - dt.timedelta(days=1), 11))
            k.mnote = R.choice(REVISION_NOTES)
            k.pset_status, k.reviewed = "revision_requested", k.msince
        elif state == "draft" and k.agenda in MOB_AGENDAS:
            k.pset_status = "draft"
        ay2.append(k)
# R-2.1 demo: a pending kegiatan of Prodi Magister Manajemen claims two students of an approved Prodi Manajemen kegiatan
# that runs at the same time -> two open duplicate-student decisions in the Mobility queue. Host: the first verified
# non-mobility slot is replaced by an approved Prodi Manajemen outbound kegiatan.
slot = next(k for k in ay2 if k.agenda not in MOB_AGENDAS and k.submitted)
host = make_kegiatan(slot.n, W2, kind="out_abroad", prodi=PRODI_BY_ID[5], end_by=D(2026, 9, 20))
while len(host.internal) < 2:
    host = make_kegiatan(slot.n, W2, kind="out_abroad", prodi=PRODI_BY_ID[5], end_by=D(2026, 9, 20))
host.submitted = at(host.end + dt.timedelta(days=3), 10)
host.mstatus, host.pset_status = "approved", "approved"
host.msince = host.reviewed = approve_after(host.submitted, 2, 5)
ay2[ay2.index(slot)] = host
claim = Keg(0, f"{host.name.split(' di ')[0]} (Magister Manajemen)", 48, host.agenda, "outbound", host.start, host.end,
            "offline", host.venue, host.country, host.doc, [4, 17], None, None, None)
claim.internal = host.internal[:2] + R.sample(by_prodi[48], 1)
claim.submitted = min(at(TODAY - dt.timedelta(days=3), 10), at(host.end + dt.timedelta(days=6), 10))
claim.mstatus, claim.msince, claim.pset_status, claim.conflict = "pending", claim.submitted, "pending", True
# swap the claimant in for one pending kegiatan so AY 2026/2027 stays at 20
pend = [k for k in ay2 if k.mstatus == "pending"]
victim = pend[-1]
claim.n = victim.n
for s in victim.internal + victim.inbound:
    s.busy.remove((victim.start, victim.end))
ay2[ay2.index(victim)] = claim
# codes follow creation order, like the app's sequence: renumber each year by submission (drafts last, by end date)
def created_key(k: Keg):
    return (k.submitted is None, k.submitted or at(k.end), k.n)


for base, year in ((101, ay1), (201, ay2)):
    for i, k in enumerate(sorted(year, key=created_key)):
        k.n = base + i
kegiatan = sorted(ay1, key=lambda k: k.n) + sorted(ay2, key=lambda k: k.n)
assert len(ay1) == 100 and len(ay2) == 20, (len(ay1), len(ay2))
for k in kegiatan:
    assert k.unit in PRODI_BY_ID
    assert k.end <= TODAY or k.submitted is None
    if k.submitted:
        assert k.submitted.date() > k.end and k.submitted.date() < TODAY, (k.n, k.end, k.submitted)

# ----------------------------------------------------------------------------------------------------------- SQL
def q(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, dt.datetime):
        return f"pg_temp.wib('{v.date().isoformat()}', '{v.strftime('%H:%M')}')"
    if isinstance(v, dt.date):
        return f"'{v.isoformat()}'"
    return "'" + str(v).replace("'", "''") + "'"


def arr(xs) -> str:
    return "'{" + ",".join(xs) + "}'"


HEADER = """-- seed-supabase/{name} (simks-partnership): GENERATED by scripts/gen-supabase-bulk-seed.py; do not edit by hand.
-- {what}
-- Self-contained and idempotent (existing rows are skipped), so it can be run on its own: Supabase SQL Editor or one
-- statement batch. Writes only realisasi.* and mock_baak/mock_hr; SIM Kerjasama tables are only read.
"""

HELPERS = r"""
create or replace function pg_temp.aid(n int) returns uuid language sql immutable as $$
  select ('b5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.gid(n int) returns uuid language sql immutable as $$
  select ('e5000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function pg_temp.akun(p_akun int) returns uuid language sql stable as $$
  select id from kerjasama.profiles where akun_id = p_akun $$;
create or replace function pg_temp.pdf() returns bytea language sql immutable as $$
  select decode('255044462d312e340a312030206f626a0a3c3c2f547970652f436174616c6f672f50616765732032203020523e3e0a656e646f626a0a322030206f626a0a3c3c2f547970652f50616765732f4b6964735b33203020525d2f436f756e7420313e3e0a656e646f626a0a332030206f626a0a3c3c2f547970652f506167652f506172656e742032203020522f4d65646961426f785b30203020323030203230305d2f436f6e74656e74732034203020522f5265736f75726365733c3c3e3e3e3e0a656e646f626a0a342030206f626a0a3c3c2f4c656e67746820303e3e73747265616d0a0a656e6473747265616d0a656e646f626a0a787265660a3020350a303030303030303030302036353533352066200a30303030303030303039203030303030206e200a30303030303030303534203030303030206e200a30303030303030313035203030303030206e200a30303030303030313939203030303030206e200a747261696c65720a3c3c2f53697a6520352f526f6f742031203020523e3e0a7374617274787265660a3234350a2525454f460a', 'hex') $$;
create or replace function pg_temp.wib(d date, t time default '09:00') returns timestamptz language sql immutable as $$
  select (d + t) at time zone 'Asia/Jakarta' $$;

-- preconditions: accounts seeded (03_accounts.sql) and the bulk registries present (05_registries_bulk.sql)
do $$
begin
  if pg_temp.akun(1) is null or pg_temp.akun(4) is null or pg_temp.akun(10) is null or pg_temp.akun(11) is null then
    raise exception 'run seed-supabase/03_accounts.sql first (account_roles for akun 1, 4, 10, 11)';
  end if;
  if not exists (select 1 from mock_baak.students where nrp like '%6___' and length(nrp) = 9 and nrp ~ '^[A-H]\d{4}[6-8]\d{3}$') then
    raise exception 'run seed-supabase/05_registries_bulk.sql first';
  end if;
end $$;

-- one kegiatan with its units, kerja sama, SDGs, external persons, files and log (skipped when it exists).
-- Creator: the Prodi Manajemen submitter (akun 4) for unit 5, otherwise IO Admin (akun 1) on behalf of the prodi.
create or replace function pg_temp.keg(
  p_n int, p_name text, p_unit int, p_agenda int, p_dir text, p_start date, p_end date, p_mode text, p_venue text,
  p_country text, p_doc int, p_sdgs int[], p_submitted timestamptz, p_mstatus text, p_msince timestamptz,
  p_files text[], p_mnote text, p_ext jsonb)
returns void language plpgsql as $f$
declare v_id uuid := pg_temp.aid(p_n); v_g uuid := pg_temp.gid(p_n);
        v_creator uuid := pg_temp.akun(case when p_unit = 5 then 4 else 1 end);
        v_mobt uuid := pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end);
        v_mob boolean := realisasi.agenda_is_mobility(p_agenda);
        v_created timestamptz; v_code text; k text; v_path text; e jsonb;
begin
  if exists (select 1 from realisasi.activities where id = v_id) then return; end if;
  if not exists (select 1 from kerjasama.units where id = p_unit and kind = 'prodi') then
    raise exception 'kegiatan %: unit % is not a Program Studi', p_n, p_unit;
  end if;
  if not exists (select 1 from kerjasama.agendas where id = p_agenda) then raise exception 'kegiatan %: agenda % missing', p_n, p_agenda; end if;
  if not exists (select 1 from realisasi.documents_valid_between(p_start, p_end) v where v.document_id = p_doc) then
    raise exception 'kegiatan %: document % not valid for % - %', p_n, p_doc, p_start, p_end;
  end if;
  v_created := coalesce(p_submitted - interval '2 days', pg_temp.wib(least(p_end, realisasi.today()) - 1));
  v_code := 'RL-' || to_char(v_created at time zone 'Asia/Jakarta', 'YYYY') || '-' || lpad(p_n::text, 4, '0');
  insert into realisasi.event_groups (id, created_by, created_at) values (v_g, v_creator, v_created) on conflict do nothing;
  insert into realisasi.activities (id, code, name, agenda_id, direction, start_date, end_date, mode, venue, country_code,
              sks_recognized, description, submitter_unit_id, created_by, submitted_at, verified_at,
              mobility_status, mobility_since, event_group_id, created_at, updated_at)
  values (v_id, v_code, p_name, p_agenda, p_dir::realisasi.direction, p_start, p_end, p_mode::realisasi.activity_mode, p_venue,
          p_country, case when v_mob and p_dir = 'outbound' then case when p_end - p_start >= 80 then 20 when p_end - p_start >= 20 then 6 else 2 end end,
          'Kegiatan "' || p_name || '" sebagai implementasi kerja sama dengan mitra.', p_unit, v_creator, p_submitted,
          case when p_submitted is not null and (not v_mob or p_mstatus = 'approved')
               then coalesce(case when v_mob then p_msince end, p_submitted) end,
          case when p_submitted is null or not v_mob then 'not_required' else p_mstatus end::realisasi.track_status,
          coalesce(p_msince, p_submitted, v_created), v_g, v_created, coalesce(p_msince, p_submitted, v_created));
  insert into realisasi.activity_units (activity_id, unit_id, is_submitter) values (v_id, p_unit, true);
  insert into realisasi.activity_documents (activity_id, original_document_id, out_of_scope_warning)
  values (v_id, p_doc, not exists (select 1 from kerjasama.document_scope_units su where su.document_id = p_doc and su.unit_id = p_unit));
  insert into realisasi.activity_sdgs (activity_id, sdg_id) select v_id, s from unnest(p_sdgs) s;
  for e in select * from jsonb_array_elements(p_ext) loop
    insert into realisasi.activity_external_persons (activity_id, full_name, institution, country_code, role, notes)
    values (v_id, e ->> 'full_name', e ->> 'institution', e ->> 'country_code', (e ->> 'role')::realisasi.person_role, e ->> 'notes');
  end loop;
  foreach k in array p_files || case when v_mob and p_submitted is not null then '{mobility_bundle}'::text[] else '{}' end loop
    v_path := case when k = 'mobility_bundle' then 'realisasi-transcripts/' else 'realisasi-files/' end
              || v_id || '/' || k || '/' || md5(v_id::text || k)::uuid || '.pdf';
    insert into realisasi.file_blobs (path, bucket, data, mime, size_bytes, created_by, created_at)
    values (v_path, split_part(v_path, '/', 1), pg_temp.pdf(), 'application/pdf', length(pg_temp.pdf()), v_creator, v_created + interval '1 hour')
    on conflict (path) do nothing;
    insert into realisasi.activity_files (activity_id, kind, version, storage_path, filename, size_bytes, mime, is_current, uploaded_by, uploaded_at)
    values (v_id, k::realisasi.file_kind, 1, v_path,
            case when k = 'mobility_bundle' then 'Transkrip_Poster_Dokumentasi_' else upper(k) || '_' end || v_code || '.pdf',
            length(pg_temp.pdf()), 'application/pdf', true, v_creator, v_created + interval '1 hour');
  end loop;

  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'create', v_creator, null, null, false, v_created);
  if p_submitted is null then return; end if;
  insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
  values (v_id, 'system', null, 'submit', v_creator, null, null, false, p_submitted);
  if v_mob and p_mstatus = 'approved' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'approve', v_mobt, null, '{"version":1}', false, p_msince);
  elsif v_mob and p_mstatus = 'revision_requested' then
    insert into realisasi.activity_log (activity_id, kind, track, action, actor_id, note, diff, in_frozen_period, created_at)
    values (v_id, 'verification', 'mobility', 'request_revision', v_mobt, p_mnote, null, false, p_msince);
  end if;
end $f$;

-- participant set v1: PETRA students (internal), inbound students and internal staff from the mock registries
create or replace function pg_temp.peserta(p_n int, p_status text, p_internal text[], p_inbound text[], p_staff text[],
  p_submitted timestamptz, p_reviewed timestamptz) returns void language plpgsql as $f$
declare v_act uuid := pg_temp.aid(p_n); v_id uuid := md5(pg_temp.aid(p_n)::text || ':v1')::uuid; v_by uuid;
begin
  if exists (select 1 from realisasi.participant_set_versions where id = v_id) then return; end if;
  select created_by into v_by from realisasi.activities where id = v_act;
  insert into realisasi.participant_set_versions (id, activity_id, version, status, submitted_by, submitted_at, reviewed_by, reviewed_at)
  values (v_id, v_act, 1, p_status::realisasi.pset_status, case when p_submitted is not null then v_by end, p_submitted,
          case when p_reviewed is not null then pg_temp.akun(case when p_n % 2 = 0 then 10 else 11 end) end, p_reviewed);
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name)
  select v_id, 'internal', s.nrp, s.full_name, s.faculty_name, s.prodi_name
    from unnest(p_internal) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_students (set_version_id, section, nrp, full_name, faculty_name, prodi_name,
              home_institution, home_student_number, home_country_code)
  select v_id, 'inbound', s.nrp, s.full_name, s.faculty_name, s.prodi_name, s.home_institution, 'HS-' || right(s.nrp, 5), s.home_country_code
    from unnest(p_inbound) with ordinality x(nrp, o) join mock_baak.students s on s.nrp = x.nrp order by o;
  insert into realisasi.participant_staff (set_version_id, employee_id, full_name, unit_name)
  select v_id, e.employee_id, e.full_name, e.unit_name
    from unnest(p_staff) with ordinality x(id, o) join mock_hr.employees e on e.employee_id = x.id order by o;
  if (select count(*) from realisasi.participant_students where set_version_id = v_id)
     <> coalesce(cardinality(p_internal), 0) + coalesce(cardinality(p_inbound), 0) then
    raise exception 'kegiatan %: a student NRP is missing from mock_baak.students', p_n;
  end if;
end $f$;
"""


def keg_sql(k: Keg) -> str:
    import json
    lines = [f"-- {k.n}: {PRODI_BY_ID[k.unit].unit}"]
    lines.append(
        "select pg_temp.keg({n}, {name}, {unit}, {agenda}, {dir}, {s}, {e}, {mode}, {venue}, {country}, {doc}, {sdgs}, "
        "{sub}, {ms}, {msince}, {files}, {note}, {ext});".format(
            n=k.n, name=q(k.name), unit=k.unit, agenda=k.agenda, dir=q(k.direction), s=q(k.start), e=q(k.end),
            mode=q(k.mode), venue=q(k.venue), country=q(k.country), doc=k.doc, sdgs=arr(map(str, k.sdgs)),
            sub=q(k.submitted), ms=q(k.mstatus), msince=q(k.msince), files=q(k.files), note=q(k.mnote),
            ext=q(json.dumps(k.ext, ensure_ascii=False)) + "::jsonb"))
    if k.agenda in MOB_AGENDAS and k.pset_status:
        lines.append("select pg_temp.peserta({n}, {st}, {i}, {ib}, {sf}, {sub}, {rv});".format(
            n=k.n, st=q(k.pset_status), i=arr(s.nrp for s in k.internal), ib=arr(s.nrp for s in k.inbound),
            sf=arr(e.id for e in k.staff), sub=q(k.submitted), rv=q(k.reviewed)))
    if k.conflict:
        lines.append(f"select realisasi._scan_conflicts(pg_temp.aid({k.n})) where not exists "
                     f"(select 1 from realisasi.participant_conflicts where pg_temp.aid({k.n}) in (activity_a, activity_b));")
    return "\n".join(lines)


def write(name: str, what: str, body: str) -> None:
    (OUT / name).write_text(HEADER.format(name=name.removesuffix(".sql"), what=what) + body.rstrip() + "\n")
    print("wrote", (OUT / name).relative_to(ROOT))


# 05 registries
reg = ["\n-- PETRA students of every Program Studi (prodi_name = the SIMKS unit name without \"Prodi\"/\"Program Studi\")",
       "insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values"]
rows = [f"  ({q(s.nrp)}, {q(s.name)}, {q(s.nrp[0])}, {q(s.prodi.faculty)}, {q(s.prodi.baak)}, 'regular', null, null, {s.intake}, 'active')"
        for s in students]
reg.append(",\n".join(rows) + "\non conflict (nrp) do nothing;")
reg.append("\n-- inbound exchange students from the partner universities")
reg.append("insert into mock_baak.students (nrp, full_name, faculty_code, faculty_name, prodi_name, category, home_institution, home_country_code, intake_year, status) values")
rows = [f"  ({q(s.nrp)}, {q(s.name)}, 'X', 'Kantor Kerja Sama dan Urusan Internasional', 'Program Pertukaran (Inbound)', 'inbound_exchange', {q(s.home[0])}, {q(s.home[1])}, {s.intake}, 'active')"
        for cc in inbound for s in inbound[cc]]
reg.append(",\n".join(rows) + "\non conflict (nrp) do nothing;")
reg.append("\n-- lecturers and heads of every Program Studi")
reg.append("insert into mock_hr.employees (employee_id, full_name, unit_name, position, status) values")
rows = [f"  ({q(e.id)}, {q(e.name)}, {q(e.unit)}, {q(e.position)}, 'active')" for e in employees]
reg.append(",\n".join(rows) + "\non conflict (employee_id) do nothing;")
write("05_registries_bulk.sql",
      f"Mock BAAK/HR registries for the bulk kegiatan: {len(students)} PETRA students across {len(PRODI)} Program Studi, "
      f"{sum(len(v) for v in inbound.values())} inbound exchange students, {len(employees)} lecturers.",
      "\n".join(reg))

# 06 a-e: AY 2025/2026 in five steps of 20; 07: AY 2026/2027
ay1_sorted = sorted(ay1, key=lambda k: k.n)
for i in range(5):
    part = ay1_sorted[i * 20:(i + 1) * 20]
    write(f"06_kegiatan_2025_2026_{'abcde'[i]}.sql",
          f"AY 2025/2026 step {i + 1}/5: kegiatan {part[0].n}-{part[-1].n} (all by Program Studi), with peserta.",
          HELPERS + "\n" + "\n\n".join(keg_sql(k) for k in part))
ay2_sorted = sorted(ay2, key=lambda k: k.n)
write("07_kegiatan_2026_2027.sql",
      f"AY 2026/2027 up to 2026-10-03: kegiatan {ay2_sorted[0].n}-{ay2_sorted[-1].n} (verified, waiting for Mobility incl. one "
      "duplicate-student decision, in revision, drafts).",
      HELPERS + "\n" + "\n\n".join(keg_sql(k) for k in ay2_sorted)
      + "\n\nselect setval('realisasi.activity_code_seq', greatest(300, (select last_value from realisasi.activity_code_seq)));")

# 08 refreeze
write("08_refreeze_2025_2026.sql",
      "Re-freezes the AY 2025/2026 snapshots once after the bulk import (R-58), as of their original freeze moments, so\n"
      "-- Ganjil and Setahun include the imported kegiatan; the earlier snapshots stay as superseded. No-op on a fresh install\n"
      "-- (90_freeze.sql freezes later) and when already done.",
      """
do $$
declare s realisasi.kpi_snapshots; v_reason text := 'Bekukan ulang setelah impor data kegiatan 2025/2026';
begin
  for s in select * from realisasi.kpi_snapshots
            where academic_year_id = 1 and superseded_by is null and refreeze_reason is distinct from v_reason
              and exists (select 1 from realisasi.activities a where a.id = ('b5000000-0000-4000-8000-' || lpad('101', 12, '0'))::uuid)
            order by frozen_at
  loop
    perform realisasi._freeze(s.academic_year_id, s.kind, s.frozen_at, (select id from kerjasama.profiles where akun_id = 1),
                              v_reason, s.id);
  end loop;
end $$;""")

# summary for the console
from collections import Counter
print("AY1 states:", Counter((k.mstatus or ("verified" if k.submitted else "draft")) for k in ay1))
print("AY2 states:", Counter((k.mstatus or ("verified" if k.submitted else "draft")) for k in ay2))
print("units:", len({k.unit for k in kegiatan}), "prodis; students used:",
      sum(len(k.internal) + len(k.inbound) for k in kegiatan), "; external persons:", sum(len(k.ext) for k in kegiatan))
