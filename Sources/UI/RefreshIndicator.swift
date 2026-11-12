//  RefreshIndicator.swift
//  Port of `lib/ui/widgets/refresh/cupertino_activity_indicator.dart`
//  and `lib/ui/widgets/refresh/cupertino_indicator.dart`.
//
//  Flutter 侧是 easy_refresh 自带的一份 Cupertino 风格指示器拷贝：
//  `CupertinoActivityIndicator` 是 8 根刻度顺时针旋转的菊花，
//  `CupertinoIndicator` 则把它和「水滴」形变叠在一起做下拉刷新反馈。
//  SwiftUI 的 `ProgressView` 无法表达「部分刻度 + 半径随进度变化」，
//  所以这里按 Flutter 的画法重画一遍。
//

import SwiftUI

// MARK: - 刷新阶段

/// 对应 easy_refresh 的 `IndicatorMode`。
public enum RefreshPhase: Equatable, Sendable {
    /// 静止，无任何反馈。
    case inactive
    /// 正在下拉，未到触发阈值。
    case drag
    /// 已到阈值但手指还没松。
    case armed
    /// 松手后进入准备刷新。
    case ready
    /// 刷新中。
    case processing
    /// 刷新完成。
    case done
    /// 没有更多数据。
    case noMore

    public var isBusy: Bool {
        self == .ready || self == .processing
    }
}

// MARK: - 菊花

/// 对应 `CupertinoActivityIndicator`：8 根刻度、1 秒一圈。
struct ActivityIndicator: View {
    /// 默认取 iOS 13.2 的 `_kActiveTickColor`。
    var color: Color = Color(red: 60 / 255, green: 60 / 255, blue: 68 / 255)
    var animating: Bool = true
    var radius: CGFloat = 10
    /// 0…1，只显示前 `progress * 8` 根刻度（对应 `partiallyRevealed`）。
    var progress: Double = 1
    var loadingLabel: String = "Loading"

    private static let tickCount = 8

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: max(radius * 0.22, 1.2), height: radius * 0.46)
                    .offset(y: -radius * 0.68)
                    .rotationEffect(.degrees(Double(index) / Double(Self.tickCount) * 360))
                    .opacity(opacity(for: index))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(angle))
        .onAppear(perform: syncAnimation)
        .onChange(of: animating) { _, _ in syncAnimation() }
        .accessibilityLabel(Text(loadingLabel))
    }

    /// Flutter 里越靠前的刻度越亮，`progress` 控制露出的根数。
    private func opacity(for index: Int) -> Double {
        guard progress > 0 else { return 0 }
        let revealed = progress * Double(Self.tickCount) - Double(index)
        let clamped = min(max(revealed, 0), 1)
        // 已经露出的刻度保留 0.35~1 的层次，避免整圈全亮失去旋转感。
        let base = 0.35 + 0.65 * Double(Self.tickCount - index) / Double(Self.tickCount)
        return clamped * base
    }

    private func syncAnimation() {
        if animating {
            angle = 0
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                angle = 360
            }
        } else {
            withAnimation(.linear(duration: 0.15)) { angle = 0 }
        }
    }
}

// MARK: - 下拉指示器

/// 对应 `CupertinoIndicator`：水滴 + 菊花。
///
/// Flutter 版本依赖 easy_refresh 的 `IndicatorState`（含 offset / 触发阈值 /
/// infiniteOffset 等一堆状态）。SwiftUI 侧只保留渲染需要的三个量：
/// `phase`、`offset`、`triggerOffset`，由调用方（`.loadMoreTrigger` 或页面）
/// 根据滚动位置算好传进来。
struct RefreshIndicator: View {
    var phase: RefreshPhase
    /// 当前下拉距离（pt）。
    var offset: CGFloat
    /// 触发刷新的阈值（pt）。
    var triggerOffset: CGFloat
    var foregroundColor: Color = Color.gray
    /// 水滴颜色，默认取 `splashColor` 的近似值。
    var backgroundColor: Color = Color.black.opacity(31 / 255)
    var showsWaterDrop: Bool = true
    var loadingLabel: String = "Loading"
    /// `noMore` 时展示的内容，缺省用打包箱图标。
    var emptyContent: AnyView?

    /// 对应 `_kDefaultWaterDropCupertinoIndicatorRadius` / `_kDefaultCupertinoIndicatorRadius`。
    private var radius: CGFloat { showsWaterDrop ? 10 : 14 }

    private var scale: Double {
        guard triggerOffset > 0 else { return 0.01 }
        return Double(min(max(offset / triggerOffset, 0.01), 0.99))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showsWaterDrop {
                WaterDropShape(
                    offset: offset,
                    triggerOffset: triggerOffset
                )
                .fill(backgroundColor)
                .frame(height: max(offset, 0))
                .opacity(waterDropOpacity)
                .animation(.easeInOut(duration: 0.4), value: phase)
            }

            indicatorContent
                .frame(height: max(triggerOffset, 0))
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(offset, triggerOffset))
        .clipped()
    }

    @ViewBuilder
    private var indicatorContent: some View {
        switch phase {
        case .inactive:
            Color.clear
        case .drag, .armed:
            ActivityIndicator(
                color: foregroundColor,
                animating: false,
                radius: radius,
                progress: scale,
                loadingLabel: loadingLabel
            )
            // 对应 `Interval(0.0, 0.8, curve: easeInOut).transform(scale)`。
            .opacity(Double(min(scale / 0.8, 1)))
        case .ready, .processing:
            ActivityIndicator(color: foregroundColor, radius: radius, loadingLabel: loadingLabel)
        case .done:
            ActivityIndicator(
                color: foregroundColor,
                radius: radius * CGFloat(scale),
                loadingLabel: loadingLabel
            )
        case .noMore:
            if let emptyContent {
                emptyContent
            } else {
                Image(systemName: "archivebox")
                    .font(.system(size: radius * 1.4))
                    .foregroundStyle(foregroundColor)
            }
        }
    }

    private var waterDropOpacity: Double {
        switch phase {
        case .drag:
            return Double(min(max(offset / max(triggerOffset, 1), 0), 1))
        case .armed:
            return 1
        case .ready, .processing, .done:
            return 0
        case .inactive, .noMore:
            return 0
        }
    }
}

// MARK: - 水滴形变

/// 对应 `_WaterDropPainter`（只做竖向，横向列表本项目未使用）。
///
/// Flutter 用 `Path.combine(union, ...)` 把两个圆和一段贝塞尔梯形合并；
/// SwiftUI 的 `Path.fill` 默认就是非零环绕规则，多个子路径叠加天然等于并集。
struct WaterDropShape: Shape {
    var offset: CGFloat
    var triggerOffset: CGFloat

    private static let maxRadius: CGFloat = 20
    private static let minRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let trigger = max(triggerOffset, 1)

        var topRadius = Self.maxRadius
        var bottomRadius = Self.maxRadius

        if offset > trigger {
            let limit = Self.maxRadius - Self.minRadius
            let diff = limit * (1 - pow(100, -(offset - trigger) / 200))
            topRadius -= diff / 4
            bottomRadius -= diff
        }

        let topCenterY = trigger / 2
        path.addEllipse(in: CGRect(
            x: centerX - topRadius,
            y: topCenterY - topRadius,
            width: topRadius * 2,
            height: topRadius * 2
        ))

        guard offset > trigger else { return path }

        let bottomCenterY = offset - (trigger / 2 - topRadius) - bottomRadius
        path.addEllipse(in: CGRect(
            x: centerX - bottomRadius,
            y: bottomCenterY - bottomRadius,
            width: bottomRadius * 2,
            height: bottomRadius * 2
        ))

        let denominator = topCenterY - bottomCenterY
        guard abs(denominator) > 0.01 else { return path }
        let angle = asin(min(max((topRadius - bottomRadius) / denominator, -1), 1))

        let topX1 = centerX - topRadius * cos(angle)
        let topY1 = topCenterY + topRadius * sin(angle)
        let topX2 = centerX + topRadius * cos(angle)
        let topY2 = topY1
        let bottomX1 = centerX - bottomRadius * cos(angle)
        let bottomY1 = bottomCenterY + bottomRadius * sin(angle)
        let bottomX2 = centerX + bottomRadius * cos(angle)
        let bottomY2 = bottomY1

        path.move(to: CGPoint(x: centerX, y: topCenterY))
        path.addLine(to: CGPoint(x: topX1, y: topY1))
        path.addQuadCurve(
            to: CGPoint(x: bottomX1, y: bottomY1),
            control: CGPoint(x: centerX - bottomRadius, y: (bottomCenterY + topCenterY) / 2)
        )
        path.addLine(to: CGPoint(x: bottomX2, y: bottomY2))
        path.addQuadCurve(
            to: CGPoint(x: topX2, y: topY2),
            control: CGPoint(x: centerX + bottomRadius, y: (bottomCenterY + topY2) / 2)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - 便捷入口

public extension View {
    /// 把下拉指示器贴到列表顶部（用于自定义 `ScrollView` 头部）。
    func refreshHeader(
        phase: RefreshPhase,
        offset: CGFloat,
        triggerOffset: CGFloat = 60,
        foregroundColor: Color = Color.gray,
        loadingLabel: String = "Loading"
    ) -> some View {
        overlay(alignment: .top) {
            RefreshIndicator(
                phase: phase,
                offset: offset,
                triggerOffset: triggerOffset,
                foregroundColor: foregroundColor,
                loadingLabel: loadingLabel
            )
            .allowsHitTesting(false)
        }
    }
}
