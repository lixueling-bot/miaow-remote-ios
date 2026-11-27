// 在家里 Wi-Fi 里找播放器：不用播放器那边做 Bonjour，直接把手机所在网段（最多 254 个地址）
// 的 47880 端口挨个问一下 /v1/info，回得上来的就是 MIAOW 播放器。一般 3～6 秒扫完。
// 用在两处：连接页的“自动查找”；电脑换了 IP（路由器重新分配）后，App 连不上时自动找回来。
import Foundation
import Darwin

struct FoundPlayer: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let host: String        // 电脑名（/v1/info 的 host），用来认“还是原来那台”
    var id: String { url.absoluteString }
}

enum Discovery {
    /// 问一下就放弃的短超时连接，扫描和试备用地址都用它
    static let quick: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 1.5
        c.timeoutIntervalForResource = 3
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 2
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// 这个地址上是不是 MIAOW 播放器
    static func probe(_ base: URL) async -> FoundPlayer? {
        var req = URLRequest(url: base.appendingPathComponent("v1/info"))
        req.timeoutInterval = 1.5
        guard let (data, resp) = try? await quick.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let info = try? API.decoder.decode(ServerInfo.self, from: data),
              info.api != nil else { return nil }
        return FoundPlayer(url: base, name: info.name ?? "MIAOW 播放器", host: info.host ?? base.host ?? "")
    }

    /// 扫手机所在的网段。onFound 每找到一台就回调一次（连接页边扫边显示）
    static func scan(port: Int = API.defaultPort,
                     onFound: @escaping @MainActor (FoundPlayer) -> Void = { _ in }) async -> [FoundPlayer] {
        guard let (addr, mask0) = localNet() else { return [] }
        // 网段太大（例如 /16）只扫自己所在的那 256 个地址
        let mask: UInt32 = (~mask0) > 1023 ? 0xFFFF_FF00 : mask0
        let net = addr & mask
        let bcast = net | ~mask
        guard bcast > net &+ 1 else { return [] }
        let hosts = (net &+ 1 ..< bcast).filter { $0 != addr }
        func url(_ h: UInt32) -> URL { URL(string: "http://\(ipString(h)):\(port)/")! }

        var found: [FoundPlayer] = []
        await withTaskGroup(of: FoundPlayer?.self) { g in
            var next = 0
            while next < min(48, hosts.count) {
                let u = url(hosts[next]); next += 1
                g.addTask { await probe(u) }
            }
            while let r = await g.next() {
                if let f = r {
                    found.append(f)
                    await onFound(f)
                }
                if next < hosts.count {
                    let u = url(hosts[next]); next += 1
                    g.addTask { await probe(u) }
                }
            }
        }
        return found
    }

    /// 手机自己的 IPv4 地址和子网掩码（主机字节序）。优先 Wi-Fi（en0）
    static func localNet() -> (UInt32, UInt32)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var best: (UInt32, UInt32)?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), let nm = ifa.ifa_netmask else { continue }
            let flags = Int32(truncatingIfNeeded: ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            let a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard isPrivate(a), m != 0 else { continue }
            if name == "en0" { return (a, m) }
            if best == nil { best = (a, m) }
        }
        return best
    }

    static func isPrivate(_ a: UInt32) -> Bool {
        a >> 24 == 10 || a >> 20 == 0xAC1 || a >> 16 == 0xC0A8 || a >> 16 == 0xA9FE
    }

    static func ipString(_ a: UInt32) -> String {
        "\(a >> 24 & 255).\(a >> 16 & 255).\(a >> 8 & 255).\(a & 255)"
    }
}
