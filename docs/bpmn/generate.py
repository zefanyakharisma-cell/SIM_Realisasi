#!/usr/bin/env python3
"""Generate the SIM Realisasi business-process diagrams (BPMN 2.0, Bizagi style).

One layout model per process drives two outputs:
  *.bpmn  BPMN 2.0 XML with diagram interchange (import into Bizagi Modeler or bpmn.io)
  *.svg   Bizagi-styled render (pools, lanes, gradient tasks, gateways, events)

Behaviour follows docs/spec/Rules.md v1.1 (Revisi V.1). Run: python3 docs/bpmn/generate.py
"""
from __future__ import annotations

import html
import os
from dataclasses import dataclass, field

OUT = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- geometry
POOL_X = 20
POOL_HDR = 34
LANE_HDR = 34
COL_W = 140
COL0 = POOL_X + POOL_HDR + LANE_HDR + 46  # centre x of column 0
LANE_H = 270
ROW_Y = {"A": 55, "M": 135, "B": 215}  # row centres inside a lane
TASK_W, TASK_H = 120, 64
GW = 46  # gateway diamond size
EV_R = 16
EXT_POOL_H = 60


def cx(col: float) -> float:
    return COL0 + col * COL_W


@dataclass
class Node:
    id: str
    kind: str  # start | end | task | gateway
    name: str
    lane: str
    col: float
    row: str = "M"
    task_type: str = "user"  # user | service | send
    event: str | None = None  # timer | conditional (start events)
    event_text: str = ""
    gw_label: str = "top"  # top | bottom
    x: float = 0
    y: float = 0

    @property
    def w(self) -> float:
        return TASK_W if self.kind == "task" else GW if self.kind == "gateway" else EV_R * 2

    @property
    def h(self) -> float:
        return TASK_H if self.kind == "task" else GW if self.kind == "gateway" else EV_R * 2

    def side(self, s: str) -> tuple[float, float]:
        return {
            "top": (self.x, self.y - self.h / 2),
            "bottom": (self.x, self.y + self.h / 2),
            "left": (self.x - self.w / 2, self.y),
            "right": (self.x + self.w / 2, self.y),
        }[s]


@dataclass
class Flow:
    src: str
    tgt: str
    route: str = "H"  # H | HV | VH | V
    name: str = ""


@dataclass
class Lane:
    id: str
    name: str


@dataclass
class ExtPool:
    id: str
    name: str
    where: str  # top | bottom


@dataclass
class MsgFlow:
    id: str
    node: str
    pool: str
    to_pool: bool  # True: node -> pool, False: pool -> node
    name: str


@dataclass
class Note:
    """Text annotation placed in a lane cell, linked to a node by a dotted association."""
    id: str
    text: str
    lane: str
    col: float
    row: str
    node: str
    w: float = 170
    h: float = 52
    x: float = 0
    y: float = 0


@dataclass
class Process:
    key: str
    title: str
    pool_name: str
    lanes: list[Lane]
    nodes: list[Node]
    flows: list[Flow]
    cols: int
    ext: list[ExtPool] = field(default_factory=list)
    msgs: list[MsgFlow] = field(default_factory=list)
    notes: list[Note] = field(default_factory=list)


# ---------------------------------------------------------------- process 1
def process_submission() -> Process:
    U, M, S = "lane_unit", "lane_mob", "lane_sys"
    lanes = [
        Lane(U, "Unit Akademik (Pengaju)"),
        Lane(M, "Tim Mobilitas IO"),
        Lane(S, "SIM Realisasi (Sistem)"),
    ]
    n = [
        Node("start", "start", "Kegiatan kerja sama selesai dilaksanakan", U, 0),
        Node("t_detail", "task", "Isi Detail kegiatan & pilih Kerja Sama", U, 1),
        Node("t_draft", "task", "Simpan draf; tetapkan semester/TA & batas lapor", S, 2, task_type="service"),
        Node("g_mob", "gateway", "Kegiatan mobilitas?", U, 3, gw_label="right"),
        Node("t_files", "task", "Unggah IA & IR (PDF) + bukti opsional", U, 4, "A"),
        Node("t_peserta", "task", "Isi peserta (NRP mahasiswa, NIP pegawai, inbound)", U, 4, "B"),
        Node("t_lookup", "task", "Lookup NRP/NIP ke data BAAK & HR", S, 4, task_type="service"),
        Node("g_valid", "gateway", "Semua NRP/NIP ditemukan?", S, 5, gw_label="bottom"),
        Node("t_files_mob", "task", "Unggah IA, IR & PDF mobilitas (gabungan)", U, 6, "B"),
        Node("g_m1", "gateway", "", U, 7),
        Node("t_submit", "task", "Ajukan kegiatan", U, 8),
        Node("t_validate", "task", "Validasi pengajuan; tandai Terlambat bila lewat batas", S, 9, task_type="service"),
        Node("g_track", "gateway", "Jenis = kegiatan mobilitas?", S, 10, gw_label="right"),
        Node("t_auto", "task", "Status Terverifikasi (track not_required)", S, 11, "B", task_type="service"),
        Node("t_pending", "task", "Track Mobilitas = pending; deteksi duplikat mahasiswa; notifikasi", S, 11, "A", task_type="send"),
        Node("t_review", "task", "Tinjau peserta & PDF mobilitas", M, 12),
        Node("g_dup", "gateway", "Ada duplikat mahasiswa antar-unit?", M, 13, gw_label="bottom"),
        Node("t_decide", "task", "Pilih kegiatan yang mempertahankan mahasiswa", M, 14, "A"),
        Node("g_m2", "gateway", "", M, 15),
        Node("g_ok", "gateway", "Peserta & berkas sesuai?", M, 16, gw_label="bottom"),
        Node("t_revise_req", "task", "Minta revisi (catatan wajib)", M, 17, "A"),
        Node("t_revise", "task", "Perbaiki & ajukan ulang (versi peserta n+1)", U, 17, "B"),
        Node("t_approve", "task", "Setujui versi peserta", M, 18),
        Node("t_verified", "task", "Status Terverifikasi; catat verified_at; notifikasi unit", S, 19, task_type="send"),
        Node("g_m3", "gateway", "", S, 20),
        Node("t_count", "task", "Hitung ke RENSTRA per unit & International Awards", S, 21, task_type="service"),
        Node("end", "end", "Kegiatan terverifikasi & terhitung", S, 22),
    ]
    f = [
        Flow("start", "t_detail"),
        Flow("t_detail", "t_draft", "HV"),
        Flow("t_draft", "g_mob"),
        Flow("g_mob", "t_files", "VH", "Tidak"),
        Flow("g_mob", "t_peserta", "VH", "Ya"),
        Flow("t_peserta", "t_lookup", "V"),
        Flow("t_lookup", "g_valid"),
        Flow("g_valid", "t_peserta", "VH", "Tidak"),
        Flow("g_valid", "t_files_mob", "HV", "Ya"),
        Flow("t_files", "g_m1", "HV"),
        Flow("t_files_mob", "g_m1", "HV"),
        Flow("g_m1", "t_submit"),
        Flow("t_submit", "t_validate", "HV"),
        Flow("t_validate", "g_track"),
        Flow("g_track", "t_pending", "VH", "Ya"),
        Flow("g_track", "t_auto", "VH", "Tidak"),
        Flow("t_auto", "g_m3", "HV"),
        Flow("t_pending", "t_review", "HV"),
        Flow("t_review", "g_dup"),
        Flow("g_dup", "t_decide", "VH", "Ya"),
        Flow("g_dup", "g_m2", "H", "Tidak"),
        Flow("t_decide", "g_m2", "HV"),
        Flow("g_m2", "g_ok"),
        Flow("g_ok", "t_revise_req", "VH", "Tidak"),
        Flow("g_ok", "t_approve", "H", "Ya"),
        Flow("t_revise_req", "t_revise", "V"),
        Flow("t_revise", "t_pending", "HV"),
        Flow("t_approve", "t_verified", "HV"),
        Flow("t_verified", "g_m3"),
        Flow("g_m3", "t_count"),
        Flow("t_count", "end"),
    ]
    ext = [
        ExtPool("pool_simks", "SIM Kerjasama", "top"),
        ExtPool("pool_baak", "BAAK & HR (data mahasiswa / pegawai)", "bottom"),
    ]
    msgs = [
        MsgFlow("mf_docs", "t_detail", "pool_simks", False, "Dokumen MoU/MoA berlaku pada tanggal kegiatan"),
        MsgFlow("mf_lookup", "t_lookup", "pool_baak", True, "Cek NRP / NIP"),
        MsgFlow("mf_realisasi", "t_count", "pool_simks", True, "Tab Realisasi & flag tanpa realisasi"),
    ]
    notes = [
        Note("note_draft", "Draf boleh dihapus hanya oleh pembuatnya atau IO Admin; kegiatan yang sudah diajukan tidak pernah dihapus (R-15)",
             S, 1.25, "B", "t_draft", w=200, h=58),
        Note("note_count", "Dihitung per unit: Fakultas = kegiatan sendiri + Program Studi + Program. Awards hanya memeringkat Program Studi (R-48)",
             S, 21.0, "B", "t_count", w=200, h=58),
    ]
    return Process("sim-realisasi-pengajuan-verifikasi", "Pengajuan & Verifikasi Kegiatan",
                   "SIM Realisasi: Pengajuan & Verifikasi Kegiatan", lanes, n, f, 23, ext, msgs, notes)


# ---------------------------------------------------------------- process 2
def process_semester() -> Process:
    U, S, A, V = "lane_unit", "lane_sys", "lane_admin", "lane_viewer"
    lanes = [
        Lane(U, "Unit Akademik"),
        Lane(S, "SIM Realisasi (Sistem)"),
        Lane(A, "IO Admin"),
        Lane(V, "Pimpinan (Viewer)"),
    ]
    n = [
        # A. daily reminders (R-61, R-62)
        Node("s_daily", "start", "Setiap hari", S, 0, "A", event="timer", event_text="R/P1D"),
        Node("t_scan", "task", "Periksa draf dekat batas pelaporan & revisi tertunda ≥ 7 hari", S, 1, "A", task_type="service"),
        Node("g_due", "gateway", "Ada yang perlu diingatkan?", S, 2, "A", gw_label="top"),
        Node("t_remind", "task", "Kirim pengingat (in-app + email outbox)", S, 3, "A", task_type="send"),
        Node("e_none", "end", "Tidak ada tindakan", S, 3, "M"),
        Node("t_unit", "task", "Lengkapi / ajukan kegiatan (proses Pengajuan)", U, 3),
        Node("e_unit", "end", "Pengingat ditindaklanjuti", U, 4),
        # B. semester cutoff & freeze (R-55..R-59)
        Node("s_cutoff", "start", "Tanggal cutoff semester", S, 0, "B", event="timer", event_text="cutoff_date"),
        Node("t_calc", "task", "Hitung RENSTRA 1.1, 1.19.S1, 1.19.S4 & International Awards", S, 1, "B", task_type="service"),
        Node("t_freeze", "task", "Bekukan snapshot (nilai, ID kontributor, pengaturan)", S, 2, "B", task_type="service"),
        Node("t_notify", "task", "Notifikasi snapshot beku ke IO Admin & pimpinan", S, 3, "B", task_type="send"),
        Node("t_check", "task", "Tinjau snapshot", A, 4),
        Node("g_refreeze", "gateway", "Perlu dibekukan ulang?", A, 5, gw_label="bottom"),
        Node("t_reason", "task", "Bekukan ulang dengan alasan wajib", A, 6, "A"),
        Node("t_supersede", "task", "Simpan snapshot baru; snapshot lama = superseded", S, 7, "B", task_type="service"),
        Node("g_m", "gateway", "", A, 8),
        Node("t_export", "task", "Unduh Excel per RENSTRA (tabel per unit, data kegiatan, mahasiswa)", A, 9),
        Node("t_dash", "task", "Tinjau dashboard & laporan RENSTRA per unit", V, 10),
        Node("e_report", "end", "Laporan semester tersedia", V, 11),
        # C. late additions / post-freeze edits (R-31, R-57)
        Node("s_late", "start", "Kegiatan diverifikasi / diubah bertanggal di periode beku", S, 5, "A",
             event="conditional", event_text="activity_date within frozen window"),
        Node("t_flag", "task", "Tandai Tambahan Susulan / Perubahan Pasca-Beku", S, 6, "A", task_type="service"),
        Node("t_next", "task", "Tampilkan di YTD & laporan snapshot berikutnya", S, 7, "A", task_type="service"),
        Node("e_late", "end", "Snapshot lama tetap", S, 8, "A"),
    ]
    f = [
        Flow("s_daily", "t_scan"),
        Flow("t_scan", "g_due"),
        Flow("g_due", "t_remind", "H", "Ya"),
        Flow("g_due", "e_none", "VH", "Tidak"),
        Flow("t_remind", "t_unit", "V"),
        Flow("t_unit", "e_unit"),
        Flow("s_cutoff", "t_calc"),
        Flow("t_calc", "t_freeze"),
        Flow("t_freeze", "t_notify"),
        Flow("t_notify", "t_check", "HV"),
        Flow("t_check", "g_refreeze"),
        Flow("g_refreeze", "t_reason", "VH", "Ya"),
        Flow("g_refreeze", "g_m", "H", "Tidak"),
        Flow("t_reason", "t_supersede", "HV"),
        Flow("t_supersede", "g_m", "HV"),
        Flow("g_m", "t_export"),
        Flow("t_export", "t_dash", "HV"),
        Flow("t_dash", "e_report"),
        Flow("s_late", "t_flag"),
        Flow("t_flag", "t_next"),
        Flow("t_next", "e_late"),
    ]
    notes = [
        Note("note_period", "Periode: Ganjil, Genap, Setahun (kumulatif), YTD. YTD hanya untuk TA aktif dan tidak pernah dibekukan (R-37)",
             V, 7.2, "M", "t_dash", w=230, h=58),
    ]
    return Process("sim-realisasi-tutup-semester", "Pengingat, Tutup Semester & Pelaporan",
                   "SIM Realisasi: Pengingat, Tutup Semester & Pelaporan", lanes, n, f, 12, notes=notes)


# ---------------------------------------------------------------- layout
def layout(p: Process):
    """Place pools, lanes and nodes. Returns pool/lane rectangles."""
    y = 20
    pools: dict[str, tuple[float, float, float, float]] = {}
    width = POOL_HDR + LANE_HDR + 46 + (p.cols - 1) * COL_W + 110
    for e in p.ext:
        if e.where == "top":
            pools[e.id] = (POOL_X, y, width, EXT_POOL_H)
            y += EXT_POOL_H + 50
    main_y = y
    lanes: dict[str, tuple[float, float, float, float]] = {}
    for ln in p.lanes:
        lanes[ln.id] = (POOL_X + POOL_HDR, y, width - POOL_HDR, LANE_H)
        y += LANE_H
    pools["main"] = (POOL_X, main_y, width, y - main_y)
    for e in p.ext:
        if e.where == "bottom":
            y += 50
            pools[e.id] = (POOL_X, y, width, EXT_POOL_H)
            y += EXT_POOL_H
    for nd in p.nodes:
        lx, ly, _, _ = lanes[nd.lane]
        nd.x, nd.y = cx(nd.col), ly + ROW_Y[nd.row]
    for nt in p.notes:
        lx, ly, _, _ = lanes[nt.lane]
        nt.x, nt.y = cx(nt.col), ly + ROW_Y[nt.row]
    return pools, lanes, POOL_X + width + 20, y + 20


def waypoints(fl: Flow, nodes: dict[str, Node]):
    s, t = nodes[fl.src], nodes[fl.tgt]
    if fl.route == "H":
        a, b = s.side("right"), t.side("left")
        if abs(a[1] - b[1]) < 1:
            return [a, b]
        mx = (a[0] + b[0]) / 2
        return [a, (mx, a[1]), (mx, b[1]), b]
    if fl.route == "V":
        if t.y < s.y:
            return [s.side("top"), t.side("bottom")]
        return [s.side("bottom"), t.side("top")]
    if fl.route == "HV":
        a = s.side("right") if t.x > s.x else s.side("left")
        b = t.side("bottom") if t.y < s.y else t.side("top")
        return [a, (b[0], a[1]), b]
    if fl.route == "VH":
        a = s.side("top") if t.y < s.y else s.side("bottom")
        b = t.side("left") if t.x > s.x else t.side("right")
        return [a, (a[0], b[1]), b]
    raise ValueError(fl.route)


def msg_waypoints(m: MsgFlow, nodes, pools):
    nd = nodes[m.node]
    px, py, pw, ph = pools[m.pool]
    if py < nd.y:  # pool above
        a, b = (nd.x, py + ph), nd.side("top")
    else:
        a, b = (nd.x, py), nd.side("bottom")
    return [b, a] if m.to_pool else [a, b]


def note_link(nt: Note, nodes):
    """Dotted association from the annotation's nearest edge to the node."""
    nd = nodes[nt.node]
    if nd.y + nd.h / 2 <= nt.y - nt.h / 2:  # node above the note
        return [(nt.x, nt.y - nt.h / 2), nd.side("bottom")]
    if nd.y - nd.h / 2 >= nt.y + nt.h / 2:
        return [(nt.x, nt.y + nt.h / 2), nd.side("top")]
    if nd.x < nt.x:
        return [(nt.x - nt.w / 2, nt.y), nd.side("right")]
    return [(nt.x + nt.w / 2, nt.y), nd.side("left")]


# ---------------------------------------------------------------- BPMN XML
def esc(s: str) -> str:
    return html.escape(s, quote=True)


def to_bpmn(p: Process) -> str:
    pools, lanes, _, _ = layout(p)
    nodes = {nd.id: nd for nd in p.nodes}
    pid = f"Process_{p.key.replace('-', '_')}"
    flows = [(f"Flow_{i+1}", fl) for i, fl in enumerate(p.flows)]
    incoming: dict[str, list[str]] = {nd.id: [] for nd in p.nodes}
    outgoing: dict[str, list[str]] = {nd.id: [] for nd in p.nodes}
    for fid, fl in flows:
        outgoing[fl.src].append(fid)
        incoming[fl.tgt].append(fid)

    L: list[str] = []
    w = L.append
    w('<?xml version="1.0" encoding="UTF-8"?>')
    w('<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" '
      'xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" '
      'xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" '
      'xmlns:di="http://www.omg.org/spec/DD/20100524/DI" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      f'id="Definitions_{pid}" targetNamespace="https://petra.ac.id/sim-realisasi/bpmn" '
      'exporter="SIM Realisasi docs/bpmn/generate.py" exporterVersion="1.0">')
    w(f'  <bpmn:collaboration id="Collab_{pid}">')
    w(f'    <bpmn:participant id="Participant_main" name="{esc(p.pool_name)}" processRef="{pid}" />')
    for e in p.ext:
        w(f'    <bpmn:participant id="{e.id}" name="{esc(e.name)}" />')
    for m in p.msgs:
        src, tgt = (m.node, m.pool) if m.to_pool else (m.pool, m.node)
        w(f'    <bpmn:messageFlow id="{m.id}" name="{esc(m.name)}" sourceRef="{src}" targetRef="{tgt}" />')
    w('  </bpmn:collaboration>')
    w(f'  <bpmn:process id="{pid}" name="{esc(p.title)}" isExecutable="false">')
    w('    <bpmn:laneSet id="LaneSet_1">')
    for ln in p.lanes:
        w(f'      <bpmn:lane id="{ln.id}" name="{esc(ln.name)}">')
        for nd in p.nodes:
            if nd.lane == ln.id:
                w(f'        <bpmn:flowNodeRef>{nd.id}</bpmn:flowNodeRef>')
        w('      </bpmn:lane>')
    w('    </bpmn:laneSet>')
    for nd in p.nodes:
        tag = {
            "start": "startEvent", "end": "endEvent", "gateway": "exclusiveGateway",
            "task": {"user": "userTask", "service": "serviceTask", "send": "sendTask"}[nd.task_type],
        }[nd.kind]
        w(f'    <bpmn:{tag} id="{nd.id}" name="{esc(nd.name)}">')
        for fid in incoming[nd.id]:
            w(f'      <bpmn:incoming>{fid}</bpmn:incoming>')
        for fid in outgoing[nd.id]:
            w(f'      <bpmn:outgoing>{fid}</bpmn:outgoing>')
        if nd.event == "timer":
            expr = "timeCycle" if nd.event_text.startswith("R/") else "timeDate"
            w(f'      <bpmn:timerEventDefinition id="{nd.id}_def"><bpmn:{expr} xsi:type="bpmn:tFormalExpression">'
              f'{esc(nd.event_text)}</bpmn:{expr}></bpmn:timerEventDefinition>')
        elif nd.event == "conditional":
            w(f'      <bpmn:conditionalEventDefinition id="{nd.id}_def"><bpmn:condition xsi:type="bpmn:tFormalExpression">'
              f'{esc(nd.event_text)}</bpmn:condition></bpmn:conditionalEventDefinition>')
        w(f'    </bpmn:{tag}>')
    for fid, fl in flows:
        name = f' name="{esc(fl.name)}"' if fl.name else ""
        w(f'    <bpmn:sequenceFlow id="{fid}"{name} sourceRef="{fl.src}" targetRef="{fl.tgt}" />')
    for nt in p.notes:
        w(f'    <bpmn:textAnnotation id="{nt.id}"><bpmn:text>{esc(nt.text)}</bpmn:text></bpmn:textAnnotation>')
        w(f'    <bpmn:association id="{nt.id}_assoc" sourceRef="{nt.id}" targetRef="{nt.node}" />')
    w('  </bpmn:process>')

    w(f'  <bpmndi:BPMNDiagram id="Diagram_{pid}" name="{esc(p.title)}">')
    w(f'    <bpmndi:BPMNPlane id="Plane_{pid}" bpmnElement="Collab_{pid}">')

    def bounds(x, y, ww, hh):
        return f'<dc:Bounds x="{x:.0f}" y="{y:.0f}" width="{ww:.0f}" height="{hh:.0f}" />'

    w(f'      <bpmndi:BPMNShape id="Participant_main_di" bpmnElement="Participant_main" isHorizontal="true">'
      f'{bounds(*pools["main"])}</bpmndi:BPMNShape>')
    for e in p.ext:
        w(f'      <bpmndi:BPMNShape id="{e.id}_di" bpmnElement="{e.id}" isHorizontal="true">'
          f'{bounds(*pools[e.id])}</bpmndi:BPMNShape>')
    for ln in p.lanes:
        w(f'      <bpmndi:BPMNShape id="{ln.id}_di" bpmnElement="{ln.id}" isHorizontal="true">'
          f'{bounds(*lanes[ln.id])}</bpmndi:BPMNShape>')
    for nd in p.nodes:
        marker = ' isMarkerVisible="true"' if nd.kind == "gateway" else ""
        w(f'      <bpmndi:BPMNShape id="{nd.id}_di" bpmnElement="{nd.id}"{marker}>'
          f'{bounds(nd.x - nd.w / 2, nd.y - nd.h / 2, nd.w, nd.h)}</bpmndi:BPMNShape>')
    for fid, fl in flows:
        pts = "".join(f'<di:waypoint x="{x:.0f}" y="{y:.0f}" />' for x, y in waypoints(fl, nodes))
        w(f'      <bpmndi:BPMNEdge id="{fid}_di" bpmnElement="{fid}">{pts}</bpmndi:BPMNEdge>')
    for nt in p.notes:
        w(f'      <bpmndi:BPMNShape id="{nt.id}_di" bpmnElement="{nt.id}">'
          f'{bounds(nt.x - nt.w / 2, nt.y - nt.h / 2, nt.w, nt.h)}</bpmndi:BPMNShape>')
        pts = "".join(f'<di:waypoint x="{x:.0f}" y="{y:.0f}" />' for x, y in note_link(nt, nodes))
        w(f'      <bpmndi:BPMNEdge id="{nt.id}_assoc_di" bpmnElement="{nt.id}_assoc">{pts}</bpmndi:BPMNEdge>')
    for m in p.msgs:
        pts = "".join(f'<di:waypoint x="{x:.0f}" y="{y:.0f}" />' for x, y in msg_waypoints(m, nodes, pools))
        w(f'      <bpmndi:BPMNEdge id="{m.id}_di" bpmnElement="{m.id}">{pts}</bpmndi:BPMNEdge>')
    w('    </bpmndi:BPMNPlane>')
    w('  </bpmndi:BPMNDiagram>')
    w('</bpmn:definitions>')
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- SVG (Bizagi look)
C = {
    "pool_hdr": "#DCE6F0", "lane_hdr": "#EEF3F8", "lane_bg": "#FFFFFF", "lane_bg2": "#FAFCFE",
    "border": "#5B6B7B", "text": "#1F2A36", "flow": "#33414F",
    "task_top": "#FFFFFF", "task_bot": "#D5E8F7", "task_stroke": "#2A6EA6",
    "gw_top": "#FFFDE6", "gw_bot": "#F7E58E", "gw_stroke": "#A8870B",
    "start_fill": "#EAF6DD", "start_stroke": "#4C9A0F",
    "end_fill": "#FCE3E0", "end_stroke": "#C0262C",
    "msg": "#6A7785", "ext_bg": "#F3F4F6",
}
FONT = "Segoe UI, Helvetica Neue, Arial, sans-serif"


def wrap(text: str, max_chars: int) -> list[str]:
    words, lines, cur = text.split(), [], ""
    for wd in words:
        if cur and len(cur) + 1 + len(wd) > max_chars:
            lines.append(cur)
            cur = wd
        else:
            cur = f"{cur} {wd}".strip()
    if cur:
        lines.append(cur)
    return lines


def text_block(x, y, lines, size=11, weight="normal", anchor="middle", color=None) -> str:
    color = color or C["text"]
    lh = size + 2.5
    y0 = y - (len(lines) - 1) * lh / 2 + size * 0.35
    spans = "".join(f'<tspan x="{x:.1f}" y="{y0 + i * lh:.1f}">{esc(t)}</tspan>' for i, t in enumerate(lines))
    return (f'<text font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{color}" '
            f'text-anchor="{anchor}">{spans}</text>')


def icon(nd: Node) -> str:
    x, y = nd.x - TASK_W / 2 + 8, nd.y - TASK_H / 2 + 7
    s = C["task_stroke"]
    if nd.task_type == "user":
        return (f'<g fill="none" stroke="{s}" stroke-width="1"><circle cx="{x+6}" cy="{y+4}" r="3.2"/>'
                f'<path d="M{x} {y+14} q0 -6 6 -6 q6 0 6 6 z" fill="#FFFFFF"/></g>')
    if nd.task_type == "service":
        teeth = "".join(
            f'<rect x="{x+5}" y="{y-1}" width="2.4" height="4" transform="rotate({a} {x+6.2} {y+6})" fill="{s}"/>'
            for a in range(0, 360, 45))
        return (f'<g>{teeth}<circle cx="{x+6.2}" cy="{y+6}" r="4.6" fill="#FFFFFF" stroke="{s}" stroke-width="1.2"/>'
                f'<circle cx="{x+6.2}" cy="{y+6}" r="1.7" fill="{s}"/></g>')
    # send: filled envelope
    return (f'<g><rect x="{x}" y="{y+1}" width="14" height="10" fill="{s}"/>'
            f'<path d="M{x} {y+1} l7 5.5 l7 -5.5" fill="none" stroke="#FFFFFF" stroke-width="1"/></g>')


def arrow_path(pts) -> str:
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)


def to_svg(p: Process) -> str:
    pools, lanes, W, H = layout(p)
    nodes = {nd.id: nd for nd in p.nodes}
    o: list[str] = []
    a = o.append
    a(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:.0f} {H:.0f}" width="{W:.0f}" height="{H:.0f}" '
      f'role="img" aria-label="{esc(p.pool_name)}">')
    a('<defs>'
      f'<linearGradient id="gTask" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{C["task_top"]}"/>'
      f'<stop offset="1" stop-color="{C["task_bot"]}"/></linearGradient>'
      f'<linearGradient id="gGw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{C["gw_top"]}"/>'
      f'<stop offset="1" stop-color="{C["gw_bot"]}"/></linearGradient>'
      '<filter id="shadow" x="-10%" y="-10%" width="130%" height="140%">'
      '<feDropShadow dx="1.5" dy="2" stdDeviation="1.4" flood-color="#000" flood-opacity="0.18"/></filter>'
      f'<marker id="arr" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="9" markerHeight="9" orient="auto-start-reverse">'
      f'<path d="M0 0 L10 5 L0 10 z" fill="{C["flow"]}"/></marker>'
      f'<marker id="marr" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="10" markerHeight="10" orient="auto-start-reverse">'
      f'<path d="M0 0 L10 5 L0 10 z" fill="#FFFFFF" stroke="{C["msg"]}" stroke-width="1"/></marker>'
      f'<marker id="mstart" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="8" markerHeight="8">'
      f'<circle cx="5" cy="5" r="4" fill="#FFFFFF" stroke="{C["msg"]}" stroke-width="1"/></marker>'
      '</defs>')
    a(f'<rect width="{W:.0f}" height="{H:.0f}" fill="#FFFFFF"/>')

    # external (collapsed) pools
    for e in p.ext:
        x, y, w, h = pools[e.id]
        a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{C["ext_bg"]}" stroke="{C["border"]}" stroke-width="1.4"/>')
        a(text_block(x + w / 2, y + h / 2, [e.name], 13, "600"))

    # main pool + lanes
    x, y, w, h = pools["main"]
    a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{C["lane_bg"]}" stroke="{C["border"]}" stroke-width="1.6"/>')
    a(f'<rect x="{x}" y="{y}" width="{POOL_HDR}" height="{h}" fill="{C["pool_hdr"]}" stroke="{C["border"]}" stroke-width="1.6"/>')
    tx, ty = x + POOL_HDR / 2, y + h / 2
    a(f'<g transform="rotate(-90 {tx} {ty})">{text_block(tx, ty, [p.pool_name], 13, "700")}</g>')
    for i, ln in enumerate(p.lanes):
        lx, ly, lw, lh = lanes[ln.id]
        a(f'<rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" fill="{C["lane_bg2"] if i % 2 else C["lane_bg"]}" '
          f'stroke="{C["border"]}" stroke-width="1"/>')
        a(f'<rect x="{lx}" y="{ly}" width="{LANE_HDR}" height="{lh}" fill="{C["lane_hdr"]}" stroke="{C["border"]}" stroke-width="1"/>')
        tx, ty = lx + LANE_HDR / 2, ly + lh / 2
        a(f'<g transform="rotate(-90 {tx} {ty})">{text_block(tx, ty, wrap(ln.name, 34), 12, "600")}</g>')

    # sequence flows (under shapes)
    for fl in p.flows:
        pts = waypoints(fl, nodes)
        a(f'<path d="{arrow_path(pts)}" fill="none" stroke="{C["flow"]}" stroke-width="1.3" '
          f'stroke-linejoin="round" marker-end="url(#arr)"/>')
        if fl.name:
            (x1, y1), (x2, y2) = pts[0], pts[1]
            if abs(x1 - x2) < 1:  # leaves vertically
                lx, ly = x1 - 6, y1 + (-10 if y2 < y1 else 16)
                anchor = "end"
            else:
                lx, ly = x1 + (8 if x2 > x1 else -8), y1 - 7
                anchor = "start" if x2 > x1 else "end"
            a(text_block(lx, ly, [fl.name], 10.5, "600", anchor, "#4A5866"))

    # message flows
    for m in p.msgs:
        pts = msg_waypoints(m, nodes, pools)
        a(f'<path d="{arrow_path(pts)}" fill="none" stroke="{C["msg"]}" stroke-width="1.2" stroke-dasharray="6 4" '
          f'marker-start="url(#mstart)" marker-end="url(#marr)"/>')
        midy = (pts[0][1] + pts[1][1]) / 2
        nd = nodes[m.node]
        my = midy if abs(pts[0][1] - pts[1][1]) < 140 else (pools[m.pool][1] + (pools[m.pool][3] + 26 if pools[m.pool][1] < nd.y else -22))
        a(text_block(pts[0][0] + 7, my, wrap(m.name, 30), 10, "normal", "start", C["msg"]))

    # text annotations (Bizagi: open bracket + dotted association)
    for nt in p.notes:
        (x1, y1), (x2, y2) = note_link(nt, nodes)
        a(f'<path d="M{x1:.1f} {y1:.1f} L{x2:.1f} {y2:.1f}" stroke="{C["msg"]}" stroke-width="1.1" stroke-dasharray="2 3" fill="none"/>')
        l, t, r, b = nt.x - nt.w / 2, nt.y - nt.h / 2, nt.x + nt.w / 2, nt.y + nt.h / 2
        a(f'<rect x="{l}" y="{t}" width="{nt.w}" height="{nt.h}" fill="#FFFDF2" stroke="none"/>')
        a(f'<path d="M{l+14} {t} H{l} V{b} H{l+14}" fill="none" stroke="{C["msg"]}" stroke-width="1.3"/>')
        lines = wrap(nt.text, int(nt.w / 5.6))
        a(text_block(l + 8, nt.y, lines, 10, "normal", "start", "#3D4A57"))

    # nodes
    for nd in p.nodes:
        if nd.kind == "task":
            a(f'<rect x="{nd.x - TASK_W/2}" y="{nd.y - TASK_H/2}" width="{TASK_W}" height="{TASK_H}" rx="9" '
              f'fill="url(#gTask)" stroke="{C["task_stroke"]}" stroke-width="1.3" filter="url(#shadow)"/>')
            a(icon(nd))
            a(text_block(nd.x + 3, nd.y + 6, wrap(nd.name, 20), 10.5))
        elif nd.kind == "gateway":
            hw = GW / 2
            a(f'<path d="M{nd.x} {nd.y-hw} L{nd.x+hw} {nd.y} L{nd.x} {nd.y+hw} L{nd.x-hw} {nd.y} z" fill="url(#gGw)" '
              f'stroke="{C["gw_stroke"]}" stroke-width="1.4" filter="url(#shadow)"/>')
            if nd.name:
                d = 7.5
                a(f'<path d="M{nd.x-d} {nd.y-d} L{nd.x+d} {nd.y+d} M{nd.x+d} {nd.y-d} L{nd.x-d} {nd.y+d}" '
                  f'stroke="{C["gw_stroke"]}" stroke-width="2.6" stroke-linecap="round"/>')
                lines = wrap(nd.name, 18)
                if nd.gw_label == "top":
                    a(text_block(nd.x, nd.y - hw - 8 - (len(lines) - 1) * 6.5, lines, 10.5, "600"))
                elif nd.gw_label == "right":
                    a(text_block(nd.x + hw - 2, nd.y + hw + 2 + (len(lines) - 1) * 6.5, lines, 10.5, "600", "start"))
                else:
                    a(text_block(nd.x, nd.y + hw + 12 + (len(lines) - 1) * 6.5, lines, 10.5, "600"))
        else:
            start = nd.kind == "start"
            a(f'<circle cx="{nd.x}" cy="{nd.y}" r="{EV_R}" fill="{C["start_fill"] if start else C["end_fill"]}" '
              f'stroke="{C["start_stroke"] if start else C["end_stroke"]}" stroke-width="{1.6 if start else 3.4}" '
              f'filter="url(#shadow)"/>')
            if nd.event == "timer":
                a(f'<circle cx="{nd.x}" cy="{nd.y}" r="10" fill="#FFFFFF" stroke="{C["start_stroke"]}" stroke-width="1.1"/>'
                  f'<path d="M{nd.x} {nd.y-7} L{nd.x} {nd.y} L{nd.x+5} {nd.y+2}" fill="none" stroke="{C["start_stroke"]}" stroke-width="1.2"/>')
            elif nd.event == "conditional":
                a(f'<rect x="{nd.x-6.5}" y="{nd.y-8}" width="13" height="16" fill="#FFFFFF" stroke="{C["start_stroke"]}" stroke-width="1.1"/>'
                  + "".join(f'<path d="M{nd.x-4} {nd.y-4.5+i*4.5} h8" stroke="{C["start_stroke"]}" stroke-width="1"/>' for i in range(3)))
            a(text_block(nd.x, nd.y + EV_R + 14 + (len(wrap(nd.name, 20)) - 1) * 6.5, wrap(nd.name, 20), 10.5))
    a('</svg>')
    return "\n".join(o) + "\n"


def main():
    for p in (process_submission(), process_semester()):
        with open(os.path.join(OUT, f"{p.key}.bpmn"), "w", encoding="utf-8") as fh:
            fh.write(to_bpmn(p))
        with open(os.path.join(OUT, f"{p.key}.svg"), "w", encoding="utf-8") as fh:
            fh.write(to_svg(p))
        print("wrote", p.key)


if __name__ == "__main__":
    main()
