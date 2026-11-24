import AppKit
import SwiftUI

struct AssignmentsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var tab: Int = 0 // 0 = Travail à faire, 1 = Contenus de cours
    @State private var showOnlyUndone: Bool = false
    @State private var selectedSubject: String = "Toutes"

    private var subjectsList: [String] {
        let base = tab == 0
            ? viewModel.assignments.map { $0.subject }
            : viewModel.resources.map { $0.subject }
        return ["Toutes"] + Array(Set(base)).sorted()
    }

    private var filteredAssignments: [AssignmentItem] {
        viewModel.assignments.filter { item in
            let matchesDone = !showOnlyUndone || !item.done
            let matchesSubject = selectedSubject == "Toutes" || item.subject == selectedSubject
            return matchesDone && matchesSubject
        }
    }

    private var filteredResources: [LessonResourceItem] {
        viewModel.resources.filter { res in
            selectedSubject == "Toutes" || res.subject == selectedSubject
        }
    }

    private var groupedDays: [(date: Date, items: [AssignmentItem])] {
        let cal = Calendar(identifier: .iso8601)
        let grouped = Dictionary(grouping: filteredAssignments) { item in
            cal.startOfDay(for: item.deadline)
        }
        return grouped.keys.sorted().map { day in
            (date: day, items: grouped[day] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                SectionErrorBanner(message: error, viewModel: viewModel) {
                    if tab == 0 {
                        await viewModel.loadAssignments(forceRefresh: true)
                    } else {
                        await viewModel.loadResources(forceRefresh: true)
                    }
                }
            }

            filterBar
            Divider()

            if tab == 0 {
                assignmentsContent
            } else {
                resourcesContent
            }
        }
        .background(AmbientBackground())
        .animation(.easeInOut(duration: 0.2), value: showOnlyUndone)
        .animation(.easeInOut(duration: 0.2), value: selectedSubject)
        .navigationTitle("")
        .onChange(of: tab) { _, newTab in
            selectedSubject = "Toutes"
            if newTab == 1 {
                Task { await viewModel.loadResources() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Cahier de textes")
                    .font(.title3.bold())
            }

            ToolbarItem(placement: .principal) {
                Picker("Onglet", selection: $tab) {
                    Text("Travail à faire").tag(0)
                    Text("Contenus de cours").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Matière", selection: $selectedSubject) {
                ForEach(subjectsList, id: \.self) { sub in
                    Text(sub).tag(sub)
                }
            }
            .frame(maxWidth: 240)

            if tab == 0 {
                Toggle("À faire uniquement", isOn: $showOnlyUndone)
                    .toggleStyle(.checkbox)
            }

            Spacer()

            let itemCount = tab == 0 ? filteredAssignments.count : filteredResources.count
            let countLabel = tab == 0
                ? (itemCount <= 1 ? "\(itemCount) devoir" : "\(itemCount) devoirs")
                : (itemCount <= 1 ? "\(itemCount) contenu" : "\(itemCount) contenus")
            Text(countLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: itemCount)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var assignmentsContent: some View {
        if viewModel.isLoading && viewModel.assignments.isEmpty {
            Spacer()
            ProgressView("Chargement des devoirs…")
            Spacer()
        } else if filteredAssignments.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(showOnlyUndone ? "Aucun devoir à faire" : "Aucun devoir sur la période")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedDays, id: \.date) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayTitle(group.date))
                                .font(.headline)
                                .foregroundStyle(Calendar.current.isDateInToday(group.date) ? Color.accentColor : Color.primary)
                                .padding(.horizontal, 4)

                            ForEach(group.items) { item in
                                AssignmentCardRow(item: item) {
                                    Task { await viewModel.toggleAssignmentDone(item) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        if viewModel.isLoading && viewModel.resources.isEmpty {
            Spacer()
            ProgressView("Chargement des contenus de cours…")
            Spacer()
        } else if filteredResources.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Aucun contenu de cours récent")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredResources) { res in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(res.subject)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(res.displayColor.opacity(0.18), in: Capsule())
                                    .foregroundStyle(res.displayColor)

                                if !res.teachers.isEmpty {
                                    Text(res.teachers.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(dateTimeRange(res.startDate, res.endDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(res.contents) { content in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let title = content.title, !title.isEmpty {
                                        Text(title)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    if !content.description.isEmpty {
                                        Text(content.description)
                                            .font(.body)
                                            .textSelection(.enabled)
                                    }
                                    if !content.attachments.isEmpty {
                                        FlowAttachmentRow(attachments: content.attachments)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEEE d MMMM"
        return "Pour le " + df.string(from: date).capitalized
    }

    private func dateTimeRange(_ start: Date, _ end: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM · HH:mm"
        return df.string(from: start)
    }
}

struct AttachmentPillView: View {
    let attachment: AttachmentItem
    @State private var isHovered: Bool = false

    private var iconName: String {
        let lower = attachment.name.lowercased()
        if attachment.kind == 0 { return "link" }
        if lower.hasSuffix(".pdf") { return "doc.richtext" }
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".mp3") { return "play.rectangle" }
        return "paperclip"
    }

    var body: some View {
        Button {
            if let url = URL(string: attachment.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label(attachment.name, systemImage: iconName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Color.accentColor.opacity(isHovered ? 0.24 : 0.15),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .help("Ouvrir \(attachment.name)")
    }
}

struct FlowAttachmentRow: View {
    let attachments: [AttachmentItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    AttachmentPillView(attachment: att)
                }
            }
        }
    }
}

private struct AssignmentCardRow: View {
    let item: AssignmentItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.subject)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(item.displayColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(item.displayColor)

                    if let minutes = item.lengthMinutes, minutes > 0 {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(item.done ? "Fait" : "Non fait")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background((item.done ? Color.green : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundStyle(item.done ? .green : .orange)
                }

                Text(item.description.isEmpty ? "Pas de description" : item.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .opacity(item.done ? 0.52 : 1.0)
                    .strikethrough(item.done)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !item.attachments.isEmpty {
                    FlowAttachmentRow(attachments: item.attachments)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: item.done)
    }
}
