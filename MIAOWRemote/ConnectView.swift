// 第一次打开：填播放器的地址（电脑上 设置 → 手机 / 平板遥控 那一行写着）
import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?

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
                    tip("1", "电脑上打开 MIAOW 播放器，设置 → 手机 / 平板遥控，勾上。那一行会写出地址，照着填。")
                    tip("2", "第一次打开时电脑会弹出 Windows 防火墙，点“允许”。")
                    tip("3", "手机和电脑连同一个 Wi-Fi。iPhone 问“查找本地网络上的设备”时点“好”。")
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.top, 10)
            }
            .padding(24)
        }
        .onAppear { if text.isEmpty { text = store.server } }
    }

    private func tip(_ n: String, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.bold()).frame(width: 20, height: 20).background(Circle().fill(Color(white: 0.2)))
            Text(s).font(.footnote).foregroundStyle(.secondary)
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
