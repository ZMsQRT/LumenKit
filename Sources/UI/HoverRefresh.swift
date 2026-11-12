//
//  HoverRefresh.swift
//  LumenKit
//
//  替代系统 `.refreshable` 的「悬停式」下拉刷新。
//
//  系统 `UIRefreshControl` 的菊花是滚动内容的一部分：刷新中往下滚列表，
//  菊花会跟着滚出屏幕。Flutter 侧 easy_refresh 的 `AppHeader`
//  （`position: IndicatorPosition.behind`）是另一套观感：
//  下拉时内容下移、指示器悬停在列表顶部，松手后指示器停在原地直到刷新结束。
//
//  SwiftUI 侧的做法：
//  - 用一个 `UIViewRepresentable` 探针盯住外层 `UIScrollView` 的 `contentOffset`，
//    算出「从顶部继续下拉的距离」；
//  - 指示器画在 `overlay(alignment: .top)` 里 —— 它在滚动内容之外，
//    所以天然不会随列表滚动，这就是「悬停」；
//  - 刷新期间用 `safeAreaInset(edge: .top)` 把内容下移一个 `triggerOffset`，
//    让指示器落在留出来的那条空白里，而不是压住第一行。
//

import SwiftUI
import UIKit

public extension View {
    /// 悬停式下拉刷新。
    ///
    /// ```swift
    /// ScrollView { ... }
    ///     .hoverRefresh { await viewModel.refresh() }
    /// ```
    ///
    /// - Parameters:
    ///   - triggerOffset: 触发刷新需要下拉的距离（pt），对应 easy_refresh 的 `triggerOffset: 60`。
    ///   - topInset: 指示器额外下移的距离，用于滚动视图忽略安全区、顶上有自绘导航栏的页面。
    ///   - foregroundColor: 菊花颜色，默认主题色（对应 `R.color.ctaColor`）。
    ///   - backgroundColor: 水滴填充色。
    ///   - showsWaterDrop: 是否显示水滴形变（对应 `userWaterDrop`）。
    ///   - action: 刷新动作，`await` 结束后指示器自动收起。
    func hoverRefresh(
        triggerOffset: CGFloat = 60,
        topInset: CGFloat = 0,
        foregroundColor: Color = Color.pink,
        backgroundColor: Color = Color.black.opacity(31 / 255),
        showsWaterDrop: Bool = true,
        loadingLabel: String = "Loading",
        indicatorIdentifier: String = "refresh.hover",
        action: @escaping () async -> Void
    ) -> some View {
        modifier(
            HoverRefreshModifier(
                triggerOffset: triggerOffset,
                topInset: topInset,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor,
                showsWaterDrop: showsWaterDrop,
                loadingLabel: loadingLabel,
                indicatorIdentifier: indicatorIdentifier,
                action: action
            )
        )
    }
}

// MARK: - 修饰器

private struct HoverRefreshModifier: ViewModifier {
    var triggerOffset: CGFloat
    var topInset: CGFloat
    var foregroundColor: Color
    var backgroundColor: Color
    var showsWaterDrop: Bool
    var loadingLabel: String
    var indicatorIdentifier: String
    var action: () async -> Void

    @StateObject private var controller = RefreshController()


    func body(content: Content) -> some View {
        content
            // 内容不足一屏也要能下拉，否则空态页永远刷新不了。
            .scrollBounceBehavior(.always, axes: .vertical)
            .background {
                ScrollRefreshProbe { distance, dragging in
                    controller.update(pull: distance, dragging: dragging)
                }
            }
            // 刷新中给指示器留出高度，列表内容整体下移；结束后收起。
            .safeAreaInset(edge: .top, spacing: 0) {
                if controller.isRefreshing {
                    Color.clear
                        .frame(height: max(triggerOffset, 1) + max(topInset, 0))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                indicator
                    .padding(.top, max(topInset, 0))
                    .allowsHitTesting(false)
            }
            .onAppear {
                controller.configure(triggerOffset: triggerOffset, action: action)
            }
            .onChange(of: triggerOffset) { _, newValue in
                controller.triggerOffset = newValue
            }
    }

    @ViewBuilder
    private var indicator: some View {
        if controller.isRefreshing || controller.pull > 0.5 {
            RefreshIndicator(
                phase: controller.phase,
                offset: displayedOffset,
                triggerOffset: triggerOffset,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor,
                showsWaterDrop: showsWaterDrop,
                loadingLabel: loadingLabel
            )
            .frame(height: max(displayedOffset, triggerOffset))
            .frame(maxWidth: .infinity, alignment: .top)
            .transition(.opacity)
            // 刷新中是「装饰性但仍需读出状态」的元素：给 VoiceOver 一个标签，
            // 同时给 UI 测试一个稳定的锚点，用来断言指示器没有随列表滚走。
            // 必须放在 `if` 分支里 —— 挂在空视图上会留下一个永不消失的无障碍节点。
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(indicatorIdentifier)
            .accessibilityLabel(Text(loadingLabel))
        }
    }

    /// 刷新中固定用触发距离，水滴收起、菊花居中，与 easy_refresh 的 `processed` 一致。
    private var displayedOffset: CGFloat {
        controller.isRefreshing ? triggerOffset : controller.pull
    }
}

// MARK: - 状态机

/// 下拉刷新的状态机，对应 easy_refresh `IndicatorState` 里本项目用到的部分。
///
/// 放在 `@MainActor` 类里而不是 `@State`，是为了让 UIKit 探针能直接回调，
/// 同时避免把非 `Sendable` 的刷新闭包塞进 `Task`。
@MainActor
public final class RefreshController: ObservableObject {
    public init() {}
    @Published public private(set) var phase: RefreshPhase = .inactive
    @Published public private(set) var pull: CGFloat = 0
    @Published public private(set) var isRefreshing = false

    /// 触发距离（pt）。
    public var triggerOffset: CGFloat = 60

    private var action: (() async -> Void)?
    /// 最后一次手指仍按下时的距离，避免松手回弹影响判断。
    private var lastDragPull: CGFloat = 0
    private var wasDragging = false
    private var isFinishing = false

    public func configure(triggerOffset: CGFloat, action: @escaping () async -> Void) {
        self.triggerOffset = triggerOffset
        self.action = action
    }

    /// 探针回调：`distance` 是从顶部继续往下拉的距离，`dragging` 是手指是否还按着。
    public func update(pull distance: CGFloat, dragging: Bool) {
        guard !isRefreshing else { return }

        let clamped = max(distance, 0)

        if dragging {
            wasDragging = true
            lastDragPull = clamped
        } else if wasDragging {
            wasDragging = false
            let released = lastDragPull
            lastDragPull = 0
            if released >= triggerOffset {
                pull = released
                begin()
                return
            }
        }

        if abs(clamped - pull) > 0.5 {
            pull = clamped
        }

        let next: RefreshPhase
        if clamped >= triggerOffset {
            next = .armed
        } else if clamped > 0.5 {
            next = .drag
        } else {
            next = .inactive
        }
        if next != phase {
            phase = next
        }
    }

    private func begin() {
        guard !isRefreshing, !isFinishing else { return }
        isRefreshing = true
        phase = .processing
        run()
    }

    private func run() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let action = self.action {
                await action()
            }
            await self.finish()
        }
    }

    private func finish() async {
        phase = .done
        try? await Task.sleep(nanoseconds: 300_000_000)

        isFinishing = true
        withAnimation(.easeOut(duration: 0.25)) {
            isRefreshing = false
            pull = 0
            phase = .inactive
        }
        isFinishing = false
    }
}

// MARK: - 滚动探针

/// 找到宿主滚动视图并汇报 `contentOffset`。
///
/// 挂成 `.background` 之后，探针与滚动视图是同一个容器里的兄弟节点，
/// 所以先看父级链上有没有 `UIScrollView`，再在最近几层子视图里找 ——
/// 这样既能覆盖 `.hoverRefresh` 直接挂在 `ScrollView` 上的写法，
/// 也能覆盖挂在「包着 ScrollView 的容器」上的写法。
private struct ScrollRefreshProbe: UIViewRepresentable {
    var onUpdate: (CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> ScrollRefreshProbeView {
        let view = ScrollRefreshProbeView()
        view.onUpdate = onUpdate
        return view
    }

    func updateUIView(_ uiView: ScrollRefreshProbeView, context: Context) {
        uiView.onUpdate = onUpdate
    }
}

@MainActor
private final class ScrollRefreshProbeView: UIView {
    var onUpdate: ((CGFloat, Bool) -> Void)?

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var lastDistance: CGFloat = -1
    private var lastDragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    private func attachIfNeeded() {
        guard window != nil else {
            detach()
            return
        }
        if let current = scrollView, current.window == nil {
            detach()
        }
        guard observation == nil else { return }
        guard let scroll = locateScrollView() else { return }
        scrollView = scroll
        observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            // UIScrollView 的 offset 只在主线程变；防御性判断一下再取主 actor。
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                self?.report(from: scroll)
            }
        }
        report(from: scroll)
    }

    private func detach() {
        observation?.invalidate()
        observation = nil
        scrollView = nil
        lastDistance = -1
        lastDragging = false
    }

    private func report(from scroll: UIScrollView) {
        let distance = max(0, -(scroll.contentOffset.y + scroll.adjustedContentInset.top))
        let dragging = scroll.isDragging
        guard abs(distance - lastDistance) > 0.5 || dragging != lastDragging else { return }
        lastDistance = distance
        lastDragging = dragging
        onUpdate?(distance, dragging)
    }

    // MARK: 查找

    private func locateScrollView() -> UIScrollView? {
        var node: UIView? = superview
        while let current = node {
            if let scroll = current as? UIScrollView, Self.isVertical(scroll) {
                return scroll
            }
            if let found = Self.firstVerticalScrollView(in: current, depth: 2) {
                return found
            }
            node = current.superview
        }
        return nil
    }

    private static func firstVerticalScrollView(in view: UIView, depth: Int) -> UIScrollView? {
        guard depth >= 0 else { return nil }
        var level: [UIView] = [view]
        for _ in 0...depth {
            var next: [UIView] = []
            for node in level {
                for sub in node.subviews {
                    if let scroll = sub as? UIScrollView, isVertical(scroll) {
                        return scroll
                    }
                    next.append(sub)
                }
            }
            level = next
            if level.isEmpty { return nil }
        }
        return nil
    }

    /// 排掉「横向轮播 / 分页容器」这类同为 `UIScrollView` 的祖先或兄弟。
    private static func isVertical(_ scroll: UIScrollView) -> Bool {
        guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return true }
        if scroll.isPagingEnabled, scroll.contentSize.width > scroll.bounds.width + 1 {
            return false
        }
        let horizontal = scroll.contentSize.width > scroll.bounds.width + 1
            && scroll.contentSize.height <= scroll.bounds.height + 1
        return !horizontal
    }
}

// MARK: - 预览

#if DEBUG

private struct HoverRefreshPreview: View {
    @State private var items = (0..<12).map { "Row \($0)" }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .hoverRefresh {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            items.shuffle()
        }
    }
}

#Preview("Refresh · Hover") {
    HoverRefreshPreview()
}

#endif
