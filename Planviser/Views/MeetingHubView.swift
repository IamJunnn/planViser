import SwiftUI
import SwiftData

struct MeetingHubView: View {
    @Query(sort: \MeetingInvite.startTime)
    private var allMeetings: [MeetingInvite]

    @Query(sort: \TaskBlock.startTime)
    private var allTasks: [TaskBlock]

    @Query private var accounts: [EmailAccount]

    @Environment(\.modelContext) private var modelContext

    @State private var displayedMonth = Date.now
    @State private var selectedDate: Date? = nil
    @State private var popoverMeeting: MeetingInvite?

    private var grid: [[Date?]] {
        CalendarHelpers.calendarGrid(for: displayedMonth)
    }

    private var meetingsByDay: [String: [MeetingInvite]] {
        var dict: [String: [MeetingInvite]] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for meeting in allMeetings {
            let key = fmt.string(from: meeting.startTime)
            dict[key, default: []].append(meeting)
        }
        return dict
    }

    private func taskOccurrencesFor(_ date: Date) -> [TaskOccurrence] {
        RecurrenceEngine.allOccurrences(tasks: allTasks, on: date)
    }

    private var accountColors: [String: Color] {
        var map: [String: Color] = [:]
        for account in accounts {
            map[account.email] = account.color
        }
        return map
    }

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack(spacing: 0) {
            // Left: full-height calendar
            VStack(spacing: 0) {
                // Month navigation
                HStack {
                    Button {
                        displayedMonth = CalendarHelpers.offsetMonth(displayedMonth, by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)

                    Text(CalendarHelpers.monthTitle(for: displayedMonth))
                        .scaledFont(.headline)
                        .frame(minWidth: 160)

                    Button {
                        displayedMonth = CalendarHelpers.offsetMonth(displayedMonth, by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Today") {
                        displayedMonth = Date.now
                        selectedDate = Date.now
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Weekday headers
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .scaledFont(.caption2, weight: .medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)

                // Calendar grid
                VStack(spacing: 0) {
                    ForEach(grid.indices, id: \.self) { row in
                        let week = grid[row]
                        if week.contains(where: { $0 != nil }) {
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { col in
                                    if let date = week[col] {
                                        CalendarDayCell(
                                            date: date,
                                            meetings: meetingsFor(date),
                                            taskOccurrences: taskOccurrencesFor(date),
                                            accountColors: accountColors,
                                            popoverMeeting: $popoverMeeting,
                                            modelContext: modelContext,
                                            isSelected: selectedDate.map { CalendarHelpers.isSameDay($0, date) } ?? false,
                                            isToday: CalendarHelpers.isSameDay(date, Date.now)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedDate = date }
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .frame(maxHeight: .infinity)

                            if row < grid.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                Spacer()
            }

            // Right: detail panel (slides in when a date is selected)
            if selectedDate != nil {
                Divider()

                DayDetailPanel(
                    selectedDate: $selectedDate,
                    meetings: selectedDate.map { meetingsFor($0) } ?? [],
                    taskOccurrences: selectedDate.map { taskOccurrencesFor($0) } ?? [],
                    accountColors: accountColors,
                    modelContext: modelContext
                )
                .id(selectedDate)
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            EmailSyncService.shared.syncGoogleCalendar(modelContext: modelContext)
        }
    }

    private func meetingsFor(_ date: Date) -> [MeetingInvite] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return meetingsByDay[fmt.string(from: date)] ?? []
    }

}

// MARK: - CalendarDayCell

struct CalendarDayCell: View {
    let date: Date
    let meetings: [MeetingInvite]
    var taskOccurrences: [TaskOccurrence] = []
    let accountColors: [String: Color]
    @Binding var popoverMeeting: MeetingInvite?
    let modelContext: ModelContext
    let isSelected: Bool
    let isToday: Bool

    // Each pill is 18pt tall + 3pt spacing
    private static let pillHeight: CGFloat = 21
    private static let dayNumberHeight: CGFloat = 24
    private static let overflowBadgeHeight: CGFloat = 16

    private var totalItems: Int { meetings.count + taskOccurrences.count }

    private func maxVisibleItems(in height: CGFloat) -> Int {
        let available = height - Self.dayNumberHeight - 4
        if totalItems <= 1 { return totalItems }
        let withBadge = Int((available - Self.overflowBadgeHeight) / Self.pillHeight)
        let withoutBadge = Int(available / Self.pillHeight)
        if totalItems <= withoutBadge {
            return totalItems
        }
        return max(1, withBadge)
    }

    /// Merged list of meetings + tasks sorted by start time
    private var sortedItems: [(isMeeting: Bool, meetingIndex: Int?, taskIndex: Int?, startTime: Date)] {
        var items: [(isMeeting: Bool, meetingIndex: Int?, taskIndex: Int?, startTime: Date)] = []
        for (i, m) in meetings.enumerated() {
            items.append((true, i, nil, m.startTime))
        }
        for (i, t) in taskOccurrences.enumerated() {
            items.append((false, nil, i, t.startTime))
        }
        return items.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        GeometryReader { geo in
            let sorted = sortedItems
            let maxVisible = maxVisibleItems(in: geo.size.height)
            let overflow = sorted.count - maxVisible

            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .scaledFont(.caption2, weight: isToday ? .bold : .regular)
                    .foregroundColor(isToday ? .white : .primary)
                    .padding(3)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())

                VStack(spacing: 3) {
                    ForEach(0..<maxVisible, id: \.self) { idx in
                        let item = sorted[idx]
                        if item.isMeeting, let mi = item.meetingIndex {
                            MeetingPill(
                                meeting: meetings[mi],
                                accountColors: accountColors,
                                popoverMeeting: $popoverMeeting,
                                modelContext: modelContext
                            )
                        } else if let ti = item.taskIndex {
                            TaskPill(occurrence: taskOccurrences[ti])
                        }
                    }
                }

                if overflow > 0 {
                    Text("+\(overflow) more")
                        .scaledFont(size: 9, weight: .medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .border(Color(nsColor: .separatorColor).opacity(0.3), width: 0.5)
    }
}

// MARK: - TaskPill

struct TaskPill: View {
    let occurrence: TaskOccurrence

    @State private var isHovered = false

    private var task: TaskBlock { occurrence.sourceTask }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: occurrence.startTime)
    }

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(task.color)
                .frame(width: 3)

            Text("\(timeString) \(task.title)")
                .scaledFont(size: 10)
                .lineLimit(1)
                .foregroundColor(occurrence.isDone ? .secondary : .primary)
                .strikethrough(occurrence.isDone)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovered ? task.color.opacity(0.15) : task.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(task.color.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - MeetingPill

struct MeetingPill: View {
    let meeting: MeetingInvite
    var accountColors: [String: Color] = [:]
    @Binding var popoverMeeting: MeetingInvite?
    let modelContext: ModelContext

    @State private var isHovered = false

    private var accountColor: Color {
        if !meeting.accountEmail.isEmpty, let color = accountColors[meeting.accountEmail] {
            return color
        }
        return meeting.sourceMessage?.account?.color ?? .gray
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mma"
        fmt.amSymbol = "am"
        fmt.pmSymbol = "pm"
        return fmt.string(from: meeting.startTime)
    }

    private var isShowingPopover: Binding<Bool> {
        Binding(
            get: { popoverMeeting?.id == meeting.id },
            set: { if !$0 { popoverMeeting = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accountColor)
                .frame(width: 3)

            Text("\(timeString) \(meeting.title)")
                .scaledFont(size: 10)
                .lineLimit(1)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovered ? accountColor.opacity(0.2) : accountColor.opacity(0.08))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            popoverMeeting = meeting
        }
        .popover(isPresented: isShowingPopover, arrowEdge: .trailing) {
            MeetingPopoverView(
                meeting: meeting,
                accountColor: accountColor,
                modelContext: modelContext,
                onDismiss: { popoverMeeting = nil }
            )
        }
    }
}

// MARK: - MeetingPopoverView

struct MeetingPopoverView: View {
    let meeting: MeetingInvite
    let accountColor: Color
    let modelContext: ModelContext
    let onDismiss: () -> Void

    private var dateTimeString: String {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE, MMMM d"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "h:mma"
        endFmt.amSymbol = "am"
        endFmt.pmSymbol = "pm"
        return "\(dayFmt.string(from: meeting.startTime))  ·  \(timeFmt.string(from: meeting.startTime)) – \(endFmt.string(from: meeting.endTime))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar with close button
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
            .padding(.top, 8)

            // Title with color dot
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accountColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .scaledFont(size: 16, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(dateTimeString)
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            Divider()
                .padding(.vertical, 10)

            // Organizer
            if !meeting.organizer.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Text(meeting.organizer)
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Location
            if !meeting.location.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Text(meeting.location)
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Video link
            if !meeting.videoLink.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "video")
                        .scaledFont(size: 13)
                        .foregroundColor(.blue)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            if let url = URL(string: meeting.videoLink) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Join Video Call")
                                .scaledFont(size: 12, weight: .medium)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)

                        Text(meeting.videoLink)
                            .scaledFont(size: 10)
                            .foregroundColor(.blue.opacity(0.7))
                            .lineLimit(2)
                            .onTapGesture {
                                if let url = URL(string: meeting.videoLink) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Description
            if !meeting.meetingDescription.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    DescriptionTextView(text: meeting.meetingDescription)
                        .scaledFont(size: 12)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()
                .padding(.vertical, 6)

            // Response buttons
            HStack {
                Text("Going?")
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    responseButton("Yes", response: .accepted, color: .green)
                    responseButton("No", response: .declined, color: .red)
                    responseButton("Maybe", response: .tentative, color: .orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
    }

    private func responseButton(_ label: String, response: MeetingResponse, color: Color) -> some View {
        let isActive = meeting.responseStatus == response

        return Button {
            MeetingResponseService.shared.respond(
                to: meeting, with: response, modelContext: modelContext
            )
        } label: {
            Text(label)
                .scaledFont(size: 11, weight: isActive ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? color : Color.clear)
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DescriptionTextView

struct DescriptionTextView: View {
    let text: String

    // Strip HTML tags that Google Calendar API may include
    private var cleanText: String {
        var result = text
        // Replace <br> and <br/> with newlines
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        // Replace </p>, </div> with newlines
        result = result.replacingOccurrences(of: "</(?:p|div)>", with: "\n", options: .regularExpression)
        // Strip remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse multiple newlines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let urlPattern = try! NSRegularExpression(
        pattern: "https?://[^\\s<>\"]+",
        options: .caseInsensitive
    )

    var body: some View {
        let cleaned = cleanText
        let urls = Self.urlPattern.matches(
            in: cleaned,
            range: NSRange(cleaned.startIndex..., in: cleaned)
        )

        if urls.isEmpty {
            Text(cleaned)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(cleaned)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                ForEach(urls, id: \.range.location) { match in
                    if let range = Range(match.range, in: cleaned) {
                        let urlString = String(cleaned[range])
                        Button {
                            if let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text(urlString)
                                .scaledFont(size: 11)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - DayDetailPanel

struct DayDetailPanel: View {
    @Binding var selectedDate: Date?
    let meetings: [MeetingInvite]
    var taskOccurrences: [TaskOccurrence] = []
    let accountColors: [String: Color]
    let modelContext: ModelContext

    @State private var popoverMeeting: MeetingInvite?
    @State private var editingTask: TaskBlock?
    @State private var isCreatingTask = false
    @State private var newTaskStartDate: Date = Date()
    @State private var newTaskEndDate: Date = Date()
    @State private var isDraggingToCreate = false
    @State private var dragPreviewStart: Date? = nil
    @State private var dragPreviewEnd: Date? = nil

    // Timeline config
    private let startHour = 0    // midnight
    private let endHour = 24     // end of day
    private let hourHeight: CGFloat = 52

    private var totalHeight: CGFloat {
        CGFloat(endHour - startHour) * hourHeight
    }

    private var isToday: Bool {
        guard let date = selectedDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var hasItems: Bool {
        !meetings.isEmpty || !taskOccurrences.isEmpty
    }

    private var subtitleText: String {
        let m = meetings.count
        let t = taskOccurrences.count
        var parts: [String] = []
        if m > 0 { parts.append("\(m) meeting\(m == 1 ? "" : "s")") }
        if t > 0 { parts.append("\(t) task\(t == 1 ? "" : "s")") }
        return parts.isEmpty ? "No items" : parts.joined(separator: ", ")
    }

    /// Earliest item hour (floored) to auto-scroll to
    private var scrollToHour: Int {
        if isToday {
            return max(startHour, Calendar.current.component(.hour, from: Date.now) - 1)
        }
        let meetingFirst = meetings.min(by: { $0.startTime < $1.startTime })?.startTime
        let taskFirst = taskOccurrences.min(by: { $0.startTime < $1.startTime })?.startTime
        let earliest: Date? = [meetingFirst, taskFirst].compactMap { $0 }.min()
        guard let first = earliest else { return 8 }
        return max(startHour, Calendar.current.component(.hour, from: first) - 1)
    }

    var body: some View {
        if let date = selectedDate {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date, style: .date)
                            .scaledFont(.subheadline, weight: .semibold)
                        Text(subtitleText)
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button {
                        let cal = Calendar.current
                        let hour = cal.component(.hour, from: Date.now)
                        let snapped = cal.date(bySettingHour: hour, minute: hour == 23 ? 30 : 0, second: 0, of: date) ?? date
                        newTaskStartDate = snapped
                        newTaskEndDate = cal.date(byAdding: .hour, value: 1, to: snapped) ?? snapped
                        isCreatingTask = true
                    } label: {
                        Image(systemName: "plus")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isCreatingTask) {
                        TaskBlockEditor(
                            task: nil,
                            defaultStart: newTaskStartDate,
                            defaultEnd: newTaskEndDate,
                            onDismiss: { isCreatingTask = false }
                        )
                        .environment(\.modelContext, modelContext)
                    }

                    Button {
                        selectedDate = nil
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                if !hasItems {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .scaledFont(size: 24)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No meetings or tasks")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            let cal = Calendar.current
                            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                            newTaskStartDate = start
                            newTaskEndDate = cal.date(byAdding: .hour, value: 1, to: start) ?? start
                            isCreatingTask = true
                        } label: {
                            Text("Add a task")
                                .scaledFont(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Timeline
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                // Hour grid lines + labels
                                VStack(spacing: 0) {
                                    ForEach(startHour..<endHour, id: \.self) { hour in
                                        HStack(alignment: .top, spacing: 4) {
                                            Text(hourLabel(hour))
                                                .scaledFont(size: 9, weight: .medium, design: .monospaced)
                                                .foregroundColor(.secondary)
                                                .frame(width: 36, alignment: .trailing)

                                            VStack(spacing: 0) {
                                                Divider()
                                                Spacer()
                                            }
                                        }
                                        .frame(height: hourHeight)
                                        .id(hour)
                                    }
                                }

                                // Drag or click empty space to create task
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: totalHeight)
                                    .padding(.leading, 44)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                if !isDraggingToCreate {
                                                    // First call — anchor start
                                                    isDraggingToCreate = true
                                                    let anchorDate = snappedDate(fromY: value.startLocation.y, for: date)
                                                    dragPreviewStart = anchorDate
                                                    dragPreviewEnd = anchorDate
                                                }
                                                let currentDate = snappedDate(fromY: value.location.y, for: date)
                                                guard let anchor = dragPreviewStart else { return }
                                                // Handle upward drags by swapping
                                                if currentDate < anchor {
                                                    dragPreviewStart = currentDate
                                                    dragPreviewEnd = anchor
                                                } else {
                                                    dragPreviewStart = anchor
                                                    dragPreviewEnd = currentDate
                                                }
                                                // Enforce 15-min minimum block
                                                if let s = dragPreviewStart, let e = dragPreviewEnd,
                                                   e.timeIntervalSince(s) < 15 * 60 {
                                                    dragPreviewEnd = Calendar.current.date(byAdding: .minute, value: 15, to: s)
                                                }
                                            }
                                            .onEnded { value in
                                                let dragDistance = abs(value.translation.height)
                                                if dragDistance < 5 {
                                                    // Treat as click — 1-hour block
                                                    let clickDate = snappedDate(fromY: value.startLocation.y, for: date)
                                                    newTaskStartDate = clickDate
                                                    newTaskEndDate = Calendar.current.date(byAdding: .hour, value: 1, to: clickDate) ?? clickDate
                                                } else {
                                                    // Use dragged range
                                                    if let s = dragPreviewStart, let e = dragPreviewEnd {
                                                        newTaskStartDate = s
                                                        newTaskEndDate = e
                                                    }
                                                }
                                                resetDragState()
                                                isCreatingTask = true
                                            }
                                    )
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.crosshair.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }

                                // Meeting blocks
                                ForEach(meetings) { meeting in
                                    let yOffset = yPosition(for: meeting.startTime)
                                    let height = blockHeight(start: meeting.startTime, end: meeting.endTime)

                                    TimelineMeetingBlock(
                                        meeting: meeting,
                                        color: colorFor(meeting),
                                        popoverMeeting: $popoverMeeting,
                                        modelContext: modelContext
                                    )
                                    .frame(height: max(height, 22))
                                    .padding(.leading, 44)
                                    .padding(.trailing, 4)
                                    .offset(y: yOffset)
                                }

                                // Task blocks
                                ForEach(taskOccurrences) { occurrence in
                                    let yOffset = yPosition(for: occurrence.startTime)
                                    let height = blockHeight(start: occurrence.startTime, end: occurrence.endTime)

                                    TimelineTaskBlock(
                                        occurrence: occurrence,
                                        editingTask: $editingTask,
                                        modelContext: modelContext,
                                        hourHeight: hourHeight,
                                        selectedDate: date
                                    )
                                    .frame(height: max(height, 22))
                                    .padding(.leading, 44)
                                    .padding(.trailing, 4)
                                    .offset(y: yOffset)
                                }

                                // Drag preview block
                                if isDraggingToCreate,
                                   let previewStart = dragPreviewStart,
                                   let previewEnd = dragPreviewEnd {
                                    let previewY = yPosition(for: previewStart)
                                    let previewH = blockHeight(start: previewStart, end: previewEnd)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                        )
                                        .overlay(
                                            Group {
                                                if previewH > 28 {
                                                    Text(previewTimeLabel(start: previewStart, end: previewEnd))
                                                        .scaledFont(size: 10, weight: .medium)
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                        )
                                        .frame(height: max(previewH, 22))
                                        .padding(.leading, 44)
                                        .padding(.trailing, 4)
                                        .offset(y: previewY)
                                        .allowsHitTesting(false)
                                }

                                // "Now" indicator
                                if isToday {
                                    let nowY = yPosition(for: Date.now)
                                    HStack(spacing: 0) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 36)
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(height: 1)
                                    }
                                    .offset(y: nowY - 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onAppear {
                            proxy.scrollTo(scrollToHour, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func snappedDate(fromY y: CGFloat, for date: Date) -> Date {
        let totalMinutes = (y / hourHeight) * 60
        let snappedMinutes = Int(round(totalMinutes / 15.0)) * 15
        let clampedMinutes = max(0, min(snappedMinutes, 24 * 60))
        let hour = clampedMinutes / 60
        let minute = clampedMinutes % 60
        let cal = Calendar.current
        return cal.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: date) ?? date
    }

    private func resetDragState() {
        isDraggingToCreate = false
        dragPreviewStart = nil
        dragPreviewEnd = nil
    }

    private func previewTimeLabel(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "h:mma"
        endFmt.amSymbol = "am"
        endFmt.pmSymbol = "pm"
        return "\(fmt.string(from: start)) – \(endFmt.string(from: end))"
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func yPosition(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let totalMinutes = CGFloat((hour - startHour) * 60 + minute)
        return totalMinutes / 60.0 * hourHeight
    }

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start) / 3600.0
        return CGFloat(duration) * hourHeight
    }

    private func colorFor(_ meeting: MeetingInvite) -> Color {
        if !meeting.accountEmail.isEmpty, let color = accountColors[meeting.accountEmail] {
            return color
        }
        return meeting.sourceMessage?.account?.color ?? .gray
    }
}

// MARK: - TimelineMeetingBlock

struct TimelineMeetingBlock: View {
    let meeting: MeetingInvite
    let color: Color
    @Binding var popoverMeeting: MeetingInvite?
    let modelContext: ModelContext

    @State private var isHovered = false

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "\(fmt.string(from: meeting.startTime)) – \(fmt.string(from: meeting.endTime))"
    }

    private var isShowingPopover: Binding<Bool> {
        Binding(
            get: { popoverMeeting?.id == meeting.id },
            set: { if !$0 { popoverMeeting = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .scaledFont(size: 11, weight: .medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text(timeString)
                    .scaledFont(size: 9)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? color.opacity(0.18) : color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            popoverMeeting = meeting
        }
        .popover(isPresented: isShowingPopover, arrowEdge: .leading) {
            MeetingPopoverView(
                meeting: meeting,
                accountColor: color,
                modelContext: modelContext,
                onDismiss: { popoverMeeting = nil }
            )
        }
    }
}

// MARK: - DragMode

private enum DragMode {
    case move
    case resize
}

// MARK: - TimelineTaskBlock

struct TimelineTaskBlock: View {
    let occurrence: TaskOccurrence
    @Binding var editingTask: TaskBlock?
    let modelContext: ModelContext
    let hourHeight: CGFloat
    let selectedDate: Date

    @State private var isHovered = false
    @State private var dragOffset: CGFloat = 0
    @State private var resizeDelta: CGFloat = 0
    @State private var dragMode: DragMode? = nil
    @State private var isResizeHovered = false

    private var task: TaskBlock { occurrence.sourceTask }
    private var snapUnit: CGFloat { hourHeight / 4.0 }

    private var isDragging: Bool { dragMode != nil }

    private var displayTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"

        if let mode = dragMode {
            let (newStart, newEnd) = computeNewTimes()
            if mode == .move {
                return "\(fmt.string(from: newStart)) – \(fmt.string(from: newEnd))"
            } else {
                return "\(fmt.string(from: occurrence.startTime)) – \(fmt.string(from: newEnd))"
            }
        }

        return "\(fmt.string(from: occurrence.startTime)) – \(fmt.string(from: occurrence.endTime))"
    }

    private var isAIDetected: Bool {
        guard let lastDetected = task.aiLastDetected else { return false }
        return Date.now.timeIntervalSince(lastDetected) < 600
    }

    private var isShowingPopover: Binding<Bool> {
        Binding(
            get: { editingTask?.id == task.id },
            set: { if !$0 { editingTask = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main block body
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.color)
                    .frame(width: 4)

                // Checkbox
                Button {
                    occurrence.toggleDone()
                } label: {
                    Image(systemName: occurrence.isDone ? "checkmark.circle.fill" : "circle")
                        .scaledFont(size: 12)
                        .foregroundColor(occurrence.isDone ? task.color : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(task.title)
                            .scaledFont(size: 11, weight: .medium)
                            .strikethrough(occurrence.isDone)
                            .lineLimit(2)
                            .foregroundColor(occurrence.isDone ? .secondary : .primary)

                        if task.isRecurring {
                            Image(systemName: "repeat")
                                .scaledFont(size: 8)
                                .foregroundColor(.secondary)
                        }

                        if isAIDetected {
                            Image(systemName: "brain.head.profile")
                                .scaledFont(size: 9)
                                .foregroundColor(.purple)
                                .help(task.aiActivity.isEmpty ? "AI detected activity" : task.aiActivity)
                        }
                    }

                    Text(displayTimeString)
                        .scaledFont(size: 9)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)

            // Resize handle at bottom
            Rectangle()
                .fill(Color.clear)
                .frame(height: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isResizeHovered = hovering
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragMode == nil { dragMode = .resize }
                            let snapped = round(value.translation.height / snapUnit) * snapUnit
                            // Enforce minimum 15-min block (1 snap unit)
                            let currentHeight = blockHeight(start: occurrence.startTime, end: occurrence.endTime)
                            let minDelta = -(currentHeight - snapUnit)
                            resizeDelta = max(snapped, minDelta)
                        }
                        .onEnded { _ in
                            applyChanges()
                        }
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isDragging ? task.color.opacity(0.18) : (isHovered ? task.color.opacity(0.12) : task.color.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(task.color.opacity(isDragging ? 0.6 : 0.4), style: StrokeStyle(lineWidth: isDragging ? 1.5 : 1, dash: isDragging ? [] : [4, 3]))
        )
        .shadow(color: isDragging ? .black.opacity(0.15) : .clear, radius: isDragging ? 4 : 0, y: 2)
        .offset(y: dragMode == .move ? dragOffset : 0)
        .frame(height: dragMode == .resize ? max(blockHeight(start: occurrence.startTime, end: occurrence.endTime) + resizeDelta, snapUnit) : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if dragMode == nil { dragMode = .move }
                    guard dragMode == .move else { return }
                    dragOffset = round(value.translation.height / snapUnit) * snapUnit
                }
                .onEnded { _ in
                    applyChanges()
                }
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering && !isResizeHovered {
                NSCursor.pointingHand.push()
            } else if !hovering {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            if dragMode == nil {
                editingTask = task
            }
        }
        .popover(isPresented: isShowingPopover, arrowEdge: .leading) {
            TaskBlockEditor(
                task: task,
                defaultStart: task.startTime,
                onDismiss: { editingTask = nil }
            )
            .environment(\.modelContext, modelContext)
        }
    }

    // MARK: - Geometry Helpers

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start) / 3600.0
        return CGFloat(duration) * hourHeight
    }

    private func computeNewTimes() -> (start: Date, end: Date) {
        let cal = Calendar.current

        if dragMode == .move {
            let minutesDelta = Int(round(Double(dragOffset) / Double(hourHeight) * 60.0 / 15.0)) * 15
            let newStart = cal.date(byAdding: .minute, value: minutesDelta, to: occurrence.startTime) ?? occurrence.startTime
            let newEnd = cal.date(byAdding: .minute, value: minutesDelta, to: occurrence.endTime) ?? occurrence.endTime
            return (newStart, newEnd)
        } else {
            let minutesDelta = Int(round(Double(resizeDelta) / Double(hourHeight) * 60.0 / 15.0)) * 15
            let newEnd = cal.date(byAdding: .minute, value: minutesDelta, to: occurrence.endTime) ?? occurrence.endTime
            // Enforce minimum 15 min
            let minEnd = cal.date(byAdding: .minute, value: 15, to: occurrence.startTime)!
            return (occurrence.startTime, max(newEnd, minEnd))
        }
    }

    private func applyChanges() {
        let (newStart, newEnd) = computeNewTimes()

        if dragMode == .move {
            // Update the source task's time-of-day components
            let cal = Calendar.current
            let newStartComps = cal.dateComponents([.hour, .minute], from: newStart)
            let newEndComps = cal.dateComponents([.hour, .minute], from: newEnd)

            task.startTime = cal.date(bySettingHour: newStartComps.hour ?? 0,
                                       minute: newStartComps.minute ?? 0,
                                       second: 0,
                                       of: task.startTime) ?? task.startTime
            task.endTime = cal.date(bySettingHour: newEndComps.hour ?? 0,
                                     minute: newEndComps.minute ?? 0,
                                     second: 0,
                                     of: task.endTime) ?? task.endTime
        } else if dragMode == .resize {
            let cal = Calendar.current
            let newEndComps = cal.dateComponents([.hour, .minute], from: newEnd)

            task.endTime = cal.date(bySettingHour: newEndComps.hour ?? 0,
                                     minute: newEndComps.minute ?? 0,
                                     second: 0,
                                     of: task.endTime) ?? task.endTime
        }

        try? modelContext.save()

        // Reset state
        dragOffset = 0
        resizeDelta = 0
        dragMode = nil
    }
}

// MARK: - Existing reusable views

struct MeetingRowView: View {
    let meeting: MeetingInvite
    let modelContext: ModelContext

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.title)
                    .scaledFont(.headline)
                    .lineLimit(1)
                Spacer()
                ResponseBadge(status: meeting.responseStatus)
            }
            Text(meeting.organizer)
                .scaledFont(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Image(systemName: "clock")
                    .scaledFont(.caption2)
                Text(meeting.startTime, style: .date)
                Text(meeting.startTime, style: .time)
                Text("–")
                Text(meeting.endTime, style: .time)
            }
            .scaledFont(.caption)
            .foregroundColor(.secondary)

            if !meeting.videoLink.isEmpty {
                Button {
                    if let url = URL(string: meeting.videoLink) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "video")
                            .scaledFont(.caption2)
                        Text("Join Video Call")
                            .scaledFont(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            if meeting.responseStatus == .pending {
                HStack(spacing: 8) {
                    Button("Accept") {
                        MeetingResponseService.shared.respond(
                            to: meeting, with: .accepted, modelContext: modelContext
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)

                    Button("Tentative") {
                        MeetingResponseService.shared.respond(
                            to: meeting, with: .tentative, modelContext: modelContext
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Decline") {
                        MeetingResponseService.shared.respond(
                            to: meeting, with: .declined, modelContext: modelContext
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ResponseBadge: View {
    let status: MeetingResponse

    var body: some View {
        Text(status.rawValue.capitalized)
            .scaledFont(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status {
        case .accepted: return .green
        case .declined: return .red
        case .tentative: return .orange
        case .pending: return .gray
        }
    }
}
