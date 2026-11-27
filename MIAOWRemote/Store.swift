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

    /// 这台播放器的其他地址（/v1/info 报的全部地址 + 电脑名.local），连不上时挨个试
    private var alternates: [String] = UserDefaults.standard.stringArray(forKey: "alternates") ?? []
    private var serverHost: String? = UserDefaults.standard.string(forKey: "serverHost")
    private var fails = 0
    private var relocating = false
    private var lastRelocate = Date.distantPast
    private var lostNote: String?           // 找过一次没找到时，播放栏上一直显示这句

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
        remember(i, base: u)
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
        alternates = []
        serverHost = nil
        for k in ["server", "alternates", "serverHost"] { UserDefaults.standard.removeObject(forKey: k) }
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
            if info == nil {
                let i: ServerInfo = try await api.get("/v1/info", timeout: 5)
                info = i
                remember(i, base: api.base)
            }
            let s: PlayerState = try await api.get("/v1/state", timeout: 5)
            apply(s)
            linkError = nil
            lostNote = nil
            fails = 0
        } catch {
            if !relocating { linkError = lostNote ?? error.localizedDescription }
            fails += 1
            // 连着 3 次（约 3 秒）连不上：多半是电脑换了 IP，去找它。找不到的话 30 秒后再找
            if fails >= 3, !relocating, Date().timeIntervalSince(lastRelocate) > 30 {
                Task { await relocate() }
            }
        }
    }

    /// 记下这台播放器的全部地址和电脑名
    private func remember(_ i: ServerInfo, base: URL) {
        let port = base.port ?? API.defaultPort
        var list = (i.urls ?? []).compactMap { API.normalize($0)?.absoluteString }
        if let h = i.host, !h.isEmpty, let u = API.normalize("\(h.lowercased()).local:\(port)") { list.append(u.absoluteString) }
        list.removeAll { $0 == base.absoluteString }
        var seen = Set<String>()
        alternates = list.filter { seen.insert($0).inserted }
        UserDefaults.standard.set(alternates, forKey: "alternates")
        if let h = i.host, !h.isEmpty {
            serverHost = h
            UserDefaults.standard.set(h, forKey: "serverHost")
        }
    }

    /// 原来的地址连不上：先试记下的其他地址，再扫一遍 Wi-Fi 网段，找到原来那台（电脑名相同）就换过去
    func relocate() async {
        guard let cur = api?.base, !relocating else { return }
        relocating = true
        lastRelocate = Date()
        defer { relocating = false }
        linkError = "连不上 \(cur.host ?? "播放器")，正在 Wi-Fi 里找它…"
        // 原地址刚好又通了就不换
        if await Discovery.probe(cur) != nil { fails = 0; linkError = nil; return }
        for s in alternates {
            guard let u = URL(string: s), u != cur, let f = await Discovery.probe(u) else { continue }
            if serverHost == nil || f.host == serverHost { await switchTo(f); return }
        }
        let found = await Discovery.scan(port: cur.port ?? API.defaultPort)
        let same = found.first { serverHost != nil && $0.host == serverHost }
        if let f = same ?? (found.count == 1 && serverHost == nil ? found.first : nil) {
            await switchTo(f)
        } else {
            lostNote = found.isEmpty
                ? "Wi-Fi 里没找到播放器：确认电脑开着、遥控已打开、手机和电脑在同一个 Wi-Fi"
                : "原来那台播放器没找到；更多 → 换一台播放器，可以从找到的里面选"
            linkError = lostNote
        }
    }

    private func switchTo(_ f: FoundPlayer) async {
        let a = API(base: f.url)
        guard let i: ServerInfo = try? await a.get("/v1/info", timeout: 5) else { return }
        api = a
        info = i
        server = f.url.absoluteString
        UserDefaults.standard.set(server, forKey: "server")
        remember(i, base: f.url)
        fails = 0
        linkError = nil
        lostNote = nil
        say("播放器换了地址，已连到 \(f.url.host ?? "")")
        await refreshState()
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
