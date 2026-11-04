import Foundation

/// Nhóm hiển thị của rule: "An toàn" hoặc "Tuỳ bạn".
public enum RuleGroup: String, Codable, Sendable {
    case safe, review
}
