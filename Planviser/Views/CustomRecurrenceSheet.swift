import SwiftUI

struct CustomRecurrenceSheet: View {
    @State var interval: Int
    @State var unit: RecurrenceUnit
    @State var weekdays: Set<Int>
    @State var endMode: EndMode
    @State var endDate: Date
    @State var occurrenceLimit: Int

    let onCancel: () -> Void
    let onSave: (_ interval: Int, _ unit: RecurrenceUnit, _ weekdays: Set<Int>, _ endDate: Date?, _ occurrenceLimit: Int) -> Void

    enum EndMode: Hashable {
        case never, onDate, afterCount
    }

    private static let weekdaySymbols: [(index: Int, label: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Custom recurrence")
                .scaledFont(size: 15, weight: .semibold)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 16)

            // Repeat every N [unit]
            HStack(spacing: 8) {
                Text("Repeat every")
                    .scaledFont(size: 13)

                Stepper(value: $interval, in: 1...999) {
                    Text("\(interval)")
                        .scaledFont(size: 13, monospacedDigit: true)
                        .frame(minWidth: 24)
                }
                .fixedSize()

                Picker("", selection: $unit) {
                    ForEach(RecurrenceUnit.allCases, id: \.self) { u in
                        Text(interval == 1 ? u.displayName : u.pluralDisplayName).tag(u)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            // Weekday circles (only for weekly)
            if unit == .week {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Repeat on")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        ForEach(Self.weekdaySymbols, id: \.index) { wd in
                            Button {
                                if weekdays.contains(wd.index) {
                                    weekdays.remove(wd.index)
                                } else {
                                    weekdays.insert(wd.index)
                                }
                            } label: {
                                Text(wd.label)
                                    .scaledFont(size: 12, weight: .medium)
                                    .frame(width: 30, height: 30)
                                    .background(weekdays.contains(wd.index) ? Color.accentColor : Color.clear)
                                    .foregroundColor(weekdays.contains(wd.index) ? .white : .primary)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .strokeBorder(weekdays.contains(wd.index) ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }

            Divider()
                .padding(.horizontal, 16)

            // End conditions
            VStack(alignment: .leading, spacing: 8) {
                Text("Ends")
                    .scaledFont(size: 13)
                    .foregroundColor(.secondary)

                // Never
                HStack(spacing: 6) {
                    Image(systemName: endMode == .never ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(endMode == .never ? .accentColor : .secondary)
                        .scaledFont(size: 14)
                    Text("Never")
                        .scaledFont(size: 13)
                }
                .contentShape(Rectangle())
                .onTapGesture { endMode = .never }

                // On date
                HStack(spacing: 6) {
                    Image(systemName: endMode == .onDate ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(endMode == .onDate ? .accentColor : .secondary)
                        .scaledFont(size: 14)
                    Text("On")
                        .scaledFont(size: 13)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize()
                        .disabled(endMode != .onDate)
                        .opacity(endMode == .onDate ? 1.0 : 0.5)
                }
                .contentShape(Rectangle())
                .onTapGesture { endMode = .onDate }

                // After N occurrences
                HStack(spacing: 6) {
                    Image(systemName: endMode == .afterCount ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(endMode == .afterCount ? .accentColor : .secondary)
                        .scaledFont(size: 14)
                    Text("After")
                        .scaledFont(size: 13)
                    Stepper(value: $occurrenceLimit, in: 1...999) {
                        Text("\(occurrenceLimit)")
                            .scaledFont(size: 13, monospacedDigit: true)
                            .frame(minWidth: 24)
                    }
                    .fixedSize()
                    .disabled(endMode != .afterCount)
                    .opacity(endMode == .afterCount ? 1.0 : 0.5)
                    Text("occurrences")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { endMode = .afterCount }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .scaledFont(size: 13)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)

                Button("Done") {
                    let finalEndDate: Date? = endMode == .onDate ? endDate : nil
                    let finalLimit = endMode == .afterCount ? occurrenceLimit : 0
                    onSave(interval, unit, weekdays, finalEndDate, finalLimit)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
    }
}
