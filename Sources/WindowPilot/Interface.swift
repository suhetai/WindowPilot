import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var store: WindowStore
    @FocusState private var searchFocused: Bool
    @State private var cardFrames: [CGWindowID: CGRect] = [:]
    @State private var worm = WormHighlight()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows the user's system accent color (System Settings → Appearance).
    private let accent = Color.accentColor
    private static let gridSpace = "WindowPilot.grid"
    static let cornerRadius: CGFloat = 16
    private static let cardRadius: CGFloat = 12

    private var selectedID: CGWindowID? {
        let results = store.filtered
        return results.indices.contains(store.selected) ? results[store.selected].id : nil
    }

    private var selectedFrame: CGRect? { selectedID.flatMap { cardFrames[$0] } }

    var body: some View {
        let results = store.filtered
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()

            if !store.accessibility || !store.screenRecording {
                permissionBanner
            }

            HStack(spacing: 6) {
                Text(store.query.isEmpty ? "所有窗口" : "搜索结果").foregroundStyle(.secondary)
                Text("\(store.filtered.count)").foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.loading { ProgressView().controlSize(.mini) }
                Label("仅本地预览", systemImage: "lock").labelStyle(.titleAndIcon).foregroundStyle(.tertiary)
            }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    if store.filtered.isEmpty {
                        ContentUnavailableView {
                            Label(store.loading ? "正在查找窗口…" : "没有匹配的窗口", systemImage: "macwindow.on.rectangle")
                        } description: {
                            Text("试试应用名、项目名或窗口标题")
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: store.columns), spacing: 12) {
                            ForEach(results) { item in
                                card(item, selected: results.indices.contains(store.selected) && results[store.selected].id == item.id)
                                    .id(item.id)
                                    .background(GeometryReader { geometry in
                                        Color.clear.preference(key: CardFramesKey.self, value: [item.id: geometry.frame(in: .named(Self.gridSpace))])
                                    })
                                    .onTapGesture {
                                        store.selected = results.firstIndex(where: { $0.id == item.id }) ?? 0
                                        store.activate(item)
                                    }
                            }
                        }
                        .coordinateSpace(name: Self.gridSpace)
                        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
                        .background(alignment: .topLeading) { wormLayer(fill: true, visible: selectedFrame != nil) }
                        .overlay(alignment: .topLeading) { wormLayer(fill: false, visible: selectedFrame != nil) }
                        .id(store.query)
                        .padding(.horizontal, 16).padding(.bottom, 16)
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: store.selected) { _, index in
                    guard results.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[index].id, anchor: .center) }
                }
                .onChange(of: store.query) { _, _ in
                    if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            .onChange(of: selectedFrame) { _, frame in
                guard let frame else { return }
                worm.retarget(frame, id: selectedID, scope: store.query, animated: !reduceMotion)
            }
            .task(id: worm.startedAt) {
                guard worm.animating else { return }
                try? await Task.sleep(nanoseconds: UInt64(WindowLogic.wormDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                worm.settle()
            }
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }
            Divider()
            footer
        }
        // The window background is an NSVisualEffectView (see App.swift); keep SwiftUI transparent on top of it.
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onAppear { searchFocused = true }
        .onChange(of: store.navigating) { _, navigating in searchFocused = !navigating }
        .onReceive(NotificationCenter.default.publisher(for: .launcherDidOpen)) { _ in searchFocused = true }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in store.updatePermissions() }
    }

    // MARK: - Sections

    /// Spotlight-style search field: large plain text on the window material, no boxed border.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular)).foregroundStyle(.secondary)
            TextField("搜索应用或窗口，例如 vscode", text: $store.query)
                .textFieldStyle(.plain).font(.system(size: 22, weight: .regular))
                .focused($searchFocused)
                .onSubmit { store.selectCurrent() }
            if !store.query.isEmpty {
                Button { store.query = ""; store.navigating = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.tertiary)
                }.buttonStyle(.borderless).help("清除搜索")
            }
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
            }.buttonStyle(.borderless).foregroundStyle(.secondary).help("刷新窗口 · ⌘R")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var permissionBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("需要授权").font(.system(size: 12, weight: .semibold))
                Text("开启权限后可显示窗口预览并切换。授权后点刷新；若预览仍为空，请重启应用。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !store.accessibility { Button("辅助功能…") { store.openPermission(false) } }
            if !store.screenRecording { Button("屏幕录制…") { store.openPermission(true) } }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label(store.navigating ? "选择模式" : "搜索模式",
                  systemImage: store.navigating ? "square.grid.3x3" : "magnifyingglass")
                .foregroundStyle(.secondary)
            Spacer()
            if store.navigating {
                hint(["H", "J", "K", "L"], "移动")
                hint(["/"], "搜索")
            } else {
                hint(["⇥"], "选择")
                hint(["↑↓←→"], "移动")
            }
            hint(["↩"], "切换")
            hint(["esc"], "关闭")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    /// Keyboard shortcut rendered as small keycaps, similar to Spotlight and System Settings.
    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(minWidth: 16).padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
            Text(label).padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func wormLayer(fill: Bool, visible: Bool) -> some View {
        if visible {
            TimelineView(.animation(paused: !worm.animating)) { context in
                if let rect = worm.rect(at: context.date) {
                    let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    Group {
                        if fill { shape.fill(accent.opacity(0.18)) }
                        else { shape.strokeBorder(accent, lineWidth: 2) }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func previewPlaceholder(_ item: WindowItem) -> String {
        if let error = store.previewErrors[item.id] {
            return error.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "无法显示预览"
        }
        return store.screenRecording ? "正在加载预览…" : "需要屏幕录制权限"
    }

    private func card(_ item: WindowItem, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05))
                if let image = store.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 40, height: 40).opacity(0.8) }
                        Text(previewPlaceholder(item))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .help(store.previewErrors[item.id] ?? "")
                    }
                }
            }.frame(height: 142).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(alignment: .top, spacing: 8) {
                if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20).padding(.top, 1) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "未命名窗口" : item.title)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                    Text(item.app).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "return").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent) }
            }.padding(.horizontal, 4)
        }
        .padding(8)
        // The selected tint and accent border are drawn by the shared worm highlight (see wormLayer).
        .background(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.app)，\(item.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.activate(item) }
    }
}

extension Notification.Name {
    static let launcherDidOpen = Notification.Name("WindowPilot.launcherDidOpen")
}

/// Selection highlight state. A new target mid-flight restarts from the rect currently on screen,
/// so rapid key repeats keep the worm continuous instead of jumping.
struct WormHighlight {
    private(set) var from: CGRect?
    private(set) var to: CGRect?
    private(set) var startedAt: Date?
    private var id: CGWindowID?
    private var scope: String?

    var animating: Bool { startedAt != nil }

    func rect(at date: Date) -> CGRect? {
        guard let to else { return nil }
        guard let from, let startedAt else { return to }
        return WindowLogic.wormRect(from: from, to: to, elapsed: date.timeIntervalSince(startedAt))
    }

    mutating func retarget(_ frame: CGRect, id newID: CGWindowID?, scope newScope: String, animated: Bool) {
        let now = Date()
        // Same card re-laid out (e.g. window resize) or a new search: follow without the worm effect.
        if animated, let current = rect(at: now), newID != id, newScope == scope {
            from = current
            startedAt = now
        } else if startedAt == nil || newScope != scope {
            from = nil
            startedAt = nil
        }
        to = frame
        id = newID
        scope = newScope
    }

    mutating func settle() {
        from = nil
        startedAt = nil
    }
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [CGWindowID: CGRect] = [:]
    static func reduce(value: inout [CGWindowID: CGRect], nextValue: () -> [CGWindowID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
