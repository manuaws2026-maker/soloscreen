import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var renamingSessionId: UUID?
    @State private var renameText: String = ""

    private let bgColor = Color(hex: "0D1117")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")
    private let accentTeal = Color(hex: "00BCD4")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()
                .overlay(borderColor)

            // Session list
            sessionList

            Divider()
                .overlay(borderColor)

            // Footer
            footerBar
        }
        .background(surfaceColor)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Chats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.createSession()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentTeal)
            }
            .buttonStyle(.plain)
            .help("New Chat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedSessions, id: \.title) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            sessionRow(session)
                        }
                    } header: {
                        sectionHeader(group.title)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(surfaceColor)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: Session) -> some View {
        let isActive = appState.activeSessionId == session.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.activeSessionId = session.id
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? accentTeal : .white.opacity(0.4))

                if renamingSessionId == session.id {
                    TextField("Session name", text: $renameText, onCommit: {
                        commitRename(session)
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(relativeTime(session.updatedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                if session.visibleMessageCount > 0 {
                    Text("\(session.visibleMessageCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? accentTeal.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? accentTeal.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingSessionId = session.id
                renameText = session.title
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    appState.deleteSession(session.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    appState.deleteSession(session.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.showProjects = true
            } label: {
                Label("Projects", systemImage: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Manage Projects")

            Spacer()

            Button {
                appState.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func commitRename(_ session: Session) {
        if let index = appState.sessions.firstIndex(where: { $0.id == session.id }) {
            appState.sessions[index].title = renameText.isEmpty ? session.title : renameText
        }
        renamingSessionId = nil
    }

    private var groupedSessions: [SessionGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var today: [Session] = []
        var yesterday: [Session] = []
        var thisWeek: [Session] = []
        var older: [Session] = []

        let sorted = appState.sessions.sorted { $0.updatedAt > $1.updatedAt }

        for session in sorted {
            let sessionDate = session.updatedAt
            if sessionDate >= startOfToday {
                today.append(session)
            } else if sessionDate >= startOfYesterday {
                yesterday.append(session)
            } else if sessionDate >= startOfWeek {
                thisWeek.append(session)
            } else {
                older.append(session)
            }
        }

        var groups: [SessionGroup] = []
        if !today.isEmpty { groups.append(SessionGroup(title: "Today", sessions: today)) }
        if !yesterday.isEmpty { groups.append(SessionGroup(title: "Yesterday", sessions: yesterday)) }
        if !thisWeek.isEmpty { groups.append(SessionGroup(title: "This Week", sessions: thisWeek)) }
        if !older.isEmpty { groups.append(SessionGroup(title: "Older", sessions: older)) }
        return groups
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Session Group

private struct SessionGroup {
    let title: String
    let sessions: [Session]
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
        .frame(width: 260, height: 600)
}
