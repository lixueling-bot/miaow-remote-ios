// 播放栏和“正在播放”
// 卡带库模式：点歌要先写卡（preparing），只能从头放，不能拖；“下一首”有预载的就切到预载的那首
import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var store: Store
    var open: () -> Void

    var body: some View {
        let s = store.state
        let t = s?.track ?? s?.pending
        VStack(spacing: 0) {
            if let e = store.linkError {
                Text(e).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    .frame(maxWidth: .infinity).padding(.vertical, 4).background(Color.black.opacity(0.6))
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let d = s?.durationS ?? 0
                ProgressView(value: d > 0 ? min(store.position(at: ctx.date) / d, 1) : 0)
                    .progressViewStyle(.linear).tint(Theme.accent).scaleEffect(x: 1, y: 0.6)
            }
            HStack(spacing: 12) {
                CoverView(album: t?.albumId, rev: t?.cover, size: 120, corner: 4).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t?.name ?? "没有在放").font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(subtitle(s)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if s?.preparing == true { ProgressView().padding(.trailing, 4) }
                Button { Task { await store.toggle() } } label: {
                    Image(systemName: s?.playing == true ? "pause.fill" : "play.fill").font(.title2).frame(width: 40, height: 40)
                }
                Button { Task { await store.next() } } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 40)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
        .background(.bar)
    }

    private func subtitle(_ s: PlayerState?) -> String {
        guard let s = s else { return store.linkError == nil ? "正在连接…" : "连不上" }
        if s.preparing == true, let p = s.pending { return "正在写卡：\(p.name)" }
        if let n = s.nextText, !n.isEmpty { return n }
        return [s.track?.artist, s.track?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var dragging: Double?
    @State private var showQueue = false

    var body: some View {
        let s = store.state
        let t = s?.track
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height && geo.size.width > 600
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .center, spacing: 36) {
                                CoverView(album: t?.albumId, rev: t?.cover, size: 1000, corner: 10).frame(maxWidth: max(min(geo.size.height - 80, 520), 200))
                                controls(s).frame(maxWidth: 460)
                            }
                        } else {
                            VStack(spacing: 24) {
                                CoverView(album: t?.albumId, rev: t?.cover, size: 1000, corner: 10).frame(maxWidth: 520)
                                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                                controls(s).frame(maxWidth: 520)
                            }
                        }
                    }
                    .padding(24)
                    .frame(minHeight: geo.size.height)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .principal) { MiaowLogo(width: 54).foregroundStyle(.secondary) }
                ToolbarItem(placement: .primaryAction) {
                    Button { showQueue = true } label: { Image(systemName: "list.bullet") }
                }
            }
            .sheet(isPresented: $showQueue) { NavigationStack { QueueView() }.environmentObject(store) }
        }
    }

    @ViewBuilder private func controls(_ s: PlayerState?) -> some View {
        let t = s?.track
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(t?.name ?? (s?.pending != nil ? "正在写卡…" : "没有在放")).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(t?.artist ?? "").font(.body).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
                Text(t?.album ?? "").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let f = t?.formatText, !f.isEmpty { Text(f).font(.caption.monospaced()).foregroundStyle(.secondary).padding(.top, 2) }
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let d = s?.durationS ?? 0
                let pos = dragging ?? store.position(at: ctx.date)
                VStack(spacing: 4) {
                    if s?.canSeek == true && d > 0 {
                        Slider(value: Binding(get: { pos }, set: { dragging = $0 }), in: 0...d, onEditingChanged: { editing in
                            if !editing, let v = dragging { Task { await store.seek(v); dragging = nil } }
                        })
                    } else {
                        ProgressView(value: d > 0 ? min(pos / d, 1) : 0).tint(Theme.accent)
                    }
                    HStack {
                        Text(timeText(pos)); Spacer(); Text(timeText(d))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 44) {
                Button { Task { await store.prev() } } label: { Image(systemName: "backward.fill").font(.title) }
                Button { Task { await store.toggle() } } label: {
                    Image(systemName: s?.playing == true ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                }
                Button { Task { await store.next() } } label: { Image(systemName: "forward.fill").font(.title) }
            }
            .foregroundStyle(.primary)

            HStack {
                Menu {
                    Picker("循环", selection: Binding(get: { s?.repeat ?? "off" }, set: { m in Task { await store.setRepeat(m) } })) {
                        Text("不循环").tag("off")
                        Text("整张循环").tag("album")
                        Text("单曲循环").tag("track")
                    }
                } label: {
                    Label(repeatText(s?.repeat), systemImage: s?.repeat == "track" ? "repeat.1" : "repeat")
                        .foregroundStyle(s?.repeat == nil || s?.repeat == "off" ? Color.secondary : Theme.accent)
                }
                Spacer()
                if s?.output == "cart" {
                    Label("卡带库", systemImage: "sdcard").foregroundStyle(.secondary)
                } else if s?.output == "cart_offline" {
                    Label("卡带库没连上", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .font(.footnote)

            VStack(alignment: .leading, spacing: 10) {
                if s?.preparing == true, let p = s?.pending {
                    row("square.and.arrow.down", "正在写卡", p.name)
                }
                if let n = s?.nextPick {
                    row("text.line.first.and.arrowtriangle.forward", "下一首", n.name + (n.artist.map { " · " + $0 } ?? ""))
                } else if let n = s?.nextText, !n.isEmpty {
                    row("text.line.first.and.arrowtriangle.forward", "下一首", n)
                }
                if let q = s?.queuedAlbum {
                    row("rectangle.stack", "接着放这张", q.name)
                }
                if let st = s?.status, !st.isEmpty {
                    row("info.circle", "播放器", st)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ icon: String, _ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(text).font(.subheadline)
            }
        }
    }

    private func repeatText(_ m: String?) -> String {
        switch m ?? "" { case "album": return "整张循环"; case "track": return "单曲循环"; default: return "不循环" }
    }
}

struct QueueView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var page: QueuePage?
    @State private var error: String?

    var body: some View {
        List {
            if let p = page {
                if let n = p.nextPick {
                    Section("预载的下一首") { TrackRow(track: n, showAlbum: true) }
                }
                Section(p.single == true ? "只播这一首" : "播放队列（\(p.count ?? p.tracks.count) 首）") {
                    ForEach(Array(p.tracks.enumerated()), id: \.offset) { i, t in
                        Button { Task { await store.playTrack(t.id) } } label: {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill").opacity(i == p.index ? 1 : 0).foregroundStyle(Theme.accent).frame(width: 22)
                                TrackRow(track: t, showAlbum: true)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if let q = p.queuedAlbum {
                    Section("放完接着放") { Text(q.name) }
                }
            } else if let e = error {
                NoteView(icon: "wifi.exclamationmark", text: e) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("队列")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        do { page = try await api.get("/v1/queue"); error = nil } catch { self.error = error.localizedDescription }
    }
}

/// 一行歌：标题、艺人 / 专辑、时长
struct TrackRow: View {
    let track: Track
    var showAlbum = false
    var body: some View {
        HStack(spacing: 12) {
            if showAlbum { CoverView(album: track.albumId, rev: track.cover, size: 120, corner: 3).frame(width: 40, height: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).lineLimit(1)
                Text([track.artist, showAlbum ? track.album : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(timeText(track.durationS)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
