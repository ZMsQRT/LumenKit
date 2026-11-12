import Foundation

/// 将持久化的本地缓存 URL 解析成当前沙盒内仍存在的文件。
/// App 更新或重新安装后沙盒根路径可能变化，旧的绝对路径不能直接用于播放。
public enum CachedFileResolver {
    /// 先检查原路径，再按 Library、Documents、tmp 中保留的相对路径尝试迁移。
    /// - Parameters:
    ///   - stored: 之前保存的文件 URL；网络 URL 和其他非文件 URL 不参与迁移。
    ///   - home: 当前沙盒根目录；可注入其他目录以验证迁移行为。
    /// - Returns: 已存在且不是目录的标准化文件 URL；找不到时返回 nil。
    public static func resolve(_ stored: URL, home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL? {
        guard stored.isFileURL else { return nil }
        let original = stored.standardizedFileURL
        if isFile(original) { return original }

        // 旧版本可能将绝对路径写入 UserDefaults / SQLite；保留已知目录下的相对部分。
        // 从后向前查找目录名，减少旧沙盒前缀本身包含相同目录名时的误匹配。
        for directory in ["Library", "Documents", "tmp"] {
            guard let range = original.path.range(of: "/\(directory)/", options: .backwards) else { continue }
            let relative = String(original.path[range.lowerBound...].dropFirst())
            let candidate = home.appendingPathComponent(relative).standardizedFileURL
            if isFile(candidate) { return candidate }
        }
        return nil
    }

    /// 缓存路径指向目录时不能交给媒体播放器，因此除了存在性还要检查文件类型。
    private static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
