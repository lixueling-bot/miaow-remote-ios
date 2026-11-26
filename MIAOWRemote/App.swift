// MIAOW 遥控：iPhone / iPad 上管家里那台 MIAOW 播放器（Windows 电脑上的 MIAOW播放器.exe）。
// 只走家里 Wi-Fi，不配对；播放器那边要在 设置 → 手机 / 平板遥控 里打开。
import SwiftUI

@main
struct MIAOWRemoteApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: phase) { p in
            // 在后台不问，回到前台马上问一次
            if p == .active { store.start(); Task { await store.refreshState() } } else { store.stop() }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.86, green: 0.66, blue: 0.40)     // 暖金，像表头指针
    static let card = Color(white: 0.11)
    static let ready = Color(red: 0.45, green: 0.78, blue: 0.52)
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab = UserDefaults.standard.integer(forKey: "shotTab")   // 截图自检用：-shotTab 2

    var body: some View {
        Group {
            if store.api == nil {
                ConnectView()
            } else {
                TabView(selection: $tab) {
                    NavigationStack { AlbumsView().routes() }.withPlayerBar()
                        .tabItem { Label("专辑", systemImage: "square.grid.2x2") }.tag(0)
                    NavigationStack { ArtistsView().routes() }.withPlayerBar()
                        .tabItem { Label("艺人", systemImage: "music.mic") }.tag(1)
                    NavigationStack { SearchView().routes() }.withPlayerBar()
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(2)
                    NavigationStack { CardsView().routes() }.withPlayerBar()
                        .tabItem { Label("卡带库", systemImage: "sdcard") }.tag(3)
                    NavigationStack { MoreView().routes() }.withPlayerBar()
                        .tabItem { Label("更多", systemImage: "ellipsis.circle") }.tag(4)
                }
                .task { store.start() }
            }
        }
        .overlay(alignment: .top) {
            if let t = store.toast { ToastView(text: t).padding(.top, 8) }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }
}

/// 每个页面底下都有播放栏，点一下打开“正在播放”
struct PlayerBarModifier: ViewModifier {
    @EnvironmentObject var store: Store
    @State private var showNowPlaying = UserDefaults.standard.bool(forKey: "shotNowPlaying")

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayer { showNowPlaying = true }
            }
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView().environmentObject(store)
            }
    }
}

extension View {
    func withPlayerBar() -> some View { modifier(PlayerBarModifier()) }

    /// 每个标签页的导航栈都认这两种跳转：专辑页、艺人页
    func routes() -> some View {
        navigationDestination(for: AlbumRoute.self) { AlbumDetailView(albumId: $0.id) }
            .navigationDestination(for: ArtistRoute.self) { ArtistDetailView(name: $0.name) }
    }
}

struct AlbumRoute: Hashable { let id: Int64 }
struct ArtistRoute: Hashable { let name: String }

/// M.I.A.O.W 标志：一根等粗的线，两个尖是小猫耳，中间圆滑的凹谷是模拟波形（机箱\标志\miaow_mark.svg）
struct MiaowMark: Shape {
    func path(in r: CGRect) -> Path {
        // 原图 viewBox 宽 100，线的 y 从 24 到 52
        let sx = r.width / 100, sy = r.height / 28
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + (y - 24) * sy) }
        var path = Path()
        path.move(to: p(0, 52))
        path.addLine(to: p(14, 52))
        path.addLine(to: p(30, 24))
        path.addLine(to: p(42, 38))
        path.addCurve(to: p(58, 38), control1: p(44.4, 40.8), control2: p(55.6, 40.8))
        path.addLine(to: p(70, 24))
        path.addLine(to: p(86, 52))
        path.addLine(to: p(100, 52))
        return path
    }
}

struct MiaowLogo: View {
    var width: CGFloat = 120
    var body: some View {
        MiaowMark()
            .stroke(style: StrokeStyle(lineWidth: width * 0.052, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
            .frame(width: width, height: width * 0.28)
            .padding(.vertical, width * 0.04)
    }
}

/// 专辑封面：先给个底色占位，取到再换
struct CoverView: View {
    @EnvironmentObject var store: Store
    let album: Int64?
    let rev: String?
    var size: Int = 300
    var corner: CGFloat = 6
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(Color(white: 0.16))
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                MiaowMark().stroke(Color(white: 0.3), lineWidth: 2).padding(18).aspectRatio(100.0 / 28.0, contentMode: .fit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .task(id: key) { await load() }
    }

    private var key: String { "\(album ?? -1)|\(rev ?? "-")|\(size)" }

    private func load() async {
        guard let a = album, rev != nil, let api = store.api else { image = nil; return }
        let url = api.coverURL(album: a, size: size, rev: rev)
        if let c = CoverCache.shared.cached(url) { image = c; return }
        image = await CoverCache.shared.load(url, api: api)
    }
}

/// 识别候选的封面（本机有才有）
struct ReleaseCoverView: View {
    @EnvironmentObject var store: Store
    let release: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.16))
            if let img = image { Image(uiImage: img).resizable().scaledToFill() }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: release) {
            guard let api = store.api else { return }
            image = await CoverCache.shared.load(api.coverURL(release: release, size: 300), api: api)
        }
    }
}

/// 出错 / 空页面
struct NoteView: View {
    let icon: String
    let text: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let r = retry { Button("再试一次", action: r).buttonStyle(.bordered) }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
