// 和播放器说话：GET 读，POST 改（必须带 X-MIAOW-Remote 头，播放器靠它挡别的网页）。
import Foundation
import UIKit

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class API {
    let base: URL
    let session: URLSession

    static let defaultPort = 47880

    init(base: URL) {
        self.base = base
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.waitsForConnectivity = false
        // 封面回 Cache-Control: max-age 30 天 + ETag，交给系统缓存
        cfg.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 400 << 20)
        cfg.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: cfg)
    }

    /// 用户填的地址 → http://IP:端口/。只填 IP 也行，端口默认 47880
    static func normalize(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        if c.port == nil { c.port = defaultPort }
        c.path = "/"
        c.query = nil
        c.fragment = nil
        return c.url
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func url(_ path: String, _ query: [String: String?] = [:]) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.path = path
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        c.queryItems = items.isEmpty ? nil : items
        // 播放器把查询里的 + 当空格；“C++”这类要写成 %2B
        if let q = c.percentEncodedQuery { c.percentEncodedQuery = q.replacingOccurrences(of: "+", with: "%2B") }
        return c.url!
    }

    func coverURL(album: Int64, size: Int, rev: String?) -> URL {
        url("/v1/cover", ["album": String(album), "size": String(size), "rev": rev ?? "0"])
    }

    func coverURL(release: String, size: Int) -> URL {
        url("/v1/cover", ["release": release, "size": String(size)])
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:], timeout: TimeInterval = 15) async throws -> T {
        var req = URLRequest(url: url(path, query))
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return try await send(req)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], timeout: TimeInterval = 25) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("1", forHTTPHeaderField: "X-MIAOW-Remote")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    /// 换封面：内容直接是图片
    func uploadCover(album: Int64, jpeg: Data) async throws -> AlbumResult {
        var req = URLRequest(url: url("/v1/album/cover", ["id": String(album)]))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("1", forHTTPHeaderField: "X-MIAOW-Remote")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        return try await send(req)
    }

    func data(_ url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(message: "没有封面") }
        return data
    }

    private func send<T: Decodable>(_ req: URLRequest, retry: Bool = true) async throws -> T {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError {
            switch e.code {
            case .timedOut: throw APIError(message: "播放器没有回应（超时）")
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                throw APIError(message: "连不上播放器：确认电脑开着、遥控已打开、手机和电脑在同一个 Wi-Fi")
            default: throw APIError(message: e.localizedDescription)
            }
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 503 = 电脑上的界面这一下腾不出手（几秒内会好）：读的请求等一下自动再问一次
        if code == 503, retry, req.httpMethod ?? "GET" == "GET" {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return try await send(req, retry: false)
        }
        if code != 200 {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data), let m = e.error { throw APIError(message: m) }
            throw APIError(message: "播放器回了 HTTP \(code)")
        }
        do { return try API.decoder.decode(T.self, from: data) }
        catch { throw APIError(message: "看不懂播放器回的内容（\(T.self)）：\(error)") }
    }
}

/// 封面：内存里留一份解好的图，磁盘缓存交给 URLCache
@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private let mem = NSCache<NSURL, UIImage>()
    private var running: [URL: Task<UIImage?, Never>] = [:]

    init() { mem.countLimit = 400 }

    func cached(_ url: URL) -> UIImage? { mem.object(forKey: url as NSURL) }

    func load(_ url: URL, api: API) async -> UIImage? {
        if let img = mem.object(forKey: url as NSURL) { return img }
        if let t = running[url] { return await t.value }
        let t = Task<UIImage?, Never> {
            guard let d = try? await api.data(url), let img = UIImage(data: d) else { return nil }
            return img.preparingForDisplay() ?? img
        }
        running[url] = t
        let img = await t.value
        running[url] = nil
        if let img = img { mem.setObject(img, forKey: url as NSURL) }
        return img
    }
}
