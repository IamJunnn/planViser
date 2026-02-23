import SwiftUI

enum AppTab: String, CaseIterable {
    case inbox = "Inbox"
    case meetings = "Meetings"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .inbox: return "envelope"
        case .meetings: return "calendar"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .inbox

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            Divider()

            // Tab content
            switch selectedTab {
            case .inbox:
                InboxView()
            case .meetings:
                MeetingHubView()
            case .settings:
                SettingsView()
            }
        }
        .frame(width: 380, height: 480)
    }
}
