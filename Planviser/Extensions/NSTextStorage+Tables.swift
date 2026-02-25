import AppKit

extension NSTextStorage {

    func insertTable(rows: Int, columns: Int, at location: Int) {
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.hidesEmptyCells = false

        let result = NSMutableAttributedString()

        for row in 0..<rows {
            for col in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                block.setContentWidth(100 / CGFloat(columns), type: .percentageValueType)
                block.setWidth(4, type: .absoluteValueType, for: .padding)

                let paraStyle = NSMutableParagraphStyle()
                paraStyle.textBlocks = [block]

                let cellText = NSAttributedString(string: " \n", attributes: [
                    .paragraphStyle: paraStyle,
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.textColor
                ])
                result.append(cellText)
            }
        }

        // Add a trailing newline to exit the table
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]))

        beginEditing()
        replaceCharacters(in: NSRange(location: location, length: 0), with: result)
        endEditing()
    }

    func addTableRow(at cursorLocation: Int) {
        guard let (table, currentRow, _) = tableContext(at: cursorLocation) else { return }
        let cols = table.numberOfColumns
        let newRow = currentRow + 1

        // Find insertion point: end of last cell in current row
        let insertLocation = findRowEnd(table: table, row: currentRow, in: self)

        let result = NSMutableAttributedString()
        for col in 0..<cols {
            let block = NSTextTableBlock(table: table, startingRow: newRow, rowSpan: 1, startingColumn: col, columnSpan: 1)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setBorderColor(.separatorColor)
            block.setContentWidth(100 / CGFloat(cols), type: .percentageValueType)
            block.setWidth(4, type: .absoluteValueType, for: .padding)

            let paraStyle = NSMutableParagraphStyle()
            paraStyle.textBlocks = [block]

            let cellText = NSAttributedString(string: " \n", attributes: [
                .paragraphStyle: paraStyle,
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            result.append(cellText)
        }

        beginEditing()
        replaceCharacters(in: NSRange(location: insertLocation, length: 0), with: result)
        endEditing()
    }

    func addTableColumn(at cursorLocation: Int) {
        guard let (table, _, _) = tableContext(at: cursorLocation) else { return }
        table.numberOfColumns += 1
        // Rebuilding columns requires re-rendering; for simplicity notify change
    }

    func removeTableRow(at cursorLocation: Int) {
        guard let (table, currentRow, _) = tableContext(at: cursorLocation) else { return }
        let rowStart = findRowStart(table: table, row: currentRow, in: self)
        let rowEnd = findRowEnd(table: table, row: currentRow, in: self)
        guard rowEnd > rowStart else { return }

        beginEditing()
        replaceCharacters(in: NSRange(location: rowStart, length: rowEnd - rowStart), with: "")
        endEditing()
    }

    func removeTableColumn(at cursorLocation: Int) {
        guard let (table, _, _) = tableContext(at: cursorLocation) else { return }
        guard table.numberOfColumns > 1 else { return }
        table.numberOfColumns -= 1
    }

    // MARK: - Table Context Detection

    func tableContext(at location: Int) -> (NSTextTable, Int, Int)? {
        guard location < length else { return nil }
        let attrs = attributes(at: min(location, length - 1), effectiveRange: nil)
        guard let paraStyle = attrs[.paragraphStyle] as? NSParagraphStyle,
              let block = paraStyle.textBlocks.first as? NSTextTableBlock else {
            return nil
        }
        let row = block.startingRow
        let col = block.startingColumn
        return (block.table, row, col)
    }

    private func findRowStart(table: NSTextTable, row: Int, in storage: NSTextStorage) -> Int {
        var loc = 0
        while loc < storage.length {
            let attrs = storage.attributes(at: loc, effectiveRange: nil)
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle,
               let block = ps.textBlocks.first as? NSTextTableBlock,
               block.table === table && block.startingRow == row {
                return loc
            }
            let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(lineRange)
        }
        return loc
    }

    private func findRowEnd(table: NSTextTable, row: Int, in storage: NSTextStorage) -> Int {
        var loc = 0
        var rowEnd = 0
        var foundRow = false
        while loc < storage.length {
            let attrs = storage.attributes(at: loc, effectiveRange: nil)
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle,
               let block = ps.textBlocks.first as? NSTextTableBlock,
               block.table === table && block.startingRow == row {
                foundRow = true
            } else if foundRow {
                return loc
            }
            let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: loc, length: 0))
            rowEnd = NSMaxRange(lineRange)
            loc = rowEnd
        }
        return rowEnd
    }
}
