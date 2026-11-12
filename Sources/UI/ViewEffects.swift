import SwiftUI

// MARK: - 渐变描边

/// 对应 `GradientBoxBorder`：用渐变画一圈描边。
///
/// 实现方式与 Flutter 一致——外层铺渐变，内层用背景色裁掉中间，
/// 这样任何圆角都能贴合（`strokeBorder` 的渐变方向会随形状偏移，不适合）。
struct GradientBorderModifier: ViewModifier {
    var gradient: LinearGradient
    var lineWidth: CGFloat = 1
    var cornerRadius: CGFloat = 0
    /// 内层遮罩色。需要透出下层内容时传 `nil`，改用 `strokeBorder` 方案。
    var fill: Color?

    func body(content: Content) -> some View {
        content
            .background {
                if let fill {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(gradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: max(cornerRadius - lineWidth, 0), style: .continuous)
                                .fill(fill)
                                .padding(lineWidth)
                        }
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(gradient, lineWidth: lineWidth)
                }
            }
    }
}

public extension View {
    /// 渐变描边（不填充内部）。
    func gradientStroke(
        _ gradient: LinearGradient,
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat = 0
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(gradient, lineWidth: lineWidth)
        }
    }

    /// 渐变描边 + 指定内部填充色。
    func gradientBorder(
        _ gradient: LinearGradient,
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat = 0,
        fill: Color
    ) -> some View {
        modifier(GradientBorderModifier(
            gradient: gradient,
            lineWidth: lineWidth,
            cornerRadius: cornerRadius,
            fill: fill
        ))
    }

    /// 圆形渐变描边。
    func gradientCircleStroke(_ gradient: LinearGradient, lineWidth: CGFloat = 1) -> some View {
        overlay { Circle().strokeBorder(gradient, lineWidth: lineWidth) }
    }
}

// MARK: - 内阴影

/// 对应 `InnerShadow`。
///
/// SwiftUI 没有内阴影，这里用「反向遮罩 + 模糊」实现：把形状外扩后裁掉内部，
/// 再把阴影画在裁剪区域内。
struct InnerShadowModifier: ViewModifier {
    var color: Color = Color(red: 160 / 255, green: 163 / 255, blue: 189 / 255).opacity(41 / 255)
    var radius: CGFloat = 12
    var offset: CGSize = CGSize(width: 0, height: 16)
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let rect = CGRect(origin: .zero, size: proxy.size)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(color, lineWidth: radius * 2)
                    .blur(radius: radius)
                    .offset(offset)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .compositingGroup()
                    .allowsHitTesting(false)
                    .frame(width: rect.width, height: rect.height)
            }
        }
    }
}

public extension View {
    /// 内阴影。
    func innerShadow(
        color: Color = Color(red: 160 / 255, green: 163 / 255, blue: 189 / 255).opacity(41 / 255),
        radius: CGFloat = 12,
        offset: CGSize = CGSize(width: 0, height: 16),
        cornerRadius: CGFloat = 0
    ) -> some View {
        modifier(InnerShadowModifier(color: color, radius: radius, offset: offset, cornerRadius: cornerRadius))
    }
}

// MARK: - 阴影

/// 对应 `DropShadow`：Flutter 里用 `BoxShadow` 实现的一组常用投影。
enum ShadowStyles {
    static let card = Color.black.opacity(0.06)
    static let dialog = Color.black.opacity(0.18)

    /// 卡片投影。
    static func card(radius: CGFloat = 16, y: CGFloat = 4) -> some ViewModifier {
        ShadowModifier(color: card, radius: radius, y: y)
    }
}

struct ShadowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: 0, y: y)
    }
}

// MARK: - 圆角便捷

public extension View {
    /// Flutter 里 `BorderRadius.circular(r)` 的直译。
    func roundedCorners(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 只圆上面两个角（弹窗 / 底部弹层常用）。
    func roundedTopCorners(_ radius: CGFloat) -> some View {
        clipShape(UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        ))
    }
}
