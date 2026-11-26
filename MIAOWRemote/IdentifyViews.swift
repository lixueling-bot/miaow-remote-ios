// 识别：逐轨对照候选（左边是你的文件，右边是资料库的），采用 / 都不是 / 恢复原标签 / 手动搜 / 重新识别
import SwiftUI

struct CandidatesView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let albumId: Int64
    var changed: (AlbumDetail) -> Void
    @State private var page: CandidatesPage?
    @State private var error: String?
    @State private var query = ""
    @State private var searching = false
    @State private var searchNote: String?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("手动搜：专辑名或艺人名", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if searching { ProgressView() }
                    else { Button("搜") { Task { await search() } }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
                if let n = searchNote { Text(n).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("先在电脑上的资料库里找，找不到再联网。一次几秒到一分钟。")
            }

            if let p = page {
                if let e = p.idEvidence, !e.isEmpty { Section("识别依据") { Text(e).font(.footnote) } }
                if p.candidates.isEmpty {
                    Section { Text("没有候选。试试上面手动搜，或者重新识别。").foregroundStyle(.secondary) }
                }
                ForEach(p.candidates) { c in
                    Section { CandidateCard(candidate: c, ours: p.ours) { Task { await apply(c) } } }
                }
            } else if let e = error {
                NoteView(icon: "exclamationmark.triangle", text: e) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            Section {
                Button { Task { await change("/v1/identify/reject", "记下了：候选都不是") } } label: { Label("候选都不是", systemImage: "xmark.circle") }
                Button { Task { await change("/v1/identify/revert", "恢复了原标签") } } label: { Label("恢复原标签", systemImage: "arrow.uturn.backward") }
                Button {
                    Task {
                        guard let api = store.api else { return }
                        do { let _: OkResult = try await api.post("/v1/identify/run", ["id": albumId]); store.say("正在重新识别"); dismiss() }
                        catch { store.say(error.localizedDescription) }
                    }
                } label: { Label("重新识别", systemImage: "arrow.clockwise") }
            }
            .disabled(busy)
        }
        .navigationTitle(page?.album?.name ?? "识别")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task {
            await load()
            if query.isEmpty, let a = page?.album { query = a.title ?? "" }
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        do { page = try await api.get("/v1/album/candidates", ["id": String(albumId)], timeout: 20); error = nil }
        catch { self.error = error.localizedDescription }
    }

    /// 手动搜是后台任务：先拿到 job 号，每 2.5 秒问一次搜完没有
    private func search() async {
        guard let api = store.api else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            let j: JobResult = try await api.post("/v1/identify/search", ["id": albumId, "q": q])
            for _ in 0..<80 {
                try await Task.sleep(nanoseconds: 2_500_000_000)
                let r: SearchJobPage = try await api.get("/v1/identify/search", ["job": String(j.job)])
                if r.done {
                    let found = r.candidates ?? []
                    searchNote = found.isEmpty ? "没搜到“\(q)”" : "搜到 \(found.count) 个（用了 \(Int(r.elapsedS ?? 0)) 秒）"
                    page = CandidatesPage(album: r.album ?? page?.album, idEvidence: page?.idEvidence, ours: r.ours ?? page?.ours ?? [], candidates: found)
                    return
                }
                searchNote = "正在搜…（\(Int(r.elapsedS ?? 0)) 秒）"
            }
            searchNote = "搜太久了，稍后再试"
        } catch is CancellationError {
        } catch { searchNote = error.localizedDescription }
    }

    private func apply(_ c: Candidate) async {
        guard let api = store.api else { return }
        busy = true
        defer { busy = false }
        do {
            let r: AlbumResult = try await api.post("/v1/identify/apply", ["id": albumId, "token": c.token], timeout: 40)
            if let a = r.album { changed(a) }
            store.say("采用了《\(c.title ?? "")》")
            dismiss()
        } catch { store.say(error.localizedDescription) }
    }

    private func change(_ path: String, _ done: String) async {
        guard let api = store.api else { return }
        busy = true
        defer { busy = false }
        do {
            let r: AlbumResult = try await api.post(path, ["id": albumId])
            if let a = r.album { changed(a) }
            store.say(done)
            await load()
        } catch { store.say(error.localizedDescription) }
    }
}

/// 一个候选：标题、得分，展开看逐轨时长对照（差 3 秒以上标出来）
struct CandidateCard: View {
    let candidate: Candidate
    let ours: [OurTrack]
    var apply: () -> Void
    @State private var open = false

    var body: some View {
        let c = candidate
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let r = c.release, c.hasCover == true { ReleaseCoverView(release: r).frame(width: 64, height: 64) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title ?? "").font(.headline)
                    Text([c.artist, c.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let s = c.score { Text("得分 \(s)").font(.caption.bold()).foregroundStyle(s >= 80 ? Theme.ready : s >= 50 ? Theme.accent : .secondary) }
                        Text("\(c.tracks?.count ?? 0) 首 / 你的 \(ours.count) 首").font(.caption).foregroundStyle(.secondary)
                    }
                    if let r = c.reason, !r.isEmpty { Text(r).font(.caption).foregroundStyle(.secondary) }
                }
            }
            HStack {
                Button(open ? "收起对照" : "逐轨对照") { withAnimation { open.toggle() } }.buttonStyle(.bordered)
                Spacer()
                Button("采用", action: apply).buttonStyle(.borderedProminent)
            }
            if open { compare }
        }
        .padding(.vertical, 4)
    }

    private var compare: some View {
        let theirs = candidate.tracks ?? []
        let n = max(ours.count, theirs.count)
        return VStack(spacing: 6) {
            HStack {
                Text("你的文件").frame(maxWidth: .infinity, alignment: .leading)
                Text("资料库").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(0..<n, id: \.self) { i in
                let o = i < ours.count ? ours[i] : nil
                let t = i < theirs.count ? theirs[i] : nil
                let diff = (o?.lengthMs).flatMap { a in (t?.lengthMs).map { b in abs(a - b) } }
                HStack(alignment: .top) {
                    side(i, o?.title, o?.lengthMs, warn: false)
                    side(i, t?.title, t?.lengthMs, warn: (diff ?? 0) > 3000)
                }
                .font(.caption)
            }
        }
    }

    private func side(_ i: Int, _ title: String?, _ ms: Int64?, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.map { "\(i + 1). \($0)" } ?? "—").lineLimit(2)
            Text(ms.map { timeText(Double($0) / 1000) } ?? "").monospacedDigit().foregroundStyle(warn ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 识别中心：统计、待确认 / 没认出来的专辑、扫描新文件
struct IdentifyCenterView: View {
    @EnvironmentObject var store: Store
    @State private var sum: IdentifySummary?
    @State private var pick: Int64?

    private var waiting: [AlbumBrief] { store.albums.filter { $0.idState == "candidates" } }
    private var unknown: [AlbumBrief] { store.albums.filter { $0.idState == "unknown" || $0.idState == "none" || $0.idState == nil } }

    var body: some View {
        List {
            if let s = sum {
                Section {
                    HStack {
                        stat("已匹配", s.matched)
                        stat("待确认", s.candidates)
                        stat("没认出", s.unknown)
                        stat("未识别", s.none)
                    }
                    if let c = s.catalog, !c.isEmpty { Text("资料库：" + c).font(.caption).foregroundStyle(.secondary) }
                    if let o = s.online, !o.isEmpty { Text("联网：" + o).font(.caption).foregroundStyle(.secondary) }
                    if s.busy == true, let st = s.status { Label(st, systemImage: "hourglass").font(.caption) }
                }
            }
            if !waiting.isEmpty {
                Section("待确认") { ForEach(waiting) { a in row(a) } }
            }
            if !unknown.isEmpty {
                Section("没认出来 / 还没识别") { ForEach(unknown) { a in row(a) } }
            }
            Section {
                Button {
                    Task {
                        guard let api = store.api else { return }
                        do { let _: OkResult = try await api.post("/v1/library/scan"); store.say("开始扫描曲库里的新文件") }
                        catch { store.say(error.localizedDescription) }
                    }
                } label: { Label("扫描新文件并识别", systemImage: "arrow.triangle.2.circlepath") }
            }
        }
        .navigationTitle("识别中心")
        .sheet(item: Binding(get: { pick.map { AlbumRoute(id: $0) } }, set: { pick = $0?.id })) { r in
            NavigationStack { CandidatesView(albumId: r.id) { _ in } }.environmentObject(store)
        }
        .task {
            while !Task.isCancelled {
                if let api = store.api { sum = try? await api.get("/v1/identify") }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .refreshable { await store.reloadAlbums() }
    }

    private func stat(_ name: String, _ v: Int?) -> some View {
        VStack(spacing: 2) {
            Text("\(v ?? 0)").font(.title3.monospacedDigit().weight(.semibold))
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ a: AlbumBrief) -> some View {
        Button { pick = a.id } label: {
            HStack(spacing: 12) {
                CoverView(album: a.id, rev: a.cover, size: 120, corner: 3).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).lineLimit(1)
                    Text(a.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

extension AlbumRoute: Identifiable {}
