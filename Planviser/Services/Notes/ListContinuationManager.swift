import AppKit

enum ListType {
    case bullet
    case numbered(Int)
    case checklist(Bool)
    case textList(NSTextList)
}

struct ListContext {
    let type: ListType
    let lineRange: NSRange
    let prefixRange: NSRange
    let indentLevel: Int
    let isEmpty: Bool
}

struct ListContinuationManager {

    static func detectListType(in textStorage: NSTextStorage, at location: Int) -> ListContext? {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
        let lineText = string.substring(with: lineRange)
        let trimmed = lineText.trimmingCharacters(in: .newlines)

        // Calculate indent level from paragraph style
        var indentLevel = 0
        if lineRange.length > 0 {
            let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
            if let paraStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                indentLevel = Int(paraStyle.headIndent / 36)

                // Check NSTextList
                if let textList = paraStyle.textLists.last {
                    let contentStart = findContentStart(in: trimmed)
                    let isEmpty = String(trimmed.dropFirst(contentStart)).trimmingCharacters(in: .whitespaces).isEmpty
                    let prefixRange = NSRange(location: lineRange.location, length: contentStart)
                    return ListContext(
                        type: .textList(textList),
                        lineRange: lineRange,
                        prefixRange: prefixRange,
                        indentLevel: indentLevel,
                        isEmpty: isEmpty
                    )
                }
            }
        }

        // Check for checklist attachment
        if lineRange.length > 0 {
            var checkRange = NSRange(location: lineRange.location, length: 0)
            let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: &checkRange)
            if let attachment = attrs[.attachment] as? NSTextAttachment,
               let cell = attachment.attachmentCell as? ChecklistAttachmentCell {
                let afterAttachment = checkRange.location + checkRange.length
                let remaining = string.substring(with: NSRange(location: afterAttachment, length: lineRange.location + lineRange.length - afterAttachment))
                let isEmpty = remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return ListContext(
                    type: .checklist(cell.isChecked),
                    lineRange: lineRange,
                    prefixRange: NSRange(location: lineRange.location, length: checkRange.length),
                    indentLevel: indentLevel,
                    isEmpty: isEmpty
                )
            }
        }

        // Check plain bullet "• "
        if let range = trimmed.range(of: #"^\s*[\u{2022}\-\*]\s"#, options: .regularExpression) {
            let prefixLen = trimmed.distance(from: trimmed.startIndex, to: range.upperBound)
            let content = String(trimmed[range.upperBound...])
            let isEmpty = content.trimmingCharacters(in: .whitespaces).isEmpty
            return ListContext(
                type: .bullet,
                lineRange: lineRange,
                prefixRange: NSRange(location: lineRange.location, length: prefixLen),
                indentLevel: indentLevel,
                isEmpty: isEmpty
            )
        }

        // Check numbered "1. "
        if let range = trimmed.range(of: #"^\s*(\d+)\.\s"#, options: .regularExpression) {
            let prefixLen = trimmed.distance(from: trimmed.startIndex, to: range.upperBound)
            let numStr = String(trimmed[range]).trimmingCharacters(in: .whitespaces).components(separatedBy: ".").first ?? "1"
            let num = Int(numStr) ?? 1
            let content = String(trimmed[range.upperBound...])
            let isEmpty = content.trimmingCharacters(in: .whitespaces).isEmpty
            return ListContext(
                type: .numbered(num),
                lineRange: lineRange,
                prefixRange: NSRange(location: lineRange.location, length: prefixLen),
                indentLevel: indentLevel,
                isEmpty: isEmpty
            )
        }

        return nil
    }

    private static func findContentStart(in line: String) -> Int {
        // Skip leading whitespace and list marker characters
        var idx = line.startIndex
        // Skip whitespace
        while idx < line.endIndex && line[idx].isWhitespace { idx = line.index(after: idx) }
        // Skip list markers like "•", "-", "1.", tab
        if idx < line.endIndex {
            let ch = line[idx]
            if ch == "\u{2022}" || ch == "-" || ch == "*" {
                idx = line.index(after: idx)
                if idx < line.endIndex && (line[idx] == " " || line[idx] == "\t") {
                    idx = line.index(after: idx)
                }
            } else if ch.isNumber {
                var numEnd = idx
                while numEnd < line.endIndex && line[numEnd].isNumber { numEnd = line.index(after: numEnd) }
                if numEnd < line.endIndex && line[numEnd] == "." {
                    idx = line.index(after: numEnd)
                    if idx < line.endIndex && (line[idx] == " " || line[idx] == "\t") {
                        idx = line.index(after: idx)
                    }
                }
            }
        }
        return line.distance(from: line.startIndex, to: idx)
    }
}
