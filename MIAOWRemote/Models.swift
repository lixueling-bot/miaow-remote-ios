// 播放器遥控接口（原生播放器\遥控接口.md）回的 JSON。解码用 convertFromSnakeCase：duration_s → durationS。
// 播放器那边很多字段可能是 null，这里几乎都写成可选，免得一项对不上整个页面就打不开。
import Foundation

struct LoadInfo: Codable, Hashable {
    var state: String?      // ready 已在卡里 / writing 正在写 / none 要现写
    var pct: Int?
    var waitS: Double?
    var needErase: Bool?
}

struct Track: Codable, Identifiable, Hashable {
    var id: Int64
    var title: String?
    var artist: String?
    var albumId: Int64?
    var album: String?
    var cover: String?
    var trackNo: Int?
    var discNo: Int?
    var durationS: Double?
    var format: String?
    var sampleRate: Int?
    var bits: Int?
    var lossless: Bool?
    var load: LoadInfo?

    var name: String { title?.isEmpty == false ? title! : "（无标题）" }
    var formatText: String {
        var parts: [String] = []
        if let f = format, !f.isEmpty { parts.append(f.uppercased()) }
        if let b = bits, b > 0 { parts.append("\(b) bit") }
        if let r = sampleRate, r > 0 { parts.append(String(format: r % 1000 == 0 ? "%.0f kHz" : "%.1f kHz", Double(r) / 1000)) }
        return parts.joined(separator: " · ")
    }
}

struct AlbumBrief: Codable, Identifiable, Hashable {
    var id: Int64
    var title: String?
    var artist: String?
    var year: String?
    var tracks: Int?
    var durationS: Double?
    var cover: String?
    var idState: String?
    var quality: String?
    var added: Int64?

    var name: String { title?.isEmpty == false ? title! : "（无标题）" }
}

struct EditField: Codable, Hashable {
    var user: String?
    var auto: String?
}

struct EditInfo: Codable, Hashable {
    var title: EditField?
    var artist: EditField?
    var year: EditField?
    var label: EditField?
    var genre: EditField?
}

struct AlbumDetail: Codable, Identifiable {
    var id: Int64
    var title: String?
    var artist: String?
    var year: String?
    var durationS: Double?
    var cover: String?
    var idState: String?
    var quality: String?
    var rev: Int?
    var genre: String?
    var label: String?
    var notes: String?
    var coverSource: String?
    var idMethod: String?
    var idEvidence: String?
    var candidates: Int?
    var queued: Bool?
    var playingTrack: Int64?
    var edit: EditInfo?
    var tracks: [Track]

    var name: String { title?.isEmpty == false ? title! : "（无标题）" }
    var brief: AlbumBrief {
        AlbumBrief(id: id, title: title, artist: artist, year: year, tracks: tracks.count, durationS: durationS,
                   cover: cover, idState: idState, quality: quality, added: nil)
    }
}

struct PlayerState: Codable {
    var rev: Int?
    var output: String?         // cart / cart_offline / local
    var state: String?          // playing / paused / stopped
    var preparing: Bool?
    var positionS: Double?
    var durationS: Double?
    var canSeek: Bool?
    var track: Track?
    var pending: Track?
    var nextPick: Track?
    var nextText: String?
    var queuedAlbum: AlbumBrief?
    var single: Bool?
    var `repeat`: String?       // off / album / track
    var queueIndex: Int?
    var queueCount: Int?
    var busy: Bool?
    var firmwareBusy: Bool?
    var status: String?

    var playing: Bool { state == "playing" }
}

struct ServerInfo: Codable {
    var name: String?
    var api: Int?
    var build: String?
    var host: String?
    var urls: [String]?
    var pairing: Bool?
}

struct ErrorBody: Codable { var ok: Bool?; var error: String? }

struct ControlResult: Codable {
    var ok: Bool?
    var result: String?         // play：queued_next = 排成了下一首；playing = 马上放
    var state: PlayerState?
}

struct AlbumResult: Codable { var ok: Bool?; var album: AlbumDetail? }
struct OkResult: Codable { var ok: Bool? }
struct JobResult: Codable { var ok: Bool?; var job: Int }

struct AlbumsPage: Codable {
    var rev: Int?
    var sort: String?
    var total: Int?
    var offset: Int?
    var albums: [AlbumBrief]
}

struct ArtistItem: Codable, Identifiable, Hashable {
    var name: String
    var albums: Int?
    var tracks: Int?
    var coverAlbum: Int64?
    var id: String { name }
}

struct ArtistsPage: Codable { var rev: Int?; var artists: [ArtistItem] }
struct ArtistAlbums: Codable { var name: String?; var albums: [AlbumBrief] }

struct SearchPage: Codable {
    var q: String?
    var artists: [ArtistItem]
    var albums: [AlbumBrief]
    var tracks: [Track]
}

struct Slot: Codable, Identifiable {
    var n: Int
    var group: String?
    var state: String?          // BLANK / READY / ……（卡带库报的原样）
    var routedTo: String?       // A / B = 接在播放机的哪个口
    var title: String?
    var track: Track?
    var part: Int?
    var current: Bool?
    var protected: Bool?
    var writingPct: Int?
    var erasingS: Double?
    var id: Int { n }
}

struct CardsPage: Codable {
    var connected: Bool
    var wanted: Bool?
    var firmware: String?
    var writing: String?
    var slots: [Slot]
    var ready: [Track]
}

struct QueuePage: Codable {
    var index: Int?
    var single: Bool?
    var count: Int?
    var tracks: [Track]
    var nextPick: Track?
    var queuedAlbum: AlbumBrief?
}

struct HistoryItem: Codable, Identifiable {
    var playedAt: Int64
    var track: Track
    var id: String { "\(playedAt)-\(track.id)" }
}

struct IdentifySummary: Codable {
    var rev: Int?
    var matched: Int?
    var candidates: Int?
    var unknown: Int?
    var none: Int?
    var canIdentify: Bool?
    var catalog: String?
    var online: String?
    var busy: Bool?
    var status: String?
}

struct OurTrack: Codable, Hashable {
    var id: Int64?
    var title: String?
    var lengthMs: Int64?
}

struct CandTrack: Codable, Hashable {
    var title: String?
    var lengthMs: Int64?
}

struct Candidate: Codable, Identifiable, Hashable {
    var token: String
    var title: String?
    var artist: String?
    var year: String?
    var score: Int?
    var method: String?
    var reason: String?
    var release: String?
    var hasCover: Bool?
    var tracks: [CandTrack]?
    var id: String { token }
}

struct CandidatesPage: Codable {
    var album: AlbumBrief?
    var idEvidence: String?
    var ours: [OurTrack]
    var candidates: [Candidate]
}

struct SearchJobPage: Codable {
    var done: Bool
    var elapsedS: Double?
    var album: AlbumBrief?
    var ours: [OurTrack]?
    var candidates: [Candidate]?
}

func timeText(_ s: Double?) -> String {
    guard let s = s, s.isFinite, s >= 0 else { return "--:--" }
    let t = Int(s.rounded())
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
