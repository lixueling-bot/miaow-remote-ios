// 专辑页：曲目表（每首标着在不在卡里、点了要等多久）、播放、接着放这张、改资料、换封面、识别
import SwiftUI
import PhotosUI

struct AlbumDetailView: View {
    @EnvironmentObject var store: Store
    let albumId: Int64
    @State private var album: AlbumDetail?
    @State private var error: String?
    @State private var showEdit = false
    @State private var showIdentify = UserDefaults.standard.bool(forKey: "shotIdentify")   // 截图自检用
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var showArtist = false

    var body: some View {
        Group {
            if let a = album {
                content(a)
            } else if let e = error {
                NoteView(icon: "exclamationmark.triangle", text: e) { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(album?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { if let a = album { menu(a) } } }
        .sheet(isPresented: $showEdit) {
            if let a = album { EditAlbumView(album: a) { album = $0 }.environmentObject(store) }
        }
        .sheet(isPresented: $showIdentify) {
            if let a = album { NavigationStack { CandidatesView(albumId: a.id) { album = $0 } }.environmentObject(store) }
        }
        .navigationDestination(isPresented: $showArtist) { ArtistDetailView(name: album?.artist ?? "") }
        .onChange(of: photo) { item in
            guard let item = item else { return }
            Task { await upload(item) }
        }
        .task {
            await store.openedAlbum(albumId)
            // 写卡进度、“在卡里”跟着变：在这页时每 3 秒刷新一次
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func content(_ a: AlbumDetail) -> some View {
        List {
            Section {
                header(a).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(a.tracks.enumerated()), id: \.element.id) { i, t in
                    Button { Task { await store.playTrack(t.id) } } label: {
                        TrackLine(index: i, track: t, playing: a.playingTrack == t.id, multiDisc: Set(a.tracks.compactMap { $0.discNo }).count > 1)
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button { Task { await store.playTrack(t.id) } } label: { Label("从这首起放", systemImage: "play") }
                        Button { Task { await store.playTrack(t.id, single: true) } } label: { Label("只播这一首", systemImage: "1.circle") }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(a.tracks.count) 首 · \(timeText(a.durationS))" + (a.quality.map { " · " + $0 } ?? ""))
                    if let n = a.notes, !n.isEmpty { Text(n) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private func header(_ a: AlbumDetail) -> some View {
        let playingOther = store.state?.track != nil && store.state?.track?.albumId != a.id
        let first = a.tracks.first?.load
        return VStack(spacing: 14) {
            ZStack {
                CoverView(album: a.id, rev: a.cover, size: 1000, corner: 8).frame(maxWidth: 360)
                if uploading { ProgressView().scaleEffect(1.4).padding(30).background(.ultraThinMaterial, in: Circle()) }
            }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            VStack(spacing: 4) {
                Text(a.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if let ar = a.artist, !ar.isEmpty {
                    Button { showArtist = true } label: { Text(ar).foregroundStyle(Theme.accent) }.buttonStyle(.borderless)
                }
                Text([a.year, a.label, a.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let s = a.idState, s != "matched" {
                    Button { showIdentify = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                            Text(s == "candidates" ? "有 \(a.candidates ?? 0) 个识别候选待确认" : s == "unknown" ? "没认出来，手动找" : "还没识别")
                        }
                        .font(.caption)
                    }
                    .padding(.top, 2)
                }
            }
            HStack(spacing: 12) {
                Button { Task { await store.playAlbum(a.id) } } label: {
                    HStack(spacing: 6) { Image(systemName: "play.fill"); Text("播放") }.frame(minWidth: 110).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                if playingOther {
                    Button { Task { await store.queueAlbum(a.id, on: a.queued != true); await load() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.queued == true ? "checkmark" : "text.append")
                            Text(a.queued == true ? "已排好" : "接着放这张")
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let f = first { Text(waitText(f)).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func waitText(_ l: LoadInfo) -> String {
        switch l.state ?? "" {
        case "ready": return "第一首已经在卡里，点了马上放"
        case "writing": return "第一首正在写卡 \(l.pct ?? 0)%"
        default:
            guard let w = l.waitS else { return "" }
            return "现在点，第一首大约 \(Int(w)) 秒后出声" + (l.needErase == true ? "（含等擦卡）" : "")
        }
    }

    private func menu(_ a: AlbumDetail) -> some View {
        Menu {
            Button { showEdit = true } label: { Label("编辑资料", systemImage: "pencil") }
            PhotosPicker(selection: $photo, matching: .images) { Label("换封面（从相册选）", systemImage: "photo") }
            if a.coverSource == "user" {
                Button { Task { await post("/v1/album/cover_reset", "恢复了原来的封面") } } label: { Label("恢复原来的封面", systemImage: "arrow.uturn.backward") }
            }
            Divider()
            Button { showIdentify = true } label: { Label("识别：对照候选", systemImage: "list.bullet.rectangle") }
            Button { Task { await runIdentify() } } label: { Label("重新识别", systemImage: "arrow.clockwise") }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    private func load() async {
        guard let api = store.api else { return }
        do { album = try await api.get("/v1/album", ["id": String(albumId)]); error = nil }
        catch { if album == nil { self.error = error.localizedDescription } }
    }

    private func post(_ path: String, _ done: String) async {
        guard let api = store.api else { return }
        do {
            let r: AlbumResult = try await api.post(path, ["id": albumId])
            if let a = r.album { album = a }
            store.say(done)
        } catch { store.say(error.localizedDescription) }
    }

    private func runIdentify() async {
        guard let api = store.api else { return }
        do {
            let _: OkResult = try await api.post("/v1/identify/run", ["id": albumId])
            store.say("正在重新识别，好了专辑墙会自己更新")
        } catch { store.say(error.localizedDescription) }
    }

    /// 相册里的图（HEIC 也行）→ 长边缩到 2400 → JPEG 传给播放器
    private func upload(_ item: PhotosPickerItem) async {
        defer { photo = nil; uploading = false }
        uploading = true
        guard let api = store.api else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
                store.say("读不出这张图"); return
            }
            guard let jpg = img.scaledJPEG(maxSide: 2400) else { store.say("这张图转不成 JPEG"); return }
            let r = try await api.uploadCover(album: albumId, jpeg: jpg)
            if let a = r.album { album = a }
            store.say("封面换好了")
        } catch { store.say(error.localizedDescription) }
    }
}

struct TrackLine: View {
    let index: Int
    let track: Track
    let playing: Bool
    let multiDisc: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent) }
                else { Text(number).foregroundStyle(.secondary) }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name).lineLimit(2).foregroundStyle(playing ? Theme.accent : .primary)
                if let l = track.load { LoadBadge(load: l) }
            }
            Spacer(minLength: 4)
            Text(timeText(track.durationS)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var number: String {
        let n = track.trackNo ?? (index + 1)
        if multiDisc, let d = track.discNo, d > 0 { return "\(d)-\(n)" }
        return "\(n)"
    }
}

/// 在卡里 / 写入 xx% / 约 N 秒
struct LoadBadge: View {
    let load: LoadInfo
    var body: some View {
        switch load.state ?? "" {
        case "ready":
            HStack(spacing: 3) { Image(systemName: "checkmark.circle.fill"); Text("在卡里") }.font(.caption2).foregroundStyle(Theme.ready)
        case "writing":
            HStack(spacing: 6) {
                ProgressView(value: Double(load.pct ?? 0), total: 100).frame(width: 60).tint(Theme.accent)
                Text("写入 \(load.pct ?? 0)%").font(.caption2).foregroundStyle(.secondary)
            }
        default:
            if let w = load.waitS, w > 0 {
                Text("点了约 \(Int(w)) 秒出声" + (load.needErase == true ? "（等擦卡）" : "")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

extension UIImage {
    func scaledJPEG(maxSide: CGFloat, quality: CGFloat = 0.9) -> Data? {
        let longSide = max(size.width, size.height) * scale
        guard longSide > 0 else { return nil }
        let k = min(1, maxSide / longSide)
        let target = CGSize(width: (size.width * scale * k).rounded(), height: (size.height * scale * k).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let out = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return out.jpegData(compressionQuality: quality)
    }
}

/// 改专辑资料：留空 = 用自动的（文件标签 / 识别结果）。只存在播放器里，原文件不动
struct EditAlbumView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let album: AlbumDetail
    var saved: (AlbumDetail) -> Void
    @State private var title = ""
    @State private var artist = ""
    @State private var year = ""
    @State private var label = ""
    @State private var genre = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("专辑名", $title, album.edit?.title)
                    field("艺人", $artist, album.edit?.artist)
                    field("年份", $year, album.edit?.year).keyboardType(.numberPad)
                    field("出版社", $label, album.edit?.label)
                    field("流派", $genre, album.edit?.genre)
                } footer: {
                    Text("留空就用自动的（灰字）。只改播放器里的资料，音乐文件不动。")
                }
                if let e = error { Section { Text(e).foregroundStyle(.red) } }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("保存") { Task { await save() } }.bold() }
                }
            }
            .onAppear {
                title = album.edit?.title?.user ?? ""
                artist = album.edit?.artist?.user ?? ""
                year = album.edit?.year?.user ?? ""
                label = album.edit?.label?.user ?? ""
                genre = album.edit?.genre?.user ?? ""
            }
        }
    }

    private func field(_ name: String, _ text: Binding<String>, _ f: EditField?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(f?.auto ?? "", text: text)
        }
    }

    private func save() async {
        guard let api = store.api else { return }
        busy = true
        defer { busy = false }
        do {
            let r: AlbumResult = try await api.post("/v1/album/edit", ["id": album.id, "title": title, "artist": artist, "year": year, "label": label, "genre": genre])
            if let a = r.album { saved(a) }
            store.say("资料改好了")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
