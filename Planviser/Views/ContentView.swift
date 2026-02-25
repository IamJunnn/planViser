import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case inbox = "Inbox"
    case schedule = "Schedule"
    case review = "Review"
    case notes = "Notes"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .inbox: return "envelope.fill"
        case .schedule: return "calendar"
        case .review: return "doc.text.magnifyingglass"
        case .notes: return "lock.doc.fill"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @AppStorage("selectedTab") private var selectedTab: AppTab = .inbox
    @AppStorage("appFontSize") private var fontSizeStep: Double = 3
    @ObservedObject private var screenMonitor = ScreenMonitorManager.shared

    @Query(sort: \WeeklyReview.weekEndDate, order: .reverse)
    private var reviews: [WeeklyReview]

    @State private var showReviewBanner = false
    @State private var windowWidth: CGFloat = 900

    private var isCompact: Bool { windowWidth < 850 }

    private var fontScale: CGFloat {
        let scales: [CGFloat] = [0.8, 0.85, 0.9, 1.0, 1.1, 1.25, 1.4]
        let index = max(0, min(Int(fontSizeStep), scales.count - 1))
        return scales[index]
    }

    var body: some View {
        GeometryReader { geo in
            NavigationSplitView {
                if isCompact {
                    compactSidebar
                        .navigationSplitViewColumnWidth(min: 52, ideal: 56, max: 64)
                } else {
                    expandedSidebar
                        .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
                }
            } detail: {
                VStack(spacing: 0) {
                    if showReviewBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.purple)
                            Text("It's Sunday! Time for your weekly review.")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Start Review") {
                                selectedTab = .review
                                showReviewBanner = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button {
                                showReviewBanner = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.08))

                        Divider()
                    }

                    switch selectedTab {
                    case .inbox:
                        InboxView()
                    case .schedule:
                        MeetingHubView()
                    case .review:
                        WeeklyReviewView()
                    case .notes:
                        NotesView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isCompact)
            .onChange(of: geo.size.width) { _, newWidth in
                windowWidth = newWidth
            }
            .onAppear {
                windowWidth = geo.size.width
            }
        }
        .environment(\.fontScale, fontScale)
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            showReviewBanner = WeeklyReviewService.shared.shouldPromptReview(existingReviews: reviews)
        }
    }

    // MARK: - Compact Sidebar (icon-only)

    private var compactSidebar: some View {
        VStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                CompactTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }

            Spacer()

            if screenMonitor.isEnabled {
                Circle()
                    .fill(screenMonitor.isCapturing ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                    .help("AI Monitoring")
                    .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
    }

    // MARK: - Expanded Sidebar (icon + label)

    private var expandedSidebar: some View {
        List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            } icon: {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screenMonitor.isEnabled {
                HStack(spacing: 5) {
                    Circle()
                        .fill(screenMonitor.isCapturing ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text("AI Monitoring")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Compact Tab Button with hover + press feedback

struct CompactTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : isHovering ? .primary : .secondary)
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backgroundColor)
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
        )
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isPressed {
            return Color.primary.opacity(0.12)
        } else if isHovering {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}
