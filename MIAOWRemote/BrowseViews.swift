// 艺人、搜索、卡带库卡位、更多（识别中心、最近播放、换播放器）
import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var store: Store
    @State private var artists: [ArtistItem] = []
    @State private var error: String?
    @State private var filter = ""

    var body: some View {
        List {
            if artists.isEmpty, let e = error {
                NoteView(icon: "wifi.exclamationmark", text: e) { Task { await load() } }
            }
            ForEach(artists.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { a in
                NavigationLink(value: ArtistRoute(name: a.name)) {
                    HStack(spacing: 12) {
                        CoverView(album: a.coverAlbum, rev: a.coverAlbum.flatMap { store.album($0)?.cover }, size: 120, corner: 22).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).lineLimit(1)
                            Text("\(a.albums ?? 0) 张专辑 · \(a.tracks ?? 0) 首").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("艺人")
        .searchable(text: $filter, prompt: "找艺人")
        .task(id: store.albumsRev) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        do { let p: ArtistsPage = try await api.get("/v1/artists"); artists = p.artists; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject var store: Store
    let name: String
    @State private var albums: [AlbumBrief] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let e = error, albums.isEmpty { NoteView(icon: "exclamationmark.triangle", text: e) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)], spacing: 20) {
                ForEach(albums) { a in
                    NavigationLink(value: AlbumRoute(id: a.id)) { AlbumCell(album: a) }.buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(name)
        .task {
            guard let api = store.api else { return }
            do { let p: ArtistAlbums = try await api.get("/v1/artist", ["name": name]); albums = p.albums }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var store: Store
    @State private var q = ""
    @State private var page: SearchPage?
    @State private var error: String?

    var body: some View {
        List {
            if let p = page {
                if p.artists.isEmpty && p.albums.isEmpty && p.tracks.isEmpty {
                    Text("没找到“\(p.q ?? q)”").foregroundStyle(.secondary)
                }
                if !p.artists.isEmpty {
                    Section("艺人") {
                        ForEach(p.artists) { a in
                            NavigationLink(value: ArtistRoute(name: a.name)) {
                                Text(a.name) + Text("  \(a.albums ?? 0) 张").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if !p.albums.isEmpty {
                    Section("专辑") {
                        ForEach(p.albums) { a in
                            NavigationLink(value: AlbumRoute(id: a.id)) {
                                HStack(spacing: 12) {
                                    CoverView(album: a.id, rev: a.cover, size: 120, corner: 3).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name).lineLimit(1)
                                        Text([a.artist, a.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !p.tracks.isEmpty {
                    Section("曲目") {
                        ForEach(p.tracks) { t in
                            Button { Task { await store.playTrack(t.id) } } label: { TrackRow(track: t, showAlbum: true) }
                                .foregroundStyle(.primary)
                                .contextMenu {
                                    Button { Task { await store.playTrack(t.id, single: true) } } label: { Label("只播这一首", systemImage: "1.circle") }
                                }
                        }
                    }
                }
            } else if let e = error {
                NoteView(icon: "exclamationmark.triangle", text: e)
            } else {
                Text("搜艺人、专辑、曲目。中文名可以打拼音首字母，比如 zjl。").font(.callout).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "艺人、专辑、曲目")
        .task(id: q) {
            let s = q.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { page = nil; error = nil; return }
            try? await Task.sleep(nanoseconds: 300_000_000)    // 打字停一下再搜
            if Task.isCancelled { return }
            guard let api = store.api else { return }
            do { page = try await api.get("/v1/search", ["q": s]); error = nil }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

/// 卡带库 6 个卡位：谁在播放机上、正在写 / 擦、卡里是哪首
struct CardsView: View {
    @EnvironmentObject var store: Store
    @State private var page: CardsPage?
    @State private var error: String?

    var body: some View {
        List {
            if let p = page {
                if !p.connected {
                    NoteView(icon: "sdcard", text: p.wanted == true ? "卡带库没连上（播放器在等它）" : "这台播放器现在没用卡带库")
                } else {
                    Section {
                        if let f = p.firmware { LabeledContent("固件", value: f) }
                        if let w = p.writing, !w.isEmpty { LabeledContent("写卡", value: w) }
                    }
                    Section("卡位") {
                        ForEach(p.slots) { s in SlotRow(slot: s) }
                    }
                    if !p.ready.isEmpty {
                        Section("卡里有的歌（点了马上播）") {
                            ForEach(p.ready) { t in
                                Button { Task { await store.playTrack(t.id) } } label: { TrackRow(track: t, showAlbum: true) }.foregroundStyle(.primary)
                            }
                        }
                    }
                }
            } else if let e = error {
                NoteView(icon: "wifi.exclamationmark", text: e)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("卡带库")
        .task {
            while !Task.isCancelled {
                if let api = store.api {
                    do { page = try await api.get("/v1/cards"); error = nil } catch { self.error = error.localizedDescription }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

struct SlotRow: View {
    let slot: Slot
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(slot.n)").font(.title3.monospacedDigit().weight(.semibold))
                .frame(width: 30, height: 30)
                .background(Circle().strokeBorder(slot.current == true ? Theme.accent : Color(white: 0.3), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.track?.name ?? slot.title ?? "卡位 \(slot.n)").lineLimit(2).foregroundStyle(slot.track == nil && slot.title == nil ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(stateText).foregroundStyle(stateColor)
                    if let p = slot.routedTo, p == "A" || p == "B" { Text("接 \(p) 口") }
                    if slot.current == true { Text("正在放").foregroundStyle(Theme.accent) }
                    if slot.protected == true { Image(systemName: "lock.fill") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let w = slot.writingPct { ProgressView(value: Double(w), total: 100).tint(Theme.accent) }
            }
        }
        .padding(.vertical, 2)
    }

    private var stateText: String {
        if let w = slot.writingPct { return "写入 \(w)%" }
        if let e = slot.erasingS { return "擦除中 \(Int(e)) 秒" }
        let s = slot.state ?? ""
        switch s.uppercased() {
        case "READY": return "已写好"
        case "BLANK": return "空卡"
        case "DIRTY": return "待擦"
        case "ERASING": return "擦除中"
        case "WRITING": return "写入中"
        case "EMPTY": return "没插卡"
        case "UNKNOWN": return "状态不明"
        case "": return "—"
        default: return s
        }
    }

    private var stateColor: Color {
        if slot.writingPct != nil || slot.erasingS != nil { return Theme.accent }
        return slot.state?.uppercased() == "READY" ? Theme.ready : .secondary
    }
}

struct MoreView: View {
    @EnvironmentObject var store: Store
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                NavigationLink { IdentifyCenterView() } label: { Label("识别中心", systemImage: "wand.and.stars") }
                NavigationLink { QueueView() } label: { Label("播放队列", systemImage: "list.number") }
                NavigationLink { HistoryView() } label: { Label("最近播放", systemImage: "clock") }
            }
            Section("播放器") {
                LabeledContent("地址", value: store.server)
                if let i = store.info {
                    if let h = i.host { LabeledContent("电脑", value: h) }
                    if let b = i.build { LabeledContent("播放器版本", value: b) }
                }
                Button("换一台播放器", role: .destructive) { confirmForget = true }
            }
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        MiaowLogo(width: 70).foregroundStyle(.secondary)
                        Text("Minimal Interference, Absolute Original Wave").font(.caption2).foregroundStyle(.secondary)
                        Text("遥控 " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("更多")
        .confirmationDialog("不连这台了？", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("换一台", role: .destructive) { store.forget() }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var items: [HistoryItem] = []
    @State private var error: String?

    var body: some View {
        List {
            if let e = error { NoteView(icon: "exclamationmark.triangle", text: e) }
            ForEach(items) { h in
                Button { Task { await store.playTrack(h.track.id) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        TrackRow(track: h.track, showAlbum: true)
                        Text(Date(timeIntervalSince1970: TimeInterval(h.playedAt)).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 52)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("最近播放")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        do { items = try await api.get("/v1/history", ["n": "100"]); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
