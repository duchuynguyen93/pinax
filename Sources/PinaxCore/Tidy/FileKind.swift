import Foundation
import UniformTypeIdentifiers

/// Nhóm file khi sắp xếp Downloads (§3.5). Tên thư mục đích cố định tiếng Anh, không localize để ổn định.
public enum FileKind: String, CaseIterable, Sendable, Hashable {
    case installers, archives, images, videos, audio, documents, code, other

    public var folderName: String {
        switch self {
        case .installers: "Installers"
        case .archives: "Archives"
        case .images: "Images"
        case .videos: "Videos"
        case .audio: "Audio"
        case .documents: "Documents"
        case .code: "Code"
        case .other: "Other"
        }
    }

    private static let installerExts: Set<String> = ["dmg", "pkg", "mpkg"]
    private static let archiveExts: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"]
    private static let documentExts: Set<String> = [
        "pdf", "txt", "text", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "csv", "md", "epub",
    ]
    // `ts` nằm đây (không phải MPEG transport stream) nên kiểm trước UTType.
    private static let codeExts: Set<String> = [
        "json", "yaml", "yml", "sh", "xml", "html", "css", "swift", "dart", "py", "js", "ts",
    ]

    /// Thứ tự kiểm: Installers → Archives → Images → Videos → Audio → Documents → Code → Other.
    /// Đuôi liệt kê tường minh được ưu tiên hơn `UTType` vì một số đuôi (ts, json, xml) bị UTType xếp nhóm khác.
    public static func classify(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if installerExts.contains(ext) { return .installers }
        if archiveExts.contains(ext) { return .archives }
        if documentExts.contains(ext) { return .documents }
        if codeExts.contains(ext) { return .code }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) || type.conforms(to: .plainText) || type.conforms(to: .rtf) { return .documents }
        if type.conforms(to: .sourceCode) { return .code }
        return .other
    }
}
