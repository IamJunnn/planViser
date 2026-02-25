import SwiftUI
import AppKit

// MARK: - Custom NSTextView with keyboard shortcuts and list handling

final class AdaptiveTextView: NSTextView {
    weak var coordinator: RichTextEditor.Coordinator?

    // MARK: - Keyboard Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }

        let shift = event.modifierFlags.contains(.shift)

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b":
            coordinator?.toggleBold()
            return true
        case "i":
            coordinator?.toggleItalic()
            return true
        case "u":
            coordinator?.toggleUnderline()
            return true
        case "x" where shift:
            coordinator?.toggleStrikethrough()
            return true
        case "k":
            coordinator?.insertLink()
            return true
        case "l" where shift:
            coordinator?.toggleChecklist()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - List Continuation + Tab Indent

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let shift = event.modifierFlags.contains(.shift)

        // Enter key (36)
        if keyCode == 36 {
            if handleDividerShortcut() { return }
            if handleEnterForList() { return }
        }

        // Tab key (48)
        if keyCode == 48 {
            // Check if inside a table cell first
            if let storage = textStorage, storage.tableContext(at: selectedRange().location) != nil {
                navigateTableCell(forward: !shift)
                return
            }
            if shift {
                if handleOutdent() { return }
            } else {
                if handleIndent() { return }
            }
        }

        super.keyDown(with: event)
    }

    private func handleEnterForList() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        guard let ctx = ListContinuationManager.detectListType(in: storage, at: cursor) else { return false }

        if ctx.isEmpty {
            // Empty list line — remove the prefix and exit list mode
            storage.beginEditing()
            storage.replaceCharacters(in: ctx.lineRange, with: "\n")
            storage.endEditing()
            let newLoc = ctx.lineRange.location + 1
            setSelectedRange(NSRange(location: newLoc, length: 0))
            didChangeText()
            return true
        }

        // Continue list on next line
        var prefix: String
        switch ctx.type {
        case .bullet:
            prefix = "\u{2022} "
        case .numbered(let n):
            prefix = "\(n + 1). "
        case .checklist:
            // Insert a new checklist item via coordinator
            storage.beginEditing()
            storage.replaceCharacters(in: selectedRange(), with: NSAttributedString(string: "\n"))
            storage.endEditing()
            let newLoc = selectedRange().location + 1
            setSelectedRange(NSRange(location: newLoc, length: 0))
            didChangeText()
            coordinator?.insertChecklistAttachment(at: newLoc)
            return true
        case .textList:
            prefix = "\u{2022} "
        }

        let indent = String(repeating: "\t", count: ctx.indentLevel)
        let insertion = "\n\(indent)\(prefix)"
        insertText(insertion, replacementRange: selectedRange())
        return true
    }

    private func handleIndent() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        guard ListContinuationManager.detectListType(in: storage, at: cursor) != nil else { return false }

        let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: cursor, length: 0))
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: lineRange) { value, range, _ in
            let para = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            para.headIndent += 36
            para.firstLineHeadIndent += 36
            storage.addAttribute(.paragraphStyle, value: para, range: range)
        }
        storage.endEditing()
        didChangeText()
        return true
    }

    private func handleOutdent() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        guard ListContinuationManager.detectListType(in: storage, at: cursor) != nil else { return false }

        let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: cursor, length: 0))
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: lineRange) { value, range, _ in
            let para = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            para.headIndent = max(0, para.headIndent - 36)
            para.firstLineHeadIndent = max(0, para.firstLineHeadIndent - 36)
            storage.addAttribute(.paragraphStyle, value: para, range: range)
        }
        storage.endEditing()
        didChangeText()
        return true
    }

    // MARK: - Divider Shortcut (--- + Enter)

    private func handleDividerShortcut() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        let str = storage.string as NSString
        let lineRange = str.lineRange(for: NSRange(location: cursor, length: 0))
        let lineText = str.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)

        // Match dashes: "---", "——", "—-", or any mix of hyphens/em-dashes/en-dashes
        let dashChars: Set<Character> = ["-", "\u{2014}", "\u{2013}"]
        guard !lineText.isEmpty,
              lineText.allSatisfy({ dashChars.contains($0) }),
              lineText.count >= 2 else {
            return false
        }

        // Replace the line with a divider
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: NSAttributedString())

        let divider = Self.makeDividerAttributedString()
        storage.insert(divider, at: lineRange.location)
        storage.endEditing()

        setSelectedRange(NSRange(location: lineRange.location + divider.length, length: 0))
        didChangeText()
        return true
    }

    static func makeDividerAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let attachment = NSTextAttachment()
        attachment.attachmentCell = DividerAttachmentCell()

        let attachStr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        attachStr.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]))

        result.append(attachStr)
        return result
    }

    // MARK: - Table Cell Navigation

    private func navigateTableCell(forward: Bool) {
        guard let storage = textStorage else { return }
        let str = storage.string as NSString
        let cursor = selectedRange().location

        if forward {
            // Find next paragraph (next cell)
            let lineRange = str.lineRange(for: NSRange(location: cursor, length: 0))
            let nextLoc = NSMaxRange(lineRange)
            if nextLoc < storage.length {
                setSelectedRange(NSRange(location: nextLoc, length: 0))
            }
        } else {
            // Find previous paragraph start
            if cursor > 0 {
                let prevLineRange = str.lineRange(for: NSRange(location: max(0, cursor - 1), length: 0))
                setSelectedRange(NSRange(location: prevLineRange.location, length: 0))
            }
        }
    }

    // MARK: - Paste handling

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // 1. Try RTFD (rich text with attachments)
        if let rtfdData = pb.data(forType: .rtfd),
           let pasted = NSMutableAttributedString(rtfd: rtfdData, documentAttributes: nil) {
            normalizeAndInsert(pasted)
            return
        }

        // 2. Try RTF
        if let rtfData = pb.data(forType: .rtf),
           let pasted = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil) {
            normalizeAndInsert(pasted)
            return
        }

        // 3. Try HTML (Apple Notes uses this)
        if let htmlData = pb.data(forType: .html),
           let pasted = NSMutableAttributedString(html: htmlData, documentAttributes: nil) {
            normalizeAndInsert(pasted)
            return
        }

        // 4. Try plain text (always prefer text over image)
        if let plainString = pb.string(forType: .string), !plainString.isEmpty {
            let pasted = NSAttributedString(string: plainString, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            let insertRange = selectedRange()
            textStorage?.replaceCharacters(in: insertRange, with: pasted)
            setSelectedRange(NSRange(location: insertRange.location + pasted.length, length: 0))
            didChangeText()
            return
        }

        // 5. Fall back to super only for actual images / other content
        super.paste(sender)
    }

    private func normalizeAndInsert(_ pasted: NSMutableAttributedString) {
        AdaptiveTextView.normalizeColors(pasted)
        let insertRange = selectedRange()
        textStorage?.replaceCharacters(in: insertRange, with: pasted)
        setSelectedRange(NSRange(location: insertRange.location + pasted.length, length: 0))
        didChangeText()
    }

    static func normalizeColors(_ attrString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attrString.length)
        // Replace all foreground colors with adaptive system text color
        attrString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        // Adaptive tint for table/code-block backgrounds
        // Uses system quaternary label color which adapts to light/dark automatically
        let adaptiveTint = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)

        attrString.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let converted = color.usingColorSpace(.deviceRGB) ?? color
            let r = converted.redComponent
            let g = converted.greenComponent
            let b = converted.blueComponent
            let brightness = converted.brightnessComponent
            let saturation = converted.saturationComponent

            if saturation > 0.3 {
                // Colorful highlight (yellow, blue, etc.) — keep as-is
                return
            }

            if brightness > 0.85 || brightness < 0.15 {
                // Near-white or near-black page background — remove entirely
                attrString.removeAttribute(.backgroundColor, range: range)
            } else if saturation < 0.1 && (r == g && g == b || abs(r - g) < 0.05 && abs(g - b) < 0.05) {
                // Gray-ish backgrounds (tables, code blocks) — convert to adaptive tint
                attrString.addAttribute(.backgroundColor, value: adaptiveTint, range: range)
            }
        }
    }

    // MARK: - Double-click sketch attachment

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndexForInsertion(at: point)
            if charIndex < (textStorage?.length ?? 0),
               let attachment = textStorage?.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
               attachment.image != nil {
                coordinator?.editInlineSketch(at: charIndex, attachment: attachment)
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        if let storage = textStorage, storage.tableContext(at: charIndex) != nil {
            baseMenu.addItem(.separator())
            let addRow = NSMenuItem(title: "Add Row Below", action: #selector(contextAddTableRow(_:)), keyEquivalent: "")
            addRow.tag = charIndex
            addRow.target = self
            baseMenu.addItem(addRow)

            let addCol = NSMenuItem(title: "Add Column", action: #selector(contextAddTableColumn(_:)), keyEquivalent: "")
            addCol.tag = charIndex
            addCol.target = self
            baseMenu.addItem(addCol)

            let removeRow = NSMenuItem(title: "Remove Row", action: #selector(contextRemoveTableRow(_:)), keyEquivalent: "")
            removeRow.tag = charIndex
            removeRow.target = self
            baseMenu.addItem(removeRow)

            let removeCol = NSMenuItem(title: "Remove Column", action: #selector(contextRemoveTableColumn(_:)), keyEquivalent: "")
            removeCol.tag = charIndex
            removeCol.target = self
            baseMenu.addItem(removeCol)
        }

        return baseMenu
    }

    @objc private func contextAddTableRow(_ sender: NSMenuItem) {
        textStorage?.addTableRow(at: sender.tag)
        didChangeText()
    }

    @objc private func contextAddTableColumn(_ sender: NSMenuItem) {
        textStorage?.addTableColumn(at: sender.tag)
        didChangeText()
    }

    @objc private func contextRemoveTableRow(_ sender: NSMenuItem) {
        textStorage?.removeTableRow(at: sender.tag)
        didChangeText()
    }

    @objc private func contextRemoveTableColumn(_ sender: NSMenuItem) {
        textStorage?.removeTableColumn(at: sender.tag)
        didChangeText()
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var onTextChange: (() -> Void)?
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = AdaptiveTextView()

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        // Configure text view
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesRuler = false
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        // Ensure new typed text always uses adaptive color
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]

        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        context.coordinator.textView = textView

        if attributedText.length > 0 {
            // Normalize colors on load so stored content adapts to dark/light mode
            let mutable = NSMutableAttributedString(attributedString: attributedText)
            AdaptiveTextView.normalizeColors(mutable)
            textView.textStorage?.setAttributedString(mutable)
        }

        textView.registerForDraggedTypes([.fileURL, .png, .tiff])

        // Listen for checklist toggles
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleChecklistToggle(_:)),
            name: .checklistToggled,
            object: nil
        )

        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Avoid feedback loop: only update if text actually differs
        if !context.coordinator.isUpdating,
           textView.attributedString() != attributedText {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isUpdating = false
        weak var textView: NSTextView?
        var sketchPopover: NSPopover?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.attributedText = textView.attributedString()
            parent.onTextChange?()
            isUpdating = false
        }

        // MARK: - Undo-aware editing helper

        private func performUndoableEdit(in range: NSRange, block: (NSTextStorage) -> Void) {
            guard let textView, let storage = textView.textStorage else { return }
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            block(storage)
            storage.endEditing()
            textView.didChangeText()
            notifyChange()
        }

        // MARK: - Formatting Actions

        func toggleBold() {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                var attrs = textView.typingAttributes
                let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    attrs[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                textView.typingAttributes = attrs
                return
            }
            performUndoableEdit(in: range) { storage in
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    guard let font = value as? NSFont else { return }
                    let newFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(.bold) {
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    } else {
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
        }

        func toggleItalic() {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                var attrs = textView.typingAttributes
                let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    attrs[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                textView.typingAttributes = attrs
                return
            }
            performUndoableEdit(in: range) { storage in
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    guard let font = value as? NSFont else { return }
                    let newFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(.italic) {
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    } else {
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
        }

        func toggleUnderline() {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                var attrs = textView.typingAttributes
                let current = (attrs[.underlineStyle] as? Int) ?? 0
                attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                textView.typingAttributes = attrs
                return
            }
            performUndoableEdit(in: range) { storage in
                storage.enumerateAttribute(.underlineStyle, in: range) { value, attrRange, _ in
                    let current = (value as? Int) ?? 0
                    let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                    storage.addAttribute(.underlineStyle, value: newValue, range: attrRange)
                }
            }
        }

        func toggleStrikethrough() {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                var attrs = textView.typingAttributes
                let current = (attrs[.strikethroughStyle] as? Int) ?? 0
                attrs[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                textView.typingAttributes = attrs
                return
            }
            performUndoableEdit(in: range) { storage in
                storage.enumerateAttribute(.strikethroughStyle, in: range) { value, attrRange, _ in
                    let current = (value as? Int) ?? 0
                    let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                    storage.addAttribute(.strikethroughStyle, value: newValue, range: attrRange)
                }
            }
        }

        func applyHeading(_ style: HeadingStyle) {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let font = style.font
            performUndoableEdit(in: range) { storage in
                storage.addAttribute(.font, value: font, range: range)
            }
        }

        func applyHighlight(_ color: NSColor?) {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            performUndoableEdit(in: range) { storage in
                if let color {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                } else {
                    storage.removeAttribute(.backgroundColor, range: range)
                }
            }
        }

        func applyFontColor(_ color: NSColor) {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            performUndoableEdit(in: range) { storage in
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        // MARK: - Lists

        func insertBulletList() {
            guard let textView else { return }
            let para = NSMutableParagraphStyle()
            let textList = NSTextList(markerFormat: .disc, options: 0)
            para.textLists = [textList]
            para.headIndent = 36
            para.firstLineHeadIndent = 18

            let insertion = NSAttributedString(string: "\n\u{2022}\t", attributes: [
                .paragraphStyle: para,
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            textView.textStorage?.insert(insertion, at: textView.selectedRange().location)
            textView.setSelectedRange(NSRange(location: textView.selectedRange().location + insertion.length, length: 0))
            textView.didChangeText()
            notifyChange()
        }

        func insertNumberedList() {
            guard let textView else { return }
            let para = NSMutableParagraphStyle()
            let textList = NSTextList(markerFormat: .decimal, options: 0)
            para.textLists = [textList]
            para.headIndent = 36
            para.firstLineHeadIndent = 18

            let insertion = NSAttributedString(string: "\n1.\t", attributes: [
                .paragraphStyle: para,
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            textView.textStorage?.insert(insertion, at: textView.selectedRange().location)
            textView.setSelectedRange(NSRange(location: textView.selectedRange().location + insertion.length, length: 0))
            textView.didChangeText()
            notifyChange()
        }

        // MARK: - Checklist

        func toggleChecklist() {
            guard let textView, let storage = textView.textStorage else { return }
            let cursor = textView.selectedRange().location

            // If already on a checklist line, remove the attachment
            if let ctx = ListContinuationManager.detectListType(in: storage, at: cursor),
               case .checklist = ctx.type {
                storage.beginEditing()
                storage.replaceCharacters(in: ctx.prefixRange, with: "")
                storage.endEditing()
                textView.didChangeText()
                notifyChange()
                return
            }

            // Insert new checklist item
            let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: cursor, length: 0))
            insertChecklistAttachment(at: lineRange.location)
        }

        func insertChecklistAttachment(at location: Int) {
            guard let textView, let storage = textView.textStorage else { return }

            let cell = ChecklistAttachmentCell()
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell

            let attrStr = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            attrStr.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ]))

            storage.beginEditing()
            storage.insert(attrStr, at: location)
            storage.endEditing()
            textView.setSelectedRange(NSRange(location: location + attrStr.length, length: 0))
            textView.didChangeText()
            notifyChange()
        }

        @objc func handleChecklistToggle(_ notification: Notification) {
            guard let cell = notification.object as? ChecklistAttachmentCell,
                  let textView, let storage = textView.textStorage else { return }

            // Find the attachment in the text and toggle strikethrough on its line
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.attachment, in: fullRange) { value, range, stop in
                guard let attachment = value as? NSTextAttachment,
                      attachment.attachmentCell === cell else { return }

                let lineRange = (storage.string as NSString).lineRange(for: range)
                let afterAttachment = NSRange(location: range.location + range.length, length: lineRange.location + lineRange.length - range.location - range.length)
                guard afterAttachment.length > 0 else { return }

                storage.beginEditing()
                if cell.isChecked {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: afterAttachment)
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: afterAttachment)
                } else {
                    storage.removeAttribute(.strikethroughStyle, range: afterAttachment)
                    storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: afterAttachment)
                }
                storage.endEditing()
                textView.needsDisplay = true
                notifyChange()
                stop.pointee = true
            }
        }

        // MARK: - Divider

        func insertDivider() {
            guard let textView, let storage = textView.textStorage else { return }
            let divider = AdaptiveTextView.makeDividerAttributedString()
            let loc = textView.selectedRange().location
            storage.beginEditing()
            storage.insert(divider, at: loc)
            storage.endEditing()
            textView.setSelectedRange(NSRange(location: loc + divider.length, length: 0))
            textView.didChangeText()
            notifyChange()
        }

        // MARK: - Tables

        func insertTable(rows: Int, columns: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            storage.insertTable(rows: rows, columns: columns, at: textView.selectedRange().location)
            textView.didChangeText()
            notifyChange()
        }

        // MARK: - Images

        func insertImage() {
            guard let textView else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            guard panel.runModal() == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url) else { return }

            let attachment = NSTextAttachment()
            let wrapper = FileWrapper(regularFileWithContents: image.tiffRepresentation ?? Data())
            wrapper.preferredFilename = url.lastPathComponent
            attachment.fileWrapper = wrapper
            attachment.image = image

            let attrString = NSAttributedString(attachment: attachment)
            textView.textStorage?.insert(attrString, at: textView.selectedRange().location)
            notifyChange()
        }

        func insertLink() {
            guard let textView else { return }
            let range = textView.selectedRange()
            let selectedText = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""

            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")

            let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
            stackView.orientation = .vertical
            stackView.spacing = 6

            let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            urlField.placeholderString = "https://example.com"

            let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            titleField.placeholderString = "Link text"
            titleField.stringValue = selectedText

            stackView.addArrangedSubview(titleField)
            stackView.addArrangedSubview(urlField)

            alert.accessoryView = stackView

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let urlString = urlField.stringValue
            guard let url = URL(string: urlString) else { return }

            let linkText = titleField.stringValue.isEmpty ? urlString : titleField.stringValue
            let linkAttr = NSAttributedString(string: linkText, attributes: [
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 14)
            ])

            textView.textStorage?.replaceCharacters(in: range, with: linkAttr)
            notifyChange()
        }

        // MARK: - Inline Sketch

        func insertInlineSketch() {
            guard let textView else { return }
            let blankImage = NSImage(size: NSSize(width: 500, height: 300))
            blankImage.lockFocus()
            NSColor.textBackgroundColor.setFill()
            NSRect(origin: .zero, size: blankImage.size).fill()
            blankImage.unlockFocus()

            showSketchPopover(for: nil, image: blankImage, at: textView.selectedRange().location)
        }

        func editInlineSketch(at charIndex: Int, attachment: NSTextAttachment) {
            guard let image = attachment.image else { return }
            showSketchPopover(for: charIndex, image: image, at: charIndex)
        }

        private func showSketchPopover(for existingIndex: Int?, image: NSImage, at location: Int) {
            guard let textView else { return }

            let popover = NSPopover()
            popover.behavior = .transient

            let sketchView = InlineSketchView(
                initialImage: image,
                onDone: { [weak self] resultImage in
                    popover.close()
                    self?.handleSketchDone(resultImage: resultImage, existingIndex: existingIndex, at: location)
                },
                onCancel: {
                    popover.close()
                }
            )

            let hostingController = NSHostingController(rootView: sketchView)
            hostingController.preferredContentSize = NSSize(width: 520, height: 360)
            popover.contentViewController = hostingController

            let glyphRange = textView.layoutManager?.glyphRange(forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil) ?? NSRange(location: 0, length: 0)
            let rect = textView.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!) ?? NSRect(x: 0, y: 0, width: 1, height: 20)
            popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            self.sketchPopover = popover
        }

        private func handleSketchDone(resultImage: NSImage, existingIndex: Int?, at location: Int) {
            guard let textView, let storage = textView.textStorage else { return }

            let attachment = NSTextAttachment()
            let wrapper = FileWrapper(regularFileWithContents: resultImage.tiffRepresentation ?? Data())
            wrapper.preferredFilename = "sketch.tiff"
            attachment.fileWrapper = wrapper
            attachment.image = resultImage

            let attrString = NSAttributedString(attachment: attachment)

            storage.beginEditing()
            if let idx = existingIndex {
                // Replace existing attachment
                storage.replaceCharacters(in: NSRange(location: idx, length: 1), with: attrString)
            } else {
                // Insert new
                storage.insert(attrString, at: location)
            }
            storage.endEditing()
            textView.didChangeText()
            notifyChange()
        }

        private func notifyChange() {
            guard let textView else { return }
            isUpdating = true
            parent.attributedText = textView.attributedString()
            parent.onTextChange?()
            isUpdating = false
        }
    }
}

// MARK: - Heading Style

enum HeadingStyle: String, CaseIterable, Identifiable {
    case title = "Title"
    case heading = "Heading"
    case subheading = "Subheading"
    case body = "Body"

    var id: String { rawValue }

    var font: NSFont {
        switch self {
        case .title: return .boldSystemFont(ofSize: 24)
        case .heading: return .boldSystemFont(ofSize: 18)
        case .subheading: return .systemFont(ofSize: 16, weight: .semibold)
        case .body: return .systemFont(ofSize: 14)
        }
    }
}
