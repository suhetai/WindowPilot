import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var store: WindowStore
    @FocusState private var searchFocused: Bool
    private let accent = Color(red: 0.57, green: 0.88, blue: 0.70)

    var body: some View {
        let results = store.filtered
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group").font(.system(size: 20)).foregroundStyle(accent)
                Text("WindowPilot").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(store.navigating ? "选择模式" : "搜索模式")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(accent.opacity(0.10), in: Capsule())
                Button(action: store.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新窗口 · ⌘R")
                Button { store.dismiss?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭 · Esc")
            }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 18)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(accent)
                TextField("搜索应用或窗口，例如 vscode…", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 23, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit { store.selectCurrent() }
                if !store.query.isEmpty {
                    Button { store.query = ""; store.navigating = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
                Text("⌘ D").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(accent.opacity(searchFocused ? 0.5 : 0.15)))
                .padding(.horizontal, 24)

            if !store.accessibility || !store.screenRecording {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                    Text("开启权限后可显示窗口预览并切换。授权后点刷新；若预览仍为空，请重启应用。")
                        .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !store.accessibility { Button("辅助功能") { store.openPermission(false) } }
                    if !store.screenRecording { Button("屏幕录制") { store.openPermission(true) } }
                }.padding(12).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24).padding(.top, 14)
            }

            HStack {
                Text(store.query.isEmpty ? "所有窗口" : "搜索结果").fontWeight(.medium)
                Text("\(store.filtered.count)").foregroundStyle(accent)
                Spacer()
                if store.loading { ProgressView().controlSize(.mini) }
                Text("本地预览").foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    if store.filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "macwindow").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text(store.loading ? "正在查找窗口…" : "没有匹配的窗口").font(.headline)
                            Text("试试应用名、项目名或窗口标题").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 85)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: store.columns), spacing: 16) {
                            ForEach(results) { item in
                                card(item, selected: results.indices.contains(store.selected) && results[store.selected].id == item.id)
                                    .id(item.id)
                                    .onTapGesture {
                                        store.selected = results.firstIndex(where: { $0.id == item.id }) ?? 0
                                        store.activate(item)
                                    }
                            }
                        }
                        .id(store.query)
                        .padding(.horizontal, 24).padding(.bottom, 20)
                    }
                }
                .onChange(of: store.selected) { _, index in
                    guard results.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[index].id, anchor: .center) }
                }
                .onChange(of: store.query) { _, _ in
                    if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            if let message = store.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 24).padding(.bottom, 12)
            }
            HStack(spacing: 16) {
                Text(store.navigating ? "h ←    j ↓    k ↑    l →" : "Tab 进入选择 · ↑↓←→ 移动")
                Spacer()
                Text("/ 搜索").opacity(store.navigating ? 1 : 0.45)
                Text("↵ 切换")
                Text("esc 关闭")
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 26).padding(.vertical, 16).background(.black.opacity(0.15))
        }
        .background(Color(red: 0.065, green: 0.085, blue: 0.09))
        .preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
        .onChange(of: store.navigating) { _, navigating in searchFocused = !navigating }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidOpen)) { _ in searchFocused = true }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in store.updatePermissions() }
    }

    private func card(_ item: WindowItem, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black.opacity(0.22)
                if let image = store.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit().padding(5)
                } else {
                    VStack(spacing: 9) {
                        if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 42, height: 42).opacity(0.75) }
                        Text(store.previewErrors[item.id] != nil ? "预览失败（悬停查看原因）" : (store.screenRecording ? "正在加载预览…" : "需要屏幕录制权限"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .help(store.previewErrors[item.id] ?? "")
                    }
                }
            }.frame(height: 142).clipped()
            HStack(alignment: .top, spacing: 8) {
                if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20).padding(.top, 2) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "未命名窗口" : item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                    Text(item.app).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(accent) }
            }.padding(11)
        }
        .background(selected ? accent.opacity(0.10) : Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? accent : .white.opacity(0.07), lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.app)，\(item.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.activate(item) }
    }
}

extension Notification.Name {
    static let launcherDidOpen = Notification.Name("WindowPilot.launcherDidOpen")
}
