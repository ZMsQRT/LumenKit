import Foundation

public enum NumberFormatting {
    /// Format a percentage value using an optional locale identifier.
    public static func localizedPercent(_ value: Double, locale: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale(identifier: locale ?? Locale.current.identifier)
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value / 100)) ?? "\(value)%"
    }
    /// Mirrors `PlatformDispatcher.instance.locale` usage in Dart.
    public static var localeIdentifier: String { Locale.current.identifier }

    /// 按设备地区格式化百分比，例如输入 90 得到 `90%`，并可指定显示的小数位数。
    /// 输入是百分数本身而非比例：传给 NumberFormatter 前需除以 100。
    /// 半数边界使用远离零舍入，与 Flutter 百分比格式化规则保持一致。
    public static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = Locale.current
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value / 100)) ?? "\(value)%"
    }

    /// Equivalent of `NumberFormat.simpleCurrency(locale:name:decimalDigits:)`.
    public static func currency(_ value: Double, code: String, decimalDigits: Int? = nil, symbol: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        if !code.isEmpty { formatter.currencyCode = code }
        if let symbol { formatter.currencySymbol = symbol }
        if let decimalDigits {
            formatter.minimumFractionDigits = decimalDigits
            formatter.maximumFractionDigits = decimalDigits
        }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// `NumberFormat.simpleCurrency(name:).currencySymbol`.
    public static func currencySymbol(code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        if !code.isEmpty { formatter.currencyCode = code }
        return formatter.currencySymbol ?? code
    }

    /// Currency-specific precision, including zero- and three-decimal currencies.
    public static func currencyDigits(code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        if !code.isEmpty { formatter.currencyCode = code }
        return formatter.maximumFractionDigits
    }

    /// Number of significant fractional digits in the value, including values
    /// whose Double description uses scientific notation. Integral values have none.
    public static func decimalDigits(of value: Double) -> Int {
        guard value.isFinite, value != value.rounded(.towardZero),
              let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { return 0 }
        return max(0, -decimal.exponent)
    }

    /// `double.parse(value.toStringAsFixed(digits))`.
    public static func rounded(_ value: Double, digits: Int = 2) -> Double {
        let text = String(format: "%.\(digits)f", value)
        return Double(text) ?? value
    }

    /// Fixed-decimal text, e.g. `9.5` → `"9.50"`.
    public static func fixed(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }
}
