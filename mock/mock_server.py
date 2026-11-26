#!/usr/bin/env python3
"""假播放器：在云端（GitHub 的 Mac 机器）上给 App 截图自检用，不连真播放器。

字段名、结构照着 原生播放器\\src\\Remote.cs 写；数据都是编的（专辑名、封面都不是真的）。
用法：python3 mock_server.py 8099
"""
import json
import struct
import sys
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ALBUMS = [
    # id, 专辑, 艺人, 年份, 曲数, 识别状态, 底色
    (1, "Nocturnes", "Elena Varga", "2019", 8, "matched", (70, 52, 40)),
    (2, "山水之间", "林青", "2021", 10, "matched", (40, 64, 58)),
    (3, "Kind of Late", "The Midnight Trio", "1998", 6, "matched", (30, 40, 70)),
    (4, "Goldberg Variations", "Anna Keller", "2015", 12, "matched", (90, 74, 40)),
    (5, "未知专辑 2003", "群星", "", 9, "candidates", (60, 60, 60)),
    (6, "Harbour Lights", "Sea & Stone", "2008", 11, "matched", (35, 60, 80)),
    (7, "夜航", "周默", "2017", 9, "matched", (25, 25, 45)),
    (8, "Cello Suites", "Paul Arden", "2004", 6, "matched", (80, 50, 35)),
    (9, "Live at Blue Room", "Quartet Nine", "1987", 7, "unknown", (50, 30, 55)),
    (10, "Winter Light", "Hanna Lind", "2022", 10, "matched", (70, 80, 90)),
    (11, "江南", "古月乐团", "2012", 8, "matched", (45, 70, 45)),
    (12, "Slow Motion", "Kenji Aoki", "2020", 9, "matched", (85, 40, 50)),
]

TITLES = ["Prelude", "Morning", "The River", "Blue Hour", "Interlude", "Small Hours", "Night Walk", "Echoes",
          "Last Light", "Return", "Coda", "Lullaby"]

rev = 7
state = {"playing": True, "album": 3, "index": 1, "started": time.time() - 95, "repeat": "off", "queued": None}


def album_dict(a):
    i, title, artist, year, n, ids, _ = a
    return {"id": i, "title": title, "artist": artist, "year": year, "tracks": n, "duration_s": float(n * 271),
            "cover": "c%04d" % i, "id_state": ids, "quality": "FLAC 24/96" if i % 2 else "CD 16/44.1", "added": 1763900000 + i * 3600}


def find(aid):
    for a in ALBUMS:
        if a[0] == aid:
            return a
    return None


def track(a, k, load=False):
    i, title, artist, _, n, _, _ = a
    d = {"id": i * 100 + k, "title": TITLES[k % len(TITLES)], "artist": artist, "album_id": i, "album": title,
         "cover": "c%04d" % i, "track_no": k + 1, "disc_no": 1, "duration_s": 180.0 + (k * 37 + i * 11) % 240,
         "format": "flac", "sample_rate": 96000 if i % 2 else 44100, "bits": 24 if i % 2 else 16, "lossless": True}
    if load:
        if a[0] == state["album"] and k in (state["index"], state["index"] + 1):
            d["load"] = {"state": "ready", "pct": 0, "wait_s": 0.0, "need_erase": False}
        elif a[0] == state["album"] and k == state["index"] + 2:
            d["load"] = {"state": "writing", "pct": 43, "wait_s": 9.0, "need_erase": False}
        else:
            d["load"] = {"state": "none", "pct": 0, "wait_s": float(30 + k * 4), "need_erase": k > 3}
    return d


def track_by_id(tid):
    a = find(tid // 100)
    if a is None or tid % 100 >= a[4]:
        return None
    return track(a, tid % 100)


def player_state():
    a = find(state["album"])
    cur = track(a, state["index"])
    pos = (time.time() - state["started"]) if state["playing"] else 95.0
    nxt = track(a, state["index"] + 1) if state["index"] + 1 < a[4] else None
    return {
        "rev": rev, "output": "cart", "state": "playing" if state["playing"] else "paused", "preparing": False,
        "position_s": round(pos % cur["duration_s"], 1), "duration_s": cur["duration_s"], "can_seek": False,
        "track": cur, "pending": None, "next_pick": nxt,
        "next_text": ("下一首：" + nxt["title"] + "（已预载）") if nxt else None,
        "queued_album": album_dict(find(state["queued"])) if state["queued"] else None,
        "single": False, "repeat": state["repeat"], "queue_index": state["index"], "queue_count": a[4],
        "busy": False, "firmware_busy": False, "status": "卡带库：已连接（固件 1.0.5）",
    }


def album_detail(aid):
    a = find(aid)
    if a is None:
        return None
    d = album_dict(a)
    d.update({
        "rev": rev, "genre": "Jazz" if aid % 3 == 0 else "Classical", "label": "Mock Records", "notes": None,
        "cover_source": "folder", "id_method": "exact_toc", "id_evidence": "光盘目录完全一致",
        "candidates": 3 if a[5] == "candidates" else 0, "queued": state["queued"] == aid,
        "playing_track": track(find(state["album"]), state["index"])["id"] if state["album"] == aid else None,
        "edit": {k: {"user": None, "auto": v} for k, v in (("title", a[1]), ("artist", a[2]), ("year", a[3]), ("label", "Mock Records"), ("genre", "Classical"))},
        "tracks": [track(a, k, True) for k in range(a[4])],
    })
    return d


def ours(a):
    return [{"id": a[0] * 100 + k, "title": "Track %02d" % (k + 1), "length_ms": int(track(a, k)["duration_s"] * 1000)} for k in range(a[4])]


def candidates(aid):
    a = find(aid)
    cs = []
    for j, (t, ar, y, score) in enumerate([("Morning Songs", "Various Artists", "2003", 86), ("Morning Songs (Remaster)", "Various Artists", "2011", 64), ("Songs at Dawn", "M. Rossi", "2001", 31)]):
        cs.append({"token": "%d\tmock-%d\t%s" % (aid, j, t), "title": t, "artist": ar, "year": y, "score": score, "method": "catalog_name",
                   "reason": "曲数一样，时长差不到 2 秒" if j == 0 else "曲数一样，有两首时长差得多", "release": None, "has_cover": False,
                   "tracks": [{"title": TITLES[k % len(TITLES)], "length_ms": int(track(a, k)["duration_s"] * 1000) + (j * 4200 if k % 3 == 1 else 800)} for k in range(a[4])]})
    return cs


def cards():
    a = find(state["album"])
    cur, nxt = track(a, state["index"]), track(a, state["index"] + 1)
    slots = [
        {"n": 1, "group": "A", "state": "READY", "routed_to": "A", "title": cur["title"], "track": cur, "part": 0, "current": True, "protected": True, "writing_pct": None, "erasing_s": None},
        {"n": 2, "group": "A", "state": "READY", "routed_to": "B", "title": nxt["title"], "track": nxt, "part": 0, "current": False, "protected": True, "writing_pct": None, "erasing_s": None},
        {"n": 3, "group": "A", "state": "BLANK", "routed_to": None, "title": track(a, state["index"] + 2)["title"], "track": None, "part": -1, "current": False, "protected": False, "writing_pct": 43, "erasing_s": None},
        {"n": 4, "group": "A", "state": "ERASING", "routed_to": None, "title": None, "track": None, "part": -1, "current": False, "protected": False, "writing_pct": None, "erasing_s": 52.0},
        {"n": 5, "group": "B", "state": "READY", "routed_to": None, "title": "Lullaby", "track": track(find(10), 11 % 10), "part": 0, "current": False, "protected": False, "writing_pct": None, "erasing_s": None},
        {"n": 6, "group": "B", "state": "EMPTY", "routed_to": None, "title": None, "track": None, "part": -1, "current": False, "protected": False, "writing_pct": None, "erasing_s": None},
    ]
    return {"connected": True, "firmware": "1.0.5", "writing": "卡位 3：写入 43%", "slots": slots, "ready": [cur, nxt, slots[4]["track"]]}


def png(w, h, rgb):
    """纯标准库画一张竖向渐变的 PNG 当封面"""
    r, g, b = rgb
    rows = []
    for y in range(h):
        k = 0.55 + 0.45 * (1 - y / h)
        px = bytes([min(255, int(r * k * 2)), min(255, int(g * k * 2)), min(255, int(b * k * 2))])
        rows.append(b"\x00" + px * w)
    raw = zlib.compress(b"".join(rows), 6)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("mock %s\n" % (fmt % args))

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def err(self, code, msg):
        self.send(code, {"ok": False, "error": msg})

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        p = u.path.rstrip("/")
        if p in ("", "/v1", "/v1/info"):
            return self.send(200, {"name": "MIAOW 播放器", "api": 1, "build": "2026-11-23 23:46", "host": "MOCK-PC", "urls": ["http://127.0.0.1:8099/"], "pairing": False})
        if p == "/v1/state":
            return self.send(200, player_state())
        if p == "/v1/albums":
            al = [album_dict(a) for a in ALBUMS]
            s = q.get("sort", "title")
            if s == "artist":
                al.sort(key=lambda x: x["artist"])
            elif s == "year":
                al.sort(key=lambda x: x["year"], reverse=True)
            elif s == "added":
                al.sort(key=lambda x: -x["added"])
            else:
                al.sort(key=lambda x: x["title"])
            return self.send(200, {"rev": rev, "sort": s, "total": len(al), "offset": 0, "albums": al})
        if p == "/v1/album":
            d = album_detail(int(q.get("id", "0")))
            return self.send(200, d) if d else self.err(404, "没有这张专辑")
        if p == "/v1/album/candidates":
            a = find(int(q.get("id", "0")))
            if a is None:
                return self.err(404, "没有这张专辑")
            return self.send(200, {"album": album_dict(a), "id_evidence": "按专辑名在资料库里找到 3 个", "ours": ours(a), "candidates": candidates(a[0]) if a[5] == "candidates" else []})
        if p == "/v1/cover":
            a = find(int(q.get("album", "0") or 0))
            if a is None:
                return self.err(404, "没有封面")
            n = max(64, min(int(q.get("size", "600")), 600))
            return self.send(200, png(n, n, a[6]), "image/png")
        if p == "/v1/search":
            s = q.get("q", "").lower()
            al = [album_dict(a) for a in ALBUMS if s in a[1].lower() or s in a[2].lower()]
            ar = [{"name": a[2], "albums": 1, "tracks": a[4]} for a in ALBUMS if s in a[2].lower()]
            tr = [track(a, k) for a in ALBUMS for k in range(a[4]) if s in TITLES[k % len(TITLES)].lower()][:50]
            return self.send(200, {"q": q.get("q", ""), "artists": ar, "albums": al, "tracks": tr})
        if p == "/v1/artists":
            return self.send(200, {"rev": rev, "artists": sorted([{"name": a[2], "albums": 1, "tracks": a[4], "cover_album": a[0]} for a in ALBUMS], key=lambda x: x["name"])})
        if p == "/v1/artist":
            al = [album_dict(a) for a in ALBUMS if a[2] == q.get("name")]
            return self.send(200, {"name": q.get("name"), "albums": al}) if al else self.err(404, "没有这位艺人")
        if p == "/v1/cards":
            return self.send(200, cards())
        if p == "/v1/queue":
            a = find(state["album"])
            return self.send(200, {"index": state["index"], "single": False, "count": a[4], "tracks": [track(a, k) for k in range(a[4])], "next_pick": track(a, state["index"] + 1), "queued_album": None})
        if p == "/v1/history":
            return self.send(200, [{"played_at": int(time.time()) - 600 * k, "track": track(ALBUMS[k % 12], k % 6)} for k in range(20)])
        if p == "/v1/identify":
            return self.send(200, {"rev": rev, "matched": 10, "candidates": 1, "unknown": 1, "none": 0, "can_identify": True, "catalog": "资料库 312,004 张", "online": "MusicBrainz 正常", "busy": False, "status": ""})
        if p == "/v1/identify/search":
            return self.send(200, {"done": True, "elapsed_s": 3.0, "album": album_dict(find(5)), "ours": ours(find(5)), "candidates": candidates(5)})
        return self.err(404, "没有这个地址")

    def do_POST(self):
        global rev
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n) if n else b""
        if self.headers.get("X-MIAOW-Remote") is None:
            return self.err(403, "控制请求要带 X-MIAOW-Remote 头")
        p = urlparse(self.path).path.rstrip("/")
        q = {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()}
        if p == "/v1/album/cover":
            rev += 1
            return self.send(200, {"ok": True, "album": album_detail(int(q.get("id", "0")))})
        try:
            b = json.loads(body.decode("utf-8")) if body else {}
        except ValueError:
            return self.err(400, "请求内容不是 JSON")
        result = None
        if p == "/v1/play":
            result = "queued_next" if state["playing"] else "playing"
        elif p == "/v1/toggle":
            state["playing"] = not state["playing"]
            state["started"] = time.time() - 95
        elif p == "/v1/repeat":
            state["repeat"] = b.get("mode", "off")
        elif p == "/v1/queue_album":
            state["queued"] = b.get("album") if b.get("on", True) else None
        elif p in ("/v1/album/edit", "/v1/album/cover_reset", "/v1/identify/apply", "/v1/identify/reject", "/v1/identify/revert"):
            rev += 1
            return self.send(200, {"ok": True, "album": album_detail(int(b.get("id", 0)))})
        elif p == "/v1/identify/search":
            return self.send(200, {"ok": True, "job": 1})
        elif p in ("/v1/identify/run", "/v1/library/scan"):
            return self.send(200, {"ok": True})
        d = {"ok": True, "state": player_state()}
        if result:
            d["result"] = result
        return self.send(200, d)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    print("假播放器：http://127.0.0.1:%d/" % port, flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
