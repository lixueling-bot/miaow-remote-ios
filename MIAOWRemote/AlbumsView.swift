// 专辑墙（和电脑上的首页一样）：最上面一排“卡里有的歌”，点了马上能放
import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var store: Store
    @State private var filter = ""
    @State private var ready: [Track] = []
    @State private var openAlbum: Int64? = {
        let v = UserDefaults.standard.integer(forKey: "shotAlbum")   // 截图自检用：-shotAlbum 12
        return v > 0 ? Int64(v) : nil
    }()

    private var shown: [AlbumBrief] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return store.albums }
        return store.albums.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.artist ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            if !ready.isEmpty && filter.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("卡里有的歌").font(.headline).padding(.horizontal)
                    Text("已经写在卡带里，点了马上播").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(ready) { t in
                                Button { Task { await store.playTrack(t.id) } } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        CoverView(album: t.albumId, rev: t.cover, size: 300).frame(width: 120, height: 120)
                                        Text(t.name).font(.caption.weight(.medium)).lineLimit(1)
                                        Text(t.artist ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(width: 120)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { Task { await store.playTrack(t.id, single: true) } } label: { Label("只播这一首", systemImage: "1.circle") }
                                    if let a = t.albumId { Button { openAlbum = a } label: { Label("打开专辑", systemImage: "square.stack") } }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }

            if let e = store.albumsError, store.albums.isEmpty {
                NoteView(icon: "wifi.exclamationmark", text: e) { Task { await store.reloadAlbums() } }
            } else if store.albums.isEmpty {
                ProgressView().padding(60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)], spacing: 20) {
                    ForEach(shown) { a in
                        NavigationLink(value: AlbumRoute(id: a.id)) { AlbumCell(album: a) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("专辑")
        .navigationDestination(isPresented: Binding(get: { openAlbum != nil }, set: { if !$0 { openAlbum = nil } })) {
            if let a = openAlbum { AlbumDetailView(albumId: a) }
        }
        .searchable(text: $filter, prompt: "在专辑墙里找")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("排序", selection: $store.sort) {
                        Text("按专辑名").tag("title")
                        Text("按艺人").tag("artist")
                        Text("按年份").tag("year")
                        Text("最近加入").tag("added")
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
        .refreshable { await store.reloadAlbums(); await loadReady() }
        .task {
            if store.albums.isEmpty { await store.reloadAlbums() }
            // 卡里的歌跟着写卡变，在这页时每 5 秒看一次
            while !Task.isCancelled {
                await loadReady()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func loadReady() async {
        guard let api = store.api, let c: CardsPage = try? await api.get("/v1/cards") else { return }
        ready = c.ready
    }
}

struct AlbumCell: View {
    let album: AlbumBrief
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverView(album: album.id, rev: album.cover, size: 400)
            Text(album.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text([album.artist, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
