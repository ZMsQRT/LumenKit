//  DateFormatting.swift
//  对应 Flutter 的 `lib/utils/format_util.dart`。
//
//  日期输入均为 Unix 时间戳，但单位由具体函数决定：VIP、优惠券、通话和记录
//  日期使用秒；生日使用毫秒。默认按设备本地时区解释，生日可指定来源时区。
//  单位不能仅凭整数大小可靠推断，调用方必须按对应接口约定传值。
//

import Foundation

/// 集中处理业务日期和时长的展示，不负责修改或持久化原始时间数据。
public enum DateFormatting {
    /// 固定使用公历，并将时间戳转换到指定时区后再提取日期分量。
    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 将整数补足至少两位，例如 3 → `03`、-3 → `-03`；较长数字保持原样。
    public static func twoDigits(_ value: Int) -> String {
        if value < 0 {
            // magnitude 也能处理 Int.min，避免对最小整数取反时发生溢出。
            let magnitude = value.magnitude
            return magnitude < 10 ? "-0\(magnitude)" : "-\(magnitude)"
        }
        return value >= 10 ? String(value) : "0\(String(value))"
    }

    /// VIP 到期日：输入秒级时间戳，输出 `dd/MM/yyyy`；无效值显示 `—`。
    public static func date(_ timestamp: Int) -> String { dayMonthYear(timestamp) }

    /// 上述业务日期共用同一格式和占位规则。
    private static func dayMonthYear(_ timestamp: Int) -> String {
        // 这些业务字段以 0 表示缺失；非正数或无法解析的值不展示为 1970 年日期。
        guard timestamp > 0, let parts = dateParts(timestamp) else { return "—" }
        return "\(twoDigits(parts.day))/\(twoDigits(parts.month))/\(parts.year)"
    }

    /// 生日：输入毫秒级时间戳，输出 `yyyy-MM-dd`；无法解析时返回空字符串。
    ///
    /// 默认按设备本地时区转换，与原有 Flutter 行为一致。如果服务端把“日期”
    /// 编码成某个时区的零点，调用方应传入该来源时区，避免跨时区后日期变化。
    /// 1970 年以前的负数时间戳是有效生日，不按业务到期日的缺失规则处理。
    public static func birthday(_ millisecondsSinceEpoch: Int, timeZone: TimeZone = .current) -> String {
        guard let parts = dateParts(millisecondsSinceEpoch, inMilliseconds: true, timeZone: timeZone) else { return "" }
        return "\(String(format: "%04d", parts.year))-\(twoDigits(parts.month))-\(twoDigits(parts.day))"
    }

    /// 记录日期：输入秒级时间戳，输出 `dd-MM HH:mm`；无效值显示 `—`。
    public static func recordDate(_ timestamp: Int) -> String {
        guard timestamp > 0, let parts = dateParts(timestamp) else { return "—" }
        return "\(twoDigits(parts.day))-\(twoDigits(parts.month)) \(twoDigits(parts.hour)):\(twoDigits(parts.minute))"
    }

    /// 将秒数格式化为通话或直播时长。
    ///
    /// 负数按 0 秒处理；不足一小时默认显示 `mm:ss`，达到一小时或显式传入
    /// `showHours` 时显示 `HH:mm:ss`。小时为累计值，超过 24 小时也不会归零。
    public static func duration(_ duration: Int, showHours: Bool = false) -> String {
        let duration = max(duration, 0)
        let hours = duration / 3600
        let minutes = duration / 60 % 60
        let seconds = duration % 60
        if hours > 0 || showHours {
            return "\(twoDigits(hours)):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(twoDigits(minutes)):\(twoDigits(seconds))"
    }

    /// 返回与 Flutter 对齐的英文月份缩写；不在 1...12 范围内时返回空字符串。
    /// 该方法使用固定英文缩写，不随设备语言切换。
    public static func monthString(_ month: Int) -> String {
        switch month {
        case 1: "Jan"
        case 2: "Feb"
        case 3: "Mar"
        case 4: "Apr"
        case 5: "May"
        case 6: "Jun"
        case 7: "Jul"
        case 8: "Aug"
        case 9: "Sep"
        case 10: "Oct"
        case 11: "Nov"
        case 12: "Dec"
        default: ""
        }
    }

    /// 判断两个秒级时间戳是否属于设备本地时区的同一日。
    /// 任一时间超出支持范围时返回 false；此通用比较不把 0 特判为缺失值。
    public static func isSameDay(_ timestamp1: Int, _ timestamp2: Int) -> Bool {
        guard let lhs = dateParts(timestamp1), let rhs = dateParts(timestamp2) else { return false }
        return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
    }

    /// 将秒或毫秒时间戳转换为指定时区的公历分量；转换失败返回 nil。
    /// 该方法只处理日期转换，“0 是否代表缺失”由上层业务格式化函数决定。
    private static func dateParts(
        _ timestamp: Int,
        inMilliseconds: Bool = false,
        timeZone: TimeZone = .current
    ) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int)? {
        let seconds = inMilliseconds ? Double(timestamp) / 1000 : Double(timestamp)
        // 限制支持的时间范围，避免极端数值进入日历转换；常见的毫秒值误传给
        // 秒接口时也会被拒绝，但秒和毫秒的取值范围有重叠，不能依此自动识别单位。
        guard seconds >= -62_135_596_800, seconds < 253_402_300_800 else { return nil }
        let components = calendar(in: timeZone).dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: seconds)
        )
        // 时区换算后再次验证公元纪元和年份，并要求所有输出分量均存在。
        guard components.era == 1, let year = components.year, (1...9999).contains(year),
              let month = components.month, let day = components.day,
              let hour = components.hour, let minute = components.minute else { return nil }
        return (year, month, day, hour, minute)
    }
}

