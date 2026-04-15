import Foundation

enum NotificationTextSanitizer {
    private static let gb18030Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static let westernMojibakeScalars: Set<UnicodeScalar> = [
        "ð", "Ÿ", "â", "œ", "š", "ž", "™", "€", "œ", "�"
    ]

    static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let repair = repairGB18030Emoji(in: text, from: index)
                ?? repairWesternEmoji(in: text, from: index)
            {
                sanitized += repair.text
                index = repair.nextIndex
                continue
            }

            sanitized.append(text[index])
            index = text.index(after: index)
        }

        return sanitized
    }

    private static func repairGB18030Emoji(in text: String, from index: String.Index) -> Repair? {
        guard text[index] == "馃",
              let nextIndex = text.index(index, offsetBy: 2, limitedBy: text.endIndex)
        else { return nil }

        let candidate = String(text[index..<nextIndex])
        return repairedCandidate(candidate, using: gb18030Encoding).map {
            Repair(text: $0, nextIndex: nextIndex)
        }
    }

    private static func repairWesternEmoji(in text: String, from index: String.Index) -> Repair? {
        guard containsWesternMojibake(text[index]) else { return nil }

        for length in stride(from: 8, through: 3, by: -1) {
            guard let nextIndex = text.index(index, offsetBy: length, limitedBy: text.endIndex) else {
                continue
            }

            let candidate = String(text[index..<nextIndex])
            guard candidate.contains(where: containsWesternMojibake) else { continue }

            if let repaired = repairedCandidate(candidate, using: .windowsCP1252) {
                return Repair(text: repaired, nextIndex: nextIndex)
            }
        }

        return nil
    }

    private static func repairedCandidate(_ candidate: String, using encoding: String.Encoding) -> String? {
        guard let data = candidate.data(using: encoding),
              let repaired = String(data: data, encoding: .utf8),
              repaired != candidate,
              repaired.contains(where: isEmojiLike)
        else { return nil }

        return repaired
    }

    private static func containsWesternMojibake(_ character: Character) -> Bool {
        character.unicodeScalars.contains { westernMojibakeScalars.contains($0) }
    }

    private static func isEmojiLike(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            $0.properties.isEmoji && ($0.properties.isEmojiPresentation || $0.value > 0x238C)
        }
    }

    private struct Repair {
        let text: String
        let nextIndex: String.Index
    }
}
