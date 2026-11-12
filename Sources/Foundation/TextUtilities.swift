import CryptoKit
import Foundation

/// Project-independent text helpers.
public enum TextUtilities {
    public static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func truncate(_ value: String, length: Int, trailing: String = "…") -> String {
        value.count > length ? String(value.prefix(length)) + trailing : value
    }
}
