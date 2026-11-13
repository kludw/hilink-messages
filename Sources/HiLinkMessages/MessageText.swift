import Foundation
import SwiftUI

/// Things found inside a message's text: web links and verification codes.
enum MessageText {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The text with every web address turned into an underlined, clickable link.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let linkDetector else { return result }
        let matches = linkDetector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let stringRange = Range(match.range, in: text),
                  let range = Range(stringRange, in: result) else { continue }
            result[range].link = url
            result[range].underlineStyle = .single
        }
        return result
    }

    private static let codeWords = try? NSRegularExpression(
        pattern: #"\b(code|codes|otp|passcode|pin|verification|verify|password|one[- ]time|2fa|kod|kodu|kodem|hasło|código|codigo|codice|mot de passe)\b"#,
        options: [.caseInsensitive]
    )
    /// 4–8 digits, or two groups of three ("284 913", "284-913"), not part of a longer number.
    private static let codeDigits = try? NSRegularExpression(pattern: #"(?<![\d.,/])(\d{3}[ -]\d{3}|\d{4,8})(?![\d/]|[.,]\d)"#)

    /// The verification code in a message such as "Your one-time code is 284 913", without spaces.
    /// Only messages that talk about a code are considered, so amounts and account numbers are left alone.
    static func verificationCode(in text: String) -> String? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let codeWords, let codeDigits,
              codeWords.firstMatch(in: text, range: whole) != nil,
              let match = codeDigits.firstMatch(in: text, range: whole),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return text[range].filter(\.isNumber)
    }
}
