//  InsetRoundedShape.swift
//  Port of `lib/ui/widgets/custom_shape_border.dart`.
//
//  Flutter 的 `CustomShapeBorder` 只有一个用途：给 `ShapeDecoration`
//  提供「可按边偏移的圆角矩形」路径。`border_anchor`、`report_anchor`
//  和直播间礼物 tab 的选中下划线都用它把圆角矩形整体下移一段。
//
//  SwiftUI 侧不需要 `ShapeBorder` 基类，直接实现 `Shape` 即可；
//  `padding` 的加法与 Flutter `Rect.fromLTRBR` 保持完全一致：
//  right/bottom 是把 padding 加到边界上（不是内缩），只传 top 时
//  整个形状会向下平移并拉高。
//

import SwiftUI

// MARK: - 自定义圆角矩形

/// 对应 `CustomShapeBorder`：可带四边偏移的圆角矩形。
public struct InsetRoundedShape: Shape {
    /// 圆角半径。
    public var radius: CGFloat
    /// 对原始 rect 的四边偏移，语义与 Flutter 的 `EdgeInsets` 一致。
    public var padding: EdgeInsets

    public init(radius: CGFloat = 0, padding: EdgeInsets = EdgeInsets()) {
        self.radius = radius
        self.padding = padding
    }

    /// 只指定部分边的便捷构造，对应 `EdgeInsets.only(...)`。
    public static func only(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0,
        radius: CGFloat
    ) -> InsetRoundedShape {
        InsetRoundedShape(
            radius: radius,
            padding: EdgeInsets(
                top: top,
                leading: leading,
                bottom: bottom,
                trailing: trailing
            )
        )
    }

    /// 与 Flutter `getOuterPath` 相同的矩形计算。
    ///
    /// 单独暴露出来是为了让调用方在需要 `strokeBorder` / 阴影时
    /// 能拿到同一份几何，也方便单元测试直接校验。
    public func outerRect(in rect: CGRect) -> CGRect {
        let minX = rect.minX + padding.leading
        let minY = rect.minY + padding.top
        let maxX = rect.maxX + padding.trailing
        let maxY = rect.maxY + padding.bottom
        guard maxX > minX, maxY > minY else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func path(in rect: CGRect) -> Path {
        let outer = outerRect(in: rect)
        guard !outer.isNull, !outer.isEmpty else { return Path() }
        // Flutter 的 `RRect.fromLTRBR` 是圆角（circular），不是 continuous。
        return Path(roundedRect: outer, cornerRadius: radius)
    }
}

// MARK: - 便捷修饰器

public extension View {
    /// 用 `CustomShapeBorder` 裁剪内容。
    ///
    /// Flutter 里形状通常交给 `ShapeDecoration` 画背景；SwiftUI 的
    /// 内容裁剪用 `clipShape` 更自然，背景仍然可以继续用
    /// `BoxDecoration` / `boxDecoration`。
    func customShapeClip(
        radius: CGFloat,
        padding: EdgeInsets = EdgeInsets()
    ) -> some View {
        clipShape(InsetRoundedShape(radius: radius, padding: padding))
    }

    /// 用 `CustomShapeBorder` 画一圈描边。
    func customShapeBorder(
        radius: CGFloat,
        padding: EdgeInsets = EdgeInsets(),
        color: Color,
        lineWidth: CGFloat = 1
    ) -> some View {
        overlay {
            InsetRoundedShape(radius: radius, padding: padding)
                .stroke(color, lineWidth: lineWidth)
        }
    }

    /// 渐变描边版本，对应 Flutter 里 `ShapeDecoration` + `gradient` 的组合。
    func customShapeBorder(
        radius: CGFloat,
        padding: EdgeInsets = EdgeInsets(),
        gradient: LinearGradient,
        lineWidth: CGFloat = 1
    ) -> some View {
        overlay {
            InsetRoundedShape(radius: radius, padding: padding)
                .stroke(gradient, lineWidth: lineWidth)
        }
    }
}
