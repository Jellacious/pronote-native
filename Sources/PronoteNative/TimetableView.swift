import SwiftUI

struct TimetableView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedCourse: CourseItem?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeOpacity: Double = 1.0
    @State private var isAnimatingWeek: Bool = false

    private var hourHeight: CGFloat { settings.hourHeight }
    private let timeColumnWidth: CGFloat = 56

    private var startHour: Int {
        let cal = Calendar(identifier: .iso8601)
        let earliest = viewModel.courses.map { cal.component(.hour, from: $0.startDate) }.min() ?? 8
        return max(6, min(8, earliest))
    }

    private var endHour: Int {
        let cal = Calendar(identifier: .iso8601)
        let latest = viewModel.courses.map { course -> Int in
            let h = cal.component(.hour, from: course.endDate)
            let m = cal.component(.minute, from: course.endDate)
            return m > 0 ? h + 1 : h
        }.max() ?? 18
        return min(22, max(18, latest))
    }

    private var daysToShow: [Date] {
        let cal = Calendar(identifier: .iso8601)
        let hasSaturday = settings.alwaysShowSaturday || viewModel.courses.contains {
            cal.component(.weekday, from: $0.startDate) == 7
        }
        let count = hasSaturday ? 6 : 5
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: viewModel.currentWeekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            VStack(spacing: 0) {
                dayHeaderRow
                Divider()

                ZStack {
                    timetableGrid

                    if abs(swipeOffset) >= 90 {
                        HStack {
                            if swipeOffset > 0 {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 24)
                            }
                            Spacer()
                            if swipeOffset < 0 {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 24)
                            }
                        }
                        .allowsHitTesting(false)
                    }

                    if viewModel.isLoading && viewModel.courses.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Chargement de l'emploi du temps…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    } else if !viewModel.isLoading && viewModel.courses.isEmpty && viewModel.errorMessage == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Aucun cours cette semaine")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .offset(x: swipeOffset)
            .opacity(swipeOpacity)
            .clipped()
        }
        .background(AmbientBackground())
        .frame(minWidth: 920, minHeight: 640)
        .navigationTitle(monthYearTitle)
        .navigationSubtitle(timetableSubtitle)
        .onInteractiveTrackpadSwipe(
            dragOffset: $swipeOffset,
            swipeOpacity: $swipeOpacity,
            threshold: 90,
            onCommitLeft: {
                Task {
                    if settings.invertTimetableSwipe {
                        await viewModel.goToPreviousWeek()
                    } else {
                        await viewModel.goToNextWeek()
                    }
                }
            },
            onCommitRight: {
                Task {
                    if settings.invertTimetableSwipe {
                        await viewModel.goToNextWeek()
                    } else {
                        await viewModel.goToPreviousWeek()
                    }
                }
            }
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Button {
                        animateWeekTransition(direction: -1) {
                            await viewModel.goToPreviousWeek()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 18, height: 18)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Semaine précédente (←)")

                    Button("Aujourd'hui") {
                        Task { await viewModel.goToToday() }
                    }
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Revenir à aujourd'hui (⌘T)")

                    Button {
                        animateWeekTransition(direction: 1) {
                            await viewModel.goToNextWeek()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 18, height: 18)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Semaine suivante (→)")
                }
                .disabled(viewModel.isLoading || isAnimatingWeek)
            }
        }
    }

    private var timetableSubtitle: String {
        if let label = viewModel.currentWeekLabel, !label.isEmpty {
            return "\(weekRangeSubtitle) · \(label)"
        }
        return weekRangeSubtitle
    }

    private func animateWeekTransition(direction: Int, action: @escaping @MainActor () async -> Void) {
        guard !isAnimatingWeek else { return }
        isAnimatingWeek = true
        Haptics.play(.generic)
        let exitX: CGFloat = direction > 0 ? -180 : 180
        let enterX: CGFloat = direction > 0 ? 70 : -70

        withAnimation(.easeIn(duration: 0.14)) {
            swipeOffset = exitX
            swipeOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            await action()
            swipeOffset = enterX
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                swipeOffset = 0
                swipeOpacity = 1
            }
            isAnimatingWeek = false
        }
    }

    private func matchingResources(for course: CourseItem) -> [LessonResourceItem] {
        let cal = Calendar.current
        return viewModel.resources.filter { res in
            let sameDay = cal.isDate(res.startDate, inSameDayAs: course.startDate)
            let sameTime = abs(res.startDate.timeIntervalSince(course.startDate)) < 900
            let sameSubject = res.subject.caseInsensitiveCompare(course.subject) == .orderedSame
            return sameDay && (sameTime || sameSubject) && !res.contents.isEmpty
        }
    }

    private func matchingAssignments(for course: CourseItem) -> [AssignmentItem] {
        let cal = Calendar.current
        return viewModel.assignments.filter { hw in
            cal.isDate(hw.deadline, inSameDayAs: course.startDate) &&
            hw.subject.caseInsensitiveCompare(course.subject) == .orderedSame
        }
    }

    private func resourcePreviewText(for course: CourseItem) -> String? {
        let matched = matchingResources(for: course)
        for res in matched {
            for content in res.contents {
                if let title = content.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    return title
                }
                let desc = content.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !desc.isEmpty {
                    return desc
                }
            }
        }
        return nil
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
            Button("Réessayer") {
                Task { await viewModel.loadTimetable(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Reconnecter") {
                viewModel.logout()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeColumnWidth, height: 52)

            ForEach(daysToShow, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 3) {
                    Text(weekdayShort(day))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)

                    Text(dayNumber(day))
                        .font(.system(size: 15, weight: isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isToday ? Color.accentColor : Color.clear)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
        }
    }

    private var timetableGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 10)
                                .offset(y: -7)
                                .frame(maxWidth: .infinity, alignment: .topTrailing)
                                .frame(height: hourHeight, alignment: .top)
                                .id(hour)
                        }
                    }
                    .frame(width: timeColumnWidth, height: CGFloat(endHour - startHour) * hourHeight, alignment: .top)

                    ForEach(daysToShow, id: \.self) { day in
                        dayColumn(for: day)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .onAppear {
                let currentHour = Calendar(identifier: .iso8601).component(.hour, from: Date())
                let targetHour = (startHour..<endHour).contains(currentHour) ? currentHour : startHour
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(targetHour, anchor: .top)
                }
            }
        }
    }

    private func dayColumn(for day: Date) -> some View {
        let dayCourses = courses(for: day)
        let laidOut = layoutCourses(dayCourses)
        let totalHeight = CGFloat(endHour - startHour) * hourHeight
        let isToday = Calendar.current.isDateInToday(day)

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if isToday {
                    Color.accentColor.opacity(0.03)
                }

                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 1)
                            Spacer()
                            Rectangle()
                                .fill(Color.primary.opacity(0.03))
                                .frame(height: 1)
                            Spacer()
                        }
                        .frame(height: hourHeight)
                    }
                }

                ForEach(laidOut, id: \.course.id) { item in
                    let colWidth = geo.size.width / CGFloat(item.totalColumns)
                    let xOffset = colWidth * CGFloat(item.column)
                    let metrics = courseVerticalMetrics(item.course)

                    CourseCardView(
                        course: item.course,
                        blockHeight: metrics.height,
                        resourcePreview: resourcePreviewText(for: item.course)
                    ) {
                        selectedCourse = item.course
                    }
                    .frame(width: max(0, colWidth - 6), height: metrics.height)
                    .popover(
                        isPresented: Binding(
                            get: { selectedCourse?.id == item.course.id },
                            set: { if !$0 && selectedCourse?.id == item.course.id { selectedCourse = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        CourseDetailPopover(
                            course: item.course,
                            resources: matchingResources(for: item.course),
                            assignments: matchingAssignments(for: item.course),
                            onToggleAssignment: { hw in
                                Task { await viewModel.toggleAssignmentDone(hw) }
                            }
                        )
                    }
                    .padding(.leading, xOffset + 3)
                    .padding(.top, metrics.topOffset)
                }

                if isToday, let timeOffset = currentTimeOffset() {
                    HStack(spacing: 0) {
                        CurrentTimeDot()
                            .offset(x: -3.5)
                        Rectangle()
                            .fill(Color.red)
                            .frame(height: 1.5)
                    }
                    .offset(y: timeOffset - 3.5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
        }
    }

    private func courseVerticalMetrics(_ course: CourseItem) -> (topOffset: CGFloat, height: CGFloat) {
        let cal = Calendar(identifier: .iso8601)
        let startComps = cal.dateComponents([.hour, .minute], from: course.startDate)
        let endComps = cal.dateComponents([.hour, .minute], from: course.endDate)

        let startMinutes = Double((startComps.hour ?? startHour) * 60 + (startComps.minute ?? 0))
        let endMinutes = Double((endComps.hour ?? startHour) * 60 + (endComps.minute ?? 0))
        let baseMinutes = Double(startHour * 60)

        let topOffset = CGFloat(max(0, (startMinutes - baseMinutes) / 60.0)) * hourHeight + 1
        let height = max(28, CGFloat((endMinutes - startMinutes) / 60.0) * hourHeight - 3)
        return (topOffset, height)
    }

    private func currentTimeOffset() -> CGFloat? {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let currentMinutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let minMinutes = Double(startHour * 60)
        let maxMinutes = Double(endHour * 60)
        guard currentMinutes >= minMinutes && currentMinutes <= maxMinutes else { return nil }
        return CGFloat((currentMinutes - minMinutes) / 60.0) * hourHeight
    }

    private struct LaidOutCourse {
        let course: CourseItem
        let column: Int
        let totalColumns: Int
    }

    private func layoutCourses(_ dayCourses: [CourseItem]) -> [LaidOutCourse] {
        let sorted = dayCourses.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
        guard !sorted.isEmpty else { return [] }

        var clusters: [[CourseItem]] = []
        var currentCluster: [CourseItem] = []
        var clusterEnd: Date = .distantPast

        for course in sorted {
            if currentCluster.isEmpty || course.startDate < clusterEnd {
                currentCluster.append(course)
                if course.endDate > clusterEnd {
                    clusterEnd = course.endDate
                }
            } else {
                clusters.append(currentCluster)
                currentCluster = [course]
                clusterEnd = course.endDate
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        var result: [LaidOutCourse] = []
        for cluster in clusters {
            var columnEnds: [Date] = []
            var assigned: [(course: CourseItem, col: Int)] = []

            for course in cluster {
                if let reuseIdx = columnEnds.firstIndex(where: { $0 <= course.startDate }) {
                    columnEnds[reuseIdx] = course.endDate
                    assigned.append((course, reuseIdx))
                } else {
                    columnEnds.append(course.endDate)
                    assigned.append((course, columnEnds.count - 1))
                }
            }

            let totalCols = max(1, columnEnds.count)
            for item in assigned {
                result.append(LaidOutCourse(course: item.course, column: item.col, totalColumns: totalCols))
            }
        }

        return result
    }

    private func courses(for day: Date) -> [CourseItem] {
        let cal = Calendar(identifier: .iso8601)
        return viewModel.courses.filter { cal.isDate($0.startDate, inSameDayAs: day) }
    }

    private func weekdayShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEE"
        return df.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d"
        return df.string(from: date)
    }

    private var monthYearTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "MMMM yyyy"
        return df.string(from: viewModel.currentWeekStart).capitalized
    }

    private var weekRangeSubtitle: String {
        let cal = Calendar(identifier: .iso8601)
        let end = cal.date(byAdding: .day, value: daysToShow.count - 1, to: viewModel.currentWeekStart) ?? viewModel.currentWeekStart
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        return "Semaine du \(df.string(from: viewModel.currentWeekStart)) – \(df.string(from: end))"
    }
}

private struct CourseCardView: View {
    let course: CourseItem
    let blockHeight: CGFloat
    let resourcePreview: String?
    let onTap: () -> Void

    @State private var isHovered = false

    private var accentColor: Color {
        course.isCancelled ? .red : course.displayColor
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text(course.subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(course.isCancelled ? Color.secondary : Color.primary)
                        .strikethrough(course.isCancelled)
                        .lineLimit(blockHeight > 70 ? 2 : 1)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    if course.isCancelled {
                        statusPill("Annulé", color: .red)
                    } else if course.isModified {
                        statusPill("Modifié", color: .orange)
                    }
                }

                if blockHeight > 44 {
                    Text(course.timeRangeString)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if blockHeight > 60 {
                    HStack(spacing: 6) {
                        if let room = course.room, !room.isEmpty {
                            Text(room)
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                                .lineLimit(1)
                        }
                        if let teacher = course.teacher, !teacher.isEmpty, blockHeight > 74 {
                            Text(teacher)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 1)
                }

                if blockHeight >= 110, let preview = resourcePreview, !preview.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1.5)
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(blockHeight >= 150 ? 3 : 2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accentColor.opacity(isHovered ? 0.24 : 0.15))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 3.5)
                    .padding(.vertical, 5)
                    .padding(.leading, 3.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accentColor.opacity(isHovered ? 0.55 : 0.24), lineWidth: 0.75)
            )
            .scaleEffect(isHovered ? 1.012 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct CourseDetailPopover: View {
    let course: CourseItem
    let resources: [LessonResourceItem]
    let assignments: [AssignmentItem]
    let onToggleAssignment: (AssignmentItem) -> Void

    private var accentColor: Color {
        course.isCancelled ? .red : course.displayColor
    }

    private var durationString: String {
        let minutes = max(0, Int(course.endDate.timeIntervalSince(course.startDate) / 60))
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h\(String(format: "%02d", m))" }
        if h > 0 { return "\(h)h00" }
        return "\(m) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 4, height: 22)

                    Text(course.subject)
                        .font(.headline)
                        .strikethrough(course.isCancelled)
                }

                if let status = course.status, !status.isEmpty {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((course.isCancelled ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                        .foregroundStyle(course.isCancelled ? .red : .orange)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("\(course.timeRangeString)  ·  \(durationString)", systemImage: "clock")
                    .font(.subheadline.monospacedDigit())

                if let room = course.room, !room.isEmpty {
                    Label("Salle \(room)", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                }

                if let teacher = course.teacher, !teacher.isEmpty {
                    Label(teacher, systemImage: "person")
                        .font(.subheadline)
                }

                if !course.groups.isEmpty {
                    Label(course.groups.joined(separator: ", "), systemImage: "person.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let memo = course.memo, !memo.isEmpty {
                Divider()
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !resources.isEmpty {
                Divider()
                Label("Contenu du cours", systemImage: "book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(resources) { res in
                            ForEach(res.contents) { content in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let title = content.title, !title.isEmpty {
                                        Text(title)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    if !content.description.isEmpty {
                                        Text(content.description)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                    if !content.attachments.isEmpty {
                                        FlowAttachmentRow(attachments: content.attachments)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if !assignments.isEmpty {
                Divider()
                Label("Devoirs pour ce cours", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assignments) { hw in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                onToggleAssignment(hw)
                            } label: {
                                Image(systemName: hw.done ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(hw.done ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(hw.description.isEmpty ? "Devoir" : hw.description)
                                    .font(.caption)
                                    .strikethrough(hw.done)
                                    .opacity(hw.done ? 0.55 : 1)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)

                                if !hw.attachments.isEmpty {
                                    FlowAttachmentRow(attachments: hw.attachments)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
    }
}

private struct CurrentTimeDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(isPulsing ? 0.0 : 0.55), lineWidth: 1.5)
                .frame(width: 7, height: 7)
                .scaleEffect(isPulsing ? 2.2 : 1.0)
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
        }
        .frame(width: 7, height: 7)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
