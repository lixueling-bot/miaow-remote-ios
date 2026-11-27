// 第一次打开：填播放器的地址（电脑上 设置 → 手机 / 平板遥控 那一行写着）
import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var found: [FoundPlayer] = []
    @State private var scanning = false
    @State private var scanned = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                MiaowLogo(width: 150).foregroundStyle(Theme.accent).padding(.top, 60)
                Text("M.I.A.O.W").font(.title2.weight(.light)).tracking(6)
                Text("遥控家里的 MIAOW 播放器").foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("播放器地址").font(.footnote).foregroundStyle(.secondary)
                    TextField("例如 192.168.1.124:47880", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { go() }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    if let e = error { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                .frame(maxWidth: 420)

                Button(action: go) {
                    HStack { if busy { ProgressView() }; Text(busy ? "正在连接…" : "连接") }
                        .frame(maxWidth: 420).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Wi-Fi 里找到的播放器").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        if scanning { ProgressView() } else {
                            Button(scanned ? "再找一次" : "自动查找") { scan() }.font(.footnote)
                        }
                    }
                    ForEach(found) { f in
                        Button { text = f.url.absoluteString; go() } label: {
                            HStack {
                                Image(systemName: "hifispeaker").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.host.isEmpty ? f.name : f.host).foregroundStyle(.primary)
                                    Text(f.url.host ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(busy)
                    }
                    if scanned && !scanning && found.isEmpty {
                        Text("没找到。确认电脑上的遥控已打开、防火墙点了允许、手机和电脑连同一个 Wi-Fi；也可以在上面手填地址。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    tip("1", "电脑上打开 MIAOW 播放器，设置 → 手机 / 平板遥控，勾上。那一行会写出地址，照着填。")
                    tip("2", "第一次打开时电脑会弹出 Windows 防火墙，点“允许”。")
                    tip("3", "手机和电脑连同一个 Wi-Fi。iPhone 问“查找本地网络上的设备”时点“好”。")
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.top, 10)
            }
            .padding(24)
        }
        .onAppear {
            if text.isEmpty { text = store.server }
            if !scanned && !scanning { scan() }
        }
    }

    private func tip(_ n: String, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.bold()).frame(width: 20, height: 20).background(Circle().fill(Color(white: 0.2)))
            Text(s).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func scan() {
        scanning = true
        found = []
        Task {
            _ = await Discovery.scan { f in
                if !found.contains(f) { found.append(f) }
            }
            scanning = false
            scanned = true
        }
    }

    private func go() {
        busy = true
        error = nil
        Task {
            do { try await store.connect(text) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
