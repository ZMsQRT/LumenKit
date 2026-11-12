//  AnimatedCounter.swift
//  Port of `lib/ui/widgets/text/animated_flip_counter.dart`.
//
//  Flutter 版本把数字拆成单个 digit，用 `TweenAnimationBuilder`
//  做上下翻动；SwiftUI 侧用「`Animatable` 视图 + 每帧重新格式化」
//  达到同样的连续变化效果，格式化规则与 Dart 实现逐条对齐：
//
//  * 小数位先放大 10^(fractionDigits+1) 再 floor，最后 ~/10（截断，不四舍五入）；
//  * `wholeDigits` 补前导零；`wholeDigits == 0` 且整数部分为 0 时不显示整数位；
//  * `thousandSeparator` 从右往左每 3 位插一次；
//  * 负号只在数值非零时出现。
//

import SwiftUI

// MARK: - 格式

/// 对应 `AnimatedFlipCounter` 的文本参数。
public struct CounterFormat: Equatable, Sendable {
    public var prefix: String?
    public var suffix: String?
    /// 小数点后的位数，负数按 0 处理。
    public var fractionDigits: Int
    /// 整数部分最少显示几位，负数按 0 处理。
    public var wholeDigits: Int
    /// 千分位符号，`nil` 表示不分组。
    public var thousandSeparator: String?
    public var decimalSeparator: String

    public init(
        prefix: String? = nil,
        suffix: String? = nil,
        fractionDigits: Int = 0,
        wholeDigits: Int = 1,
        thousandSeparator: String? = nil,
        decimalSeparator: String = "."
    ) {
        self.prefix = prefix
        self.suffix = suffix
        self.fractionDigits = max(fractionDigits, 0)
        self.wholeDigits = max(wholeDigits, 0)
        self.thousandSeparator = thousandSeparator
        self.decimalSeparator = decimalSeparator
    }
}

// MARK: - 数字滚动

/// 对应 `AnimatedFlipCounter`：值变化时逐帧滚动到新值。
public struct AnimatedCounter: View {
    let value: Double
    var format: CounterFormat
    var duration: TimeInterval
    var curve: Animation
    var font: Font
    var color: Color
    var lineLimit: Int?

    /// 当前显示的中间值。`initialValue` 非空时先显示它，再动画到 `value`。
    @State private var displayValue: Double

    public init(
        value: Double,
        initialValue: Double? = nil,
        format: CounterFormat = CounterFormat(),
        duration: TimeInterval = 0.3,
        curve: Animation? = nil,
        font: Font = .system(size: 24, weight: .bold),
        color: Color = .white,
        lineLimit: Int? = 1
    ) {
        self.value = value
        self.format = format
        self.duration = duration
        self.curve = curve ?? .easeOut(duration: duration)
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        _displayValue = State(initialValue: (initialValue ?? value).isFinite ? (initialValue ?? value) : 0)
    }

    /// 整数便捷入口，覆盖 VIP 价格 / 礼物数量等最常见的用法。
    public init(
        value: Int,
        initialValue: Int? = nil,
        format: CounterFormat = CounterFormat(),
        duration: TimeInterval = 0.3,
        curve: Animation? = nil,
        font: Font = .system(size: 24, weight: .bold),
        color: Color = .white,
        lineLimit: Int? = 1
    ) {
        self.init(
            value: Double(value),
            initialValue: initialValue.map(Double.init),
            format: format,
            duration: duration,
            curve: curve,
            font: font,
            color: color,
            lineLimit: lineLimit
        )
    }

    public var body: some View {
        Text(AnimatedCounter.formattedString(for: displayValue, format: format))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.6)
            // 用系统数字过渡替代手写 `Animatable`：
            // `Animatable` 要求 `animatableData` 非隔离，而 `View` 协议本身是
            // `@MainActor`，Swift 6 会判定「conformance crosses into main actor-isolated
            // code」。`contentTransition(.numericText(value:))` 是 iOS 17 原生能力，
            // 逐位滚动效果一致且没有并发告警。
            .contentTransition(.numericText(value: displayValue))
            .animation(curve, value: displayValue)
            .task(id: value) {
                let safeValue = value.isFinite ? value : 0
                guard displayValue != safeValue else { return }
                displayValue = safeValue
            }
    }
}

// MARK: - 纯格式化

extension AnimatedCounter {
    /// 与 `AnimatedFlipCounter._buildCounter` 完全一致的文本输出。
    ///
    /// 单独做成静态方法是刻意为之：动画只关心 `value` 插值，
    /// 文本规则可以被单元测试直接覆盖。
    public static func formattedString(
        for value: Double,
        format: CounterFormat
    ) -> String {
        let fractionDigits = min(max(format.fractionDigits, 0), 9)
        let wholeDigits = min(max(format.wholeDigits, 0), 100)
        let safeValue = value.isFinite ? value : 0

        // Avoid trapping when malformed or unusually large values arrive from the API.
        let factor = pow(10.0, Double(fractionDigits + 1))
        let scaledValue = floor(abs(safeValue) * factor)
        guard scaledValue.isFinite, scaledValue < Double(Int.max) else {
            return (format.prefix ?? "") + String(format: "%.0f", safeValue) + (format.suffix ?? "")
        }
        let scaled = Int(scaledValue) / 10
        let divisor = Int(pow(10.0, Double(fractionDigits)))
        let integerPart = scaled / max(divisor, 1)
        let fractionPart = scaled % max(divisor, 1)

        let showsMinus = safeValue < 0 && scaled != 0

        var integerText = String(integerPart)
        if integerPart == 0, fractionDigits > 0, wholeDigits == 0 {
            // Flutter 的 digits 从有效数字开始构造，0.7 + wholeDigits 0 会输出 ".7"。
            integerText = ""
        } else if integerText.count < wholeDigits {
            integerText = String(
                repeating: "0",
                count: wholeDigits - integerText.count
            ) + integerText
        }

        if let separator = format.thousandSeparator,
           !separator.isEmpty,
           integerText.count > 3 {
            integerText = grouped(integerText, separator: separator)
        }

        var fractionText = ""
        if fractionDigits > 0 {
            let raw = String(fractionPart)
            fractionText = format.decimalSeparator
                + String(repeating: "0", count: max(fractionDigits - raw.count, 0))
                + raw
        }

        let sign = showsMinus ? "-" : ""
        return (format.prefix ?? "")
            + sign
            + integerText
            + fractionText
            + (format.suffix ?? "")
    }

    private static func grouped(_ digits: String, separator: String) -> String {
        var characters = Array(digits)
        var groups: [String] = []
        while characters.count > 3 {
            groups.insert(String(characters.suffix(3)), at: 0)
            characters.removeLast(3)
        }
        groups.insert(String(characters), at: 0)
        return groups.joined(separator: separator)
    }
}
