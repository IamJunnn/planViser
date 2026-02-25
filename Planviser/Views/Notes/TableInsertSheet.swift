import SwiftUI

struct TableInsertSheet: View {
    @State private var rows = 3
    @State private var columns = 3
    var onInsert: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Insert Table")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Rows")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Stepper("\(rows)", value: $rows, in: 1...20)
                        .font(.system(size: 12))
                        .frame(width: 80)
                }

                HStack(spacing: 6) {
                    Text("Cols")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Stepper("\(columns)", value: $columns, in: 1...10)
                        .font(.system(size: 12))
                        .frame(width: 80)
                }
            }

            HStack(spacing: 8) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Insert") {
                    onInsert(rows, columns)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
