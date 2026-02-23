import SwiftUI
import SwiftData

struct MeetingHubView: View {
    @Query(sort: \MeetingInvite.startTime)
    private var allMeetings: [MeetingInvite]

    @Environment(\.modelContext) private var modelContext

    private var upcomingMeetings: [MeetingInvite] {
        allMeetings.filter { $0.startTime > Date.now }
    }

    var body: some View {
        if upcomingMeetings.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No upcoming meetings")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Meeting invites from your emails will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(upcomingMeetings) { meeting in
                MeetingRowView(meeting: meeting, modelContext: modelContext)
            }
        }
    }
}

struct MeetingRowView: View {
    let meeting: MeetingInvite
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ResponseBadge(status: meeting.responseStatus)
            }
            Text(meeting.organizer)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(meeting.startTime, style: .date)
                Text(meeting.startTime, style: .time)
                Text("–")
                Text(meeting.endTime, style: .time)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if !meeting.videoLink.isEmpty {
                Button {
                    if let url = URL(string: meeting.videoLink) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "video")
                            .font(.caption2)
                        Text("Join Video Call")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Response buttons
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
        .padding(.vertical, 4)
    }
}

struct ResponseBadge: View {
    let status: MeetingResponse

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
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
