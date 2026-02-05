import CryptoKit
import Foundation

struct HashGenerator {
    static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        return sha256(data)
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate hash for clipboard content (used for deduplication)
    static func hashForClipContent(
        type: ContentType,
        text: String?,
        imageData: Data?,
        filePaths: [String]?
    ) -> String {
        switch type {
        case .text, .richText, .url, .color:
            return sha256(text ?? "")
        case .image:
            if let data = imageData {
                return sha256(data)
            }
            return sha256(UUID().uuidString)
        case .file:
            let joined = (filePaths ?? []).joined(separator: "|")
            return sha256(joined)
        }
    }
}
