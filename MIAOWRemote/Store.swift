// 整个 App 共用的状态：连的是哪台播放器、正在播放什么、专辑墙。
// 前台时每秒问一次 /v1/state；状态里的 rev 变了（扫描、识别、改资料、换封面）就重拉专辑墙。
import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var server: String = UserDefaults.standard.string(forKey: "server") ?? ""
    @Published private(set) var api: API?
    @Published var info: ServerInfo?
    @Published var state: PlayerState?
    @Published var stateTime = Date()
    @Published var linkError: String?         // 连不上时播放栏上显示
    @Published var albums: [AlbumBrief] = []
    @Published var albumsRev = -1
    @Published var albumsError: String?
    @Published var sort: String = UserDefaults.standard.string(forKey: "sort") ?? "title" {
        didSet { UserDefaults.standard.set(sort, forKey: "sort"); Task { await reloadAlbums() } }
    }
    @Published var toast: String?

    private var poll: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        if let u = API.normalize(server) { api = API(base: u) }
    }

    var connected: Bool { api != nil && info != nil }

    /// 连接页：先问 /v1/info，通了才记下来
    func connect(_ text: String) async throws {
        guard let u = API.normalize(text) else { throw APIError(message: "地址不对，例如 192.168.1.124:47880") }
        let a = API(base: u)
        let i: ServerInfo = try await a.get("/v1/info", timeout: 6)
        api = a
        info = i
        server = u.absoluteString
        UserDefaults.standard.set(server, forKey: "server")
        albums = []
        albumsRev = -1
        linkError = nil
        start()
    }

    func forget() {
        stop()
        api = nil
        info = nil
        state = nil
        albums = []
        albumsRev = -1
        server = ""
        UserDefaults.standard.removeObject(forKey: "server")
    }

    func start() {
        guard api != nil, poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshState()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
    }

    func refreshState() async {
        guard let api = api else { return }
        do {
            if info == nil { info = try await api.get("/v1/info", timeout: 5) }
            let s: PlayerState = try await api.get("/v1/state", timeout: 5)
            apply(s)
            linkError = nil
        } catch {
            linkError = error.localizedDescription
        }
    }

    private func apply(_ s: PlayerState) {
        state = s
        stateTime = Date()
        if let r = s.rev, r != albumsRev { Task { await reloadAlbums() } }
    }

    /// 播放位置：两次轮询之间按时间往前走，进度条不会一秒跳一下
    func position(at now: Date) -> Double {
        guard let s = state, let p = s.positionS else { return 0 }
        guard s.playing, s.preparing != true else { return p }
        return min(p + now.timeIntervalSince(stateTime), s.durationS ?? .greatestFiniteMagnitude)
    }

    private var loadingAlbums = false
    func reloadAlbums() async {
        guard let api = api, !loadingAlbums else { return }
        loadingAlbums = true
        defer { loadingAlbums = false }
        do {
            let page: AlbumsPage = try await api.get("/v1/albums", ["sort": sort], timeout: 20)
            albums = page.albums
            albumsRev = page.rev ?? 0
            albumsError = nil
        } catch {
            albumsError = error.localizedDescription
        }
    }

    func album(_ id: Int64) -> AlbumBrief? { albums.first { $0.id == id } }

    func coverURL(album: Int64, size: Int, rev: String?) -> URL? {
        api?.coverURL(album: album, size: size, rev: rev ?? self.album(album)?.cover)
    }

    func say(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // ---------- 控制 ----------
    func control(_ path: String, _ body: [String: Any] = [:]) async {
        guard let api = api else { return }
        do {
            let r: ControlResult = try await api.post(path, body)
            if let s = r.state { apply(s) }
            if r.result == "queued_next" { say("正放着别的歌：已排成下一首，放完接上") }
        } catch {
            say(error.localizedDescription)
        }
    }

    func playAlbum(_ id: Int64, from index: Int = 0) async { await control("/v1/play", ["album": id, "index": index]) }
    func playTrack(_ id: Int64, single: Bool = false) async { await control("/v1/play", single ? ["track": id, "single": true] : ["track": id]) }
    func toggle() async { await control("/v1/toggle") }
    func next() async { await control("/v1/next") }
    func prev() async { await control("/v1/prev") }
    func stopPlay() async { await control("/v1/stop") }
    func seek(_ s: Double) async { await control("/v1/seek", ["position_s": s]) }
    func setRepeat(_ mode: String) async { await control("/v1/repeat", ["mode": mode]) }
    func queueAlbum(_ id: Int64, on: Bool) async {
        await control("/v1/queue_album", ["album": id, "on": on])
        say(on ? "现在这首放完，接着放这张" : "取消了接着放")
    }

    /// 进专辑页时告诉播放器：没在放歌的话，它会先把头两首写进卡
    func openedAlbum(_ id: Int64) async {
        guard let api = api else { return }
        let _: ControlResult? = try? await api.post("/v1/open_album", ["album": id])
    }
}

/// 轻提示（排成下一首、出错）
struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
