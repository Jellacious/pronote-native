import SwiftUI

struct MainShellView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isSettingsHovered = false
    @State private var isLogoutHovered = false

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $viewModel.selectedSection) { section in
                HStack(spacing: 10) {
                    SectionIconBadge(systemImage: section.systemImage, color: sectionColor(for: section))
                    Text(section.title)
                        .font(.body.weight(.medium))
                    Spacer()
                    if let badge = badgeCount(for: section), badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: badge)
                    }
                }
                .padding(.vertical, 2)
                .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 270)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    syncStatusLine
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(viewModel.credentials?.studentName ?? "Élève")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if let school = viewModel.credentials?.schoolName, !school.isEmpty {
                                Text(school)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        SettingsLink {
                            Image(systemName: "gearshape")
                                .font(.caption)
                                .padding(5)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(isSettingsHovered ? 0.08 : 0))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isSettingsHovered ? .primary : .secondary)
                        .animation(.easeOut(duration: 0.15), value: isSettingsHovered)
                        .onHover { isSettingsHovered = $0 }
                        .help("Réglages (⌘,)")

                        Button {
                            viewModel.logout()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.caption)
                                .padding(5)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(isLogoutHovered ? 0.08 : 0))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isLogoutHovered ? .primary : .secondary)
                        .animation(.easeOut(duration: 0.15), value: isLogoutHovered)
                        .onHover { isLogoutHovered = $0 }
                        .help("Se déconnecter")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        } detail: {
            Group {
                switch viewModel.selectedSection {
                case .home:
                    HomeView(viewModel: viewModel)
                case .timetable:
                    TimetableView(viewModel: viewModel)
                case .assignments:
                    AssignmentsView(viewModel: viewModel)
                case .grades:
                    GradesView(viewModel: viewModel)
                case .notebook:
                    NotebookView(viewModel: viewModel)
                case .messages:
                    MessagesView(viewModel: viewModel)
                case .menus:
                    MenusView(viewModel: viewModel)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.isOffline {
                    offlineBanner
                }
            }
        }
        .onChange(of: viewModel.selectedSection) { _, newSection in
            Task {
                await viewModel.loadSection(newSection)
            }
        }
        .background {
            Group {
                Button("") { viewModel.selectedSection = .home }.keyboardShortcut("1", modifiers: .command)
                Button("") { viewModel.selectedSection = .timetable }.keyboardShortcut("2", modifiers: .command)
                Button("") { viewModel.selectedSection = .assignments }.keyboardShortcut("3", modifiers: .command)
                Button("") { viewModel.selectedSection = .grades }.keyboardShortcut("4", modifiers: .command)
                Button("") { viewModel.selectedSection = .notebook }.keyboardShortcut("5", modifiers: .command)
                Button("") { viewModel.selectedSection = .messages }.keyboardShortcut("6", modifiers: .command)
                Button("") { viewModel.selectedSection = .menus }.keyboardShortcut("7", modifiers: .command)
                Button("") {
                    Task { await viewModel.loadSection(viewModel.selectedSection, forceRefresh: true) }
                }.keyboardShortcut("r", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    @ViewBuilder
    private var syncStatusLine: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            if viewModel.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Actualisation…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if let notice = viewModel.statusNotice {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(notice)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if let until = viewModel.rateLimitUntil, now < until {
                let mins = max(1, Int(ceil(until.timeIntervalSince(now) / 60)))
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Pause Pronote (\(mins) min)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            } else if viewModel.isOffline {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Hors-ligne (cache)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            } else if let updated = viewModel.lastUpdatedDate(for: viewModel.selectedSection) {
                let elapsed = max(0, Int(now.timeIntervalSince(updated) / 60))
                HStack(spacing: 6) {
                    Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                    Text(elapsed < 1 ? "Synchronisé · à l'instant" : "Synchronisé · il y a \(elapsed) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            Text(offlineBannerText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Button("Réessayer") {
                Task {
                    await viewModel.loadSection(viewModel.selectedSection, forceRefresh: true)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var offlineBannerText: String {
        if let updated = viewModel.lastUpdatedDate(for: viewModel.selectedSection) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "fr_FR")
            df.dateFormat = "d MMM à HH:mm"
            return "Mode hors-ligne — données en cache du \(df.string(from: updated))"
        }
        return "Mode hors-ligne — aucune donnée en cache pour cette section"
    }

    private func badgeCount(for section: AppSection) -> Int? {
        switch section {
        case .assignments:
            return viewModel.undoneAssignmentsCount
        case .messages:
            return viewModel.unreadMessagesCount
        default:
            return nil
        }
    }

    private func sectionColor(for section: AppSection) -> Color {
        switch section {
        case .home: return .blue
        case .timetable: return .indigo
        case .assignments: return .teal
        case .grades: return .orange
        case .notebook: return .purple
        case .messages: return .pink
        case .menus: return .green
        }
    }
}
