import SwiftUI
import SwiftData

struct TaskBlockEditor: View {
    @Environment(\.modelContext) private var modelContext

    let task: TaskBlock?
    let defaultStart: Date
    var defaultEnd: Date? = nil
    let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var selectedColorHex: String = "#007AFF"
    @State private var selectedRepeatRule: RepeatRule = .none
    @State private var showCustomRecurrenceSheet = false
    @State private var customInterval: Int = 1
    @State private var customUnit: RecurrenceUnit = .week
    @State private var customWeekdays: Set<Int> = []
    @State private var customEndDate: Date? = nil
    @State private var customOccurrenceLimit: Int = 0

    @FocusState private var titleFocused: Bool

    private static let presetColors: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Red", "#FF3B30"),
        ("Teal", "#5AC8FA"),
    ]

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: startTime)
    }

    private var weekdayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: startTime)
    }

    private var ordinalWeekdayLabel: String {
        let cal = Calendar.current
        let ordinal = cal.component(.weekdayOrdinal, from: startTime)
        let ordinalNames = ["first", "second", "third", "fourth", "fifth"]
        let ordinalStr = ordinal <= ordinalNames.count ? ordinalNames[ordinal - 1] : "\(ordinal)th"
        return "Monthly on the \(ordinalStr) \(weekdayName)"
    }

    private var annualLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d"
        return "Annually on \(fmt.string(from: startTime))"
    }

    private func repeatLabel(for rule: RepeatRule) -> String {
        switch rule {
        case .none: return "Does not repeat"
        case .daily: return "Daily"
        case .weeklyOnDay: return "Weekly on \(weekdayName)"
        case .monthlyOnOrdinal: return ordinalWeekdayLabel
        case .yearly: return annualLabel
        case .everyWeekday: return "Every weekday (Mon–Fri)"
        case .custom: return customSummaryLabel
        }
    }

    private var customSummaryLabel: String {
        let unitName = customInterval == 1 ? customUnit.displayName : "\(customInterval) \(customUnit.pluralDisplayName)"
        var label = "Every \(unitName)"

        if customUnit == .week && !customWeekdays.isEmpty {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let names = customWeekdays.sorted().compactMap { idx in
                (1...7).contains(idx) ? dayNames[idx - 1] : nil
            }
            if !names.isEmpty {
                label += " on \(names.joined(separator: ", "))"
            }
        }

        return label
    }

    private func prepopulateCustomFields() {
        switch selectedRepeatRule {
        case .daily:
            customInterval = 1; customUnit = .day; customWeekdays = []
        case .weeklyOnDay:
            customInterval = 1; customUnit = .week
            customWeekdays = [Calendar.current.component(.weekday, from: startTime)]
        case .monthlyOnOrdinal:
            customInterval = 1; customUnit = .month; customWeekdays = []
        case .yearly:
            customInterval = 1; customUnit = .year; customWeekdays = []
        case .everyWeekday:
            customInterval = 1; customUnit = .week; customWeekdays = [2, 3, 4, 5, 6]
        default:
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            TextField("Add title", text: $title)
                .textFieldStyle(.plain)
                .scaledFont(size: 18)
                .focused($titleFocused)
                .onSubmit { save() }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Date & Time row
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    DatePicker("", selection: Binding(
                        get: { startTime },
                        set: { newDate in
                            let cal = Calendar.current
                            let oldDay = cal.startOfDay(for: startTime)
                            let newDay = cal.startOfDay(for: newDate)
                            let shift = newDay.timeIntervalSince(oldDay)
                            startTime = startTime.addingTimeInterval(shift)
                            endTime = endTime.addingTimeInterval(shift)
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    HStack(spacing: 4) {
                        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(width: 90)

                        Text("–")
                            .scaledFont(size: 13)
                            .foregroundColor(.secondary)

                        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(width: 90)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)

            // Repeat picker
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Menu {
                    ForEach(RepeatRule.allCases.filter({ $0 != .custom }), id: \.self) { rule in
                        Button {
                            selectedRepeatRule = rule
                        } label: {
                            HStack {
                                Text(repeatLabel(for: rule))
                                if selectedRepeatRule == rule { Image(systemName: "checkmark") }
                            }
                        }
                    }

                    Divider()

                    Button {
                        if selectedRepeatRule != .custom {
                            prepopulateCustomFields()
                        }
                        showCustomRecurrenceSheet = true
                    } label: {
                        HStack {
                            Text(selectedRepeatRule == .custom ? customSummaryLabel : "Custom...")
                            if selectedRepeatRule == .custom { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(repeatLabel(for: selectedRepeatRule))
                            .scaledFont(size: 13)
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(size: 9)
                            .foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .sheet(isPresented: $showCustomRecurrenceSheet) {
                CustomRecurrenceSheet(
                    interval: customInterval,
                    unit: customUnit,
                    weekdays: customWeekdays,
                    endMode: customEndDate != nil ? .onDate : (customOccurrenceLimit > 0 ? .afterCount : .never),
                    endDate: customEndDate ?? Calendar.current.date(byAdding: .month, value: 1, to: startTime) ?? startTime,
                    occurrenceLimit: max(1, customOccurrenceLimit > 0 ? customOccurrenceLimit : 13),
                    onCancel: {
                        showCustomRecurrenceSheet = false
                    },
                    onSave: { interval, unit, weekdays, endDate, occurrenceLimit in
                        customInterval = interval
                        customUnit = unit
                        customWeekdays = weekdays
                        customEndDate = endDate
                        customOccurrenceLimit = occurrenceLimit
                        selectedRepeatRule = .custom
                        showCustomRecurrenceSheet = false
                    }
                )
            }

            Divider()
                .padding(.horizontal, 16)

            // Description
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                    .padding(.top, 2)

                TextField("Add description", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .scaledFont(size: 13)
                    .lineLimit(3...6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)

            // Color palette
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .scaledFont(size: 14)
                    .foregroundColor(Color(hex: selectedColorHex) ?? .blue)
                    .frame(width: 20)

                HStack(spacing: 8) {
                    ForEach(Self.presetColors, id: \.hex) { preset in
                        Circle()
                            .fill(Color(hex: preset.hex) ?? .blue)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: selectedColorHex == preset.hex ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColorHex = preset.hex
                            }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)

            // Buttons
            HStack {
                if task != nil {
                    Button("Delete", role: .destructive) {
                        deleteTask()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .scaledFont(size: 13)
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .scaledFont(size: 13)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        .onAppear {
            if let task {
                title = task.title
                note = task.note
                startTime = task.startTime
                endTime = task.endTime
                selectedColorHex = task.colorHex
                selectedRepeatRule = task.repeatRule
                if task.repeatRule == .custom {
                    customInterval = task.recurrenceInterval
                    customUnit = task.recurrenceUnitEnum
                    customWeekdays = task.recurrenceWeekdaySet
                    customEndDate = task.recurrenceEndDate
                    customOccurrenceLimit = task.recurrenceOccurrenceLimit
                }
            } else {
                startTime = defaultStart
                endTime = defaultEnd ?? (Calendar.current.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart)
            }
            titleFocused = true
        }
        .onExitCommand {
            onDismiss()
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let task {
            task.title = trimmed
            task.note = note
            task.startTime = startTime
            task.endTime = endTime
            task.colorHex = selectedColorHex
            task.repeatRule = selectedRepeatRule
            writeCustomFields(to: task)
        } else {
            let newTask = TaskBlock(
                title: trimmed,
                note: note,
                colorHex: selectedColorHex,
                startTime: startTime,
                endTime: endTime,
                repeatRule: selectedRepeatRule
            )
            writeCustomFields(to: newTask)
            modelContext.insert(newTask)
        }

        onDismiss()
    }

    private func writeCustomFields(to task: TaskBlock) {
        if selectedRepeatRule == .custom {
            task.recurrenceInterval = customInterval
            task.recurrenceUnitEnum = customUnit
            task.recurrenceWeekdaySet = customWeekdays
            task.recurrenceEndDate = customEndDate
            task.recurrenceOccurrenceLimit = customOccurrenceLimit
        } else {
            task.recurrenceInterval = 1
            task.recurrenceUnit = "week"
            task.recurrenceWeekdays = ""
            task.recurrenceEndDate = nil
            task.recurrenceOccurrenceLimit = 0
        }
    }

    private func deleteTask() {
        if let task {
            modelContext.delete(task)
        }
        onDismiss()
    }
}
