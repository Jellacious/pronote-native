import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel

    private var todayCourses: [CourseItem] {
        let cal = Calendar(identifier: .iso8601)
        return viewModel.courses.filter { cal.isDateInToday($0.startDate) }
    }

    private var upcomingAssignments: [AssignmentItem] {
        Array(viewModel.assignments.filter { !$0.done }.prefix(5))
    }

    private var recentGrades: [GradeItem] {
        Array((viewModel.grades?.grades ?? []).prefix(5))
    }

    private var todayMenu: MenuDayItem? {
        let cal = Calendar(identifier: .iso8601)
        return viewModel.menus?.days.first { cal.isDateInToday($0.date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = viewModel.errorMessage {
                    SectionErrorBanner(message: error, viewModel: viewModel) {
                        await viewModel.loadSection(.home, forceRefresh: true)
                    }
                }

                nowHeroCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    dashboardCard(title: "Emploi du temps d'aujourd'hui", icon: "calendar", section: .timetable) {
                        if todayCourses.isEmpty {
                            emptyPlaceholder("Aucun cours aujourd'hui")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(todayCourses) { course in
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(course.isCancelled ? Color.red : course.displayColor)
                                            .frame(width: 4, height: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(course.subject)
                                                .font(.subheadline.weight(.semibold))
                                                .strikethrough(course.isCancelled)
                                                .lineLimit(1)
                                            Text([course.timeRangeString, course.room].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if course.isCancelled {
                                            Text("Annulé")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    dashboardCard(title: "Travail à faire", icon: "book.closed", section: .assignments) {
                        if upcomingAssignments.isEmpty {
                            emptyPlaceholder(viewModel.assignments.isEmpty ? "Ouvre Cahier de textes pour synchroniser" : "Tout est fait !")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(upcomingAssignments) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Button {
                                            Task { await viewModel.toggleAssignmentDone(item) }
                                        } label: {
                                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(item.done ? .green : .secondary)
                                                .contentTransition(.symbolEffect(.replace))
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(item.subject)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(item.displayColor)
                                                Spacer()
                                                Text(shortDay(item.deadline))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(item.description)
                                                .font(.caption)
                                                .foregroundStyle(item.done ? .secondary : .primary)
                                                .strikethrough(item.done)
                                                .lineLimit(2)
                                                .animation(.snappy(duration: 0.25), value: item.done)
                                            if !item.attachments.isEmpty {
                                                HStack(spacing: 6) {
                                                    ForEach(item.attachments.prefix(2)) { att in
                                                        AttachmentPillView(attachment: att)
                                                    }
                                                }
                                                .padding(.top, 2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    dashboardCard(title: "Dernières notes", icon: "chart.bar.xaxis", section: .grades) {
                        if recentGrades.isEmpty {
                            emptyPlaceholder("Ouvre Notes pour synchroniser")
                        } else {
                            VStack(spacing: 8) {
                                if let overall = viewModel.grades?.overallAverage {
                                    HStack {
                                        Text("Moyenne générale")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(overall) / 20")
                                            .font(.subheadline.bold().monospacedDigit())
                                    }
                                    Divider()
                                }
                                ForEach(recentGrades) { g in
                                    HStack {
                                        Text(g.subject)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(g.valueDisplay)/\(g.outOfDisplay)")
                                            .font(.subheadline.bold().monospacedDigit())
                                    }
                                }
                            }
                        }
                    }

                    dashboardCard(title: "Menu de la cantine", icon: "fork.knife", section: .menus) {
                        if let menu = todayMenu, !menu.lunch.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(menu.lunch) { sec in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(sec.category)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 96, alignment: .leading)
                                        Text(sec.dishes.map { $0.name }.joined(separator: ", "))
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        } else {
                            emptyPlaceholder("Ouvre Cantine pour charger le menu")
                        }
                    }

                    dashboardCard(title: "Pense-bête", icon: "note.text", section: nil) {
                        TextEditor(text: Binding(
                            get: { viewModel.stickyNote },
                            set: { viewModel.updateStickyNote($0) }
                        ))
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90, maxHeight: 120)
                    }

                    dashboardCard(title: "Vie scolaire & Messages", icon: "tray.full", section: .messages) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("\(viewModel.unreadMessagesCount) non lu(s)", systemImage: "envelope.badge")
                                    .font(.subheadline)
                                Spacer()
                            }
                            if let nb = viewModel.notebook {
                                let totalHours = nb.absences.reduce(0) { $0 + $1.hoursMissed }
                                let unj = nb.absences.filter { !$0.justified }.count
                                Label("\(nb.absences.count) absence(s) (\(totalHours)h) · \(unj) non justifiée(s)", systemImage: "person.text.rectangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Ouvre Vie scolaire pour synchroniser")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AmbientBackground())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accueil")
                        .font(.title3.bold())
                    Text(todayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nowHeroCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let activeCourses = todayCourses.filter { !$0.isCancelled }
            let current = activeCourses.first { $0.startDate <= now && now < $0.endDate }
            let next = activeCourses.first { $0.startDate > now }

            GlassCard(cornerRadius: 16, padding: 16) {
                if let current {
                    let total = max(1, current.endDate.timeIntervalSince(current.startDate))
                    let elapsed = max(0, min(total, now.timeIntervalSince(current.startDate)))
                    let progress = elapsed / total
                    let remainingMin = max(1, Int(ceil(current.endDate.timeIntervalSince(now) / 60)))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HStack(spacing: 5) {
                                LivePulsingDot(color: current.displayColor)
                                Text("EN COURS")
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(current.displayColor.opacity(0.22), in: Capsule())
                            .foregroundStyle(current.displayColor)

                            Spacer()

                            Text("Finit dans \(formatDurationMinutes(remainingMin))")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: remainingMin)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(current.subject)
                                .font(.title3.bold())
                            Spacer()
                            Text(current.timeRangeString)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            if let room = current.room, !room.isEmpty {
                                Label("Salle \(room)", systemImage: "mappin.and.ellipse")
                            }
                            if let teacher = current.teacher, !teacher.isEmpty {
                                Label(teacher, systemImage: "person")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule()
                                    .fill(current.displayColor)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 6)

                        if let next {
                            HStack(spacing: 6) {
                                Text("Ensuite :")
                                    .foregroundStyle(.secondary)
                                Text(next.subject)
                                    .fontWeight(.semibold)
                                Text("à \(formatTime(next.startDate))")
                                    .foregroundStyle(.secondary)
                                if let room = next.room, !room.isEmpty {
                                    Text("· Salle \(room)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                } else if let next {
                    let untilMin = max(1, Int(ceil(next.startDate.timeIntervalSince(now) / 60)))
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PROCHAIN COURS")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(next.displayColor.opacity(0.22), in: Capsule())
                                .foregroundStyle(next.displayColor)

                            Text(next.subject)
                                .font(.title3.bold())

                            HStack(spacing: 12) {
                                Text(next.timeRangeString)
                                    .monospacedDigit()
                                if let room = next.room, !room.isEmpty {
                                    Label("Salle \(room)", systemImage: "mappin.and.ellipse")
                                }
                                if let teacher = next.teacher, !teacher.isEmpty {
                                    Label(teacher, systemImage: "person")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Dans \(formatDurationMinutes(untilMin))")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(next.displayColor)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: untilMin)
                            Text(formatTime(next.startDate))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: activeCourses.isEmpty ? "sun.max" : "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(activeCourses.isEmpty ? Color.orange : Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeCourses.isEmpty ? "Pas de cours aujourd'hui" : "Journée terminée")
                                .font(.headline)
                            Text(activeCourses.isEmpty ? "Profite de ta journée !" : "Tous tes cours d'aujourd'hui sont terminés.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func dashboardCard<Content: View>(
        title: String,
        icon: String,
        section: AppSection?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(cornerRadius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                    Spacer()
                    if let section {
                        SeeAllButton {
                            viewModel.selectedSection = section
                        }
                    }
                }
                Divider()
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func formatDurationMinutes(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h\(String(format: "%02d", m))" }
        if h > 0 { return "\(h)h" }
        return "\(m) min"
    }

    private func formatTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func shortDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEE d MMM"
        return df.string(from: date).capitalized
    }

    private var todayTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEEE d MMMM yyyy"
        return df.string(from: Date()).capitalized
    }
}

private struct LivePulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.38))
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.9 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.75)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

private struct SeeAllButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("Tout voir")
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .offset(x: isHovered ? 2 : 0)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(isHovered ? 0.14 : 0.0))
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
