import SwiftUI

struct GradesView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var groupBySubject: Bool = false

    private struct ComputedGradesSummary {
        let overallAverage: String?
        let classAverage: String?
        let subjectAverages: [SubjectAverageItem]
        let isComputedLocally: Bool
    }

    private func computeSummary(for snapshot: GradesSnapshot) -> ComputedGradesSummary {
        // Si Pronote fournit déjà la moyenne générale et les moyennes par matière, on les utilise
        let hasServerOverall = snapshot.overallAverage != nil
        let hasServerSubjects = snapshot.subjectAverages.contains { $0.studentNumeric != nil }

        if hasServerOverall && hasServerSubjects {
            return ComputedGradesSummary(
                overallAverage: snapshot.overallAverage,
                classAverage: snapshot.classAverage,
                subjectAverages: snapshot.subjectAverages,
                isComputedLocally: false
            )
        }

        // Sinon calcul automatique pondéré ramené sur 20 à partir des notes
        let grouped = Dictionary(grouping: snapshot.grades) { $0.subject }
        var computedSubjects: [SubjectAverageItem] = []

        // Couleur de secours depuis les moyennes existantes si disponibles
        let existingMap = Dictionary(uniqueKeysWithValues: snapshot.subjectAverages.map { ($0.subject, $0) })

        for subject in grouped.keys.sorted() {
            let grades = grouped[subject] ?? []
            var weightedSum = 0.0
            var totalCoef = 0.0
            var classWeightedSum = 0.0
            var classTotalCoef = 0.0

            for g in grades {
                guard let val = g.valueNumeric, g.outOfNumeric > 0 else { continue }
                let score20 = (val / g.outOfNumeric) * 20.0
                let coef = max(0.0, g.coefficient)
                if g.isBonus {
                    if score20 > 10.0 {
                        weightedSum += (score20 - 10.0) * coef
                    }
                } else {
                    weightedSum += score20 * coef
                    totalCoef += coef
                }

                if let clsNum = Double(g.classAverageDisplay.replacingOccurrences(of: ",", with: ".")), g.outOfNumeric > 0 {
                    let cls20 = (clsNum / g.outOfNumeric) * 20.0
                    if !g.isBonus {
                        classWeightedSum += cls20 * coef
                        classTotalCoef += coef
                    }
                }
            }

            let studentAvg = totalCoef > 0 ? min(20.0, weightedSum / totalCoef) : nil
            let classAvg = classTotalCoef > 0 ? min(20.0, classWeightedSum / classTotalCoef) : nil
            let existing = existingMap[subject]

            computedSubjects.append(
                SubjectAverageItem(
                    id: existing?.id ?? subject,
                    subject: subject,
                    colorHex: existing?.colorHex ?? grades.first?.colorHex,
                    studentDisplay: studentAvg.map { formatNumber($0) } ?? (existing?.studentDisplay ?? "–"),
                    studentNumeric: studentAvg ?? existing?.studentNumeric,
                    classDisplay: classAvg.map { formatNumber($0) } ?? (existing?.classDisplay ?? "–"),
                    outOfDisplay: "20",
                    outOfNumeric: 20
                )
            )
        }

        let validStudent = computedSubjects.compactMap { $0.studentNumeric }
        let overallStr = snapshot.overallAverage ?? (validStudent.isEmpty ? nil : formatNumber(validStudent.reduce(0, +) / Double(validStudent.count)))

        let validClass = computedSubjects.compactMap { Double($0.classDisplay.replacingOccurrences(of: ",", with: ".")) }
        let classStr = snapshot.classAverage ?? (validClass.isEmpty ? nil : formatNumber(validClass.reduce(0, +) / Double(validClass.count)))

        return ComputedGradesSummary(
            overallAverage: overallStr,
            classAverage: classStr,
            subjectAverages: computedSubjects.isEmpty ? snapshot.subjectAverages : computedSubjects,
            isComputedLocally: true
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                SectionErrorBanner(message: error, viewModel: viewModel) {
                    await viewModel.loadGrades(periodID: viewModel.grades?.selectedPeriodID, forceRefresh: true)
                }
            }

            if viewModel.isLoading && viewModel.grades == nil {
                Spacer()
                ProgressView("Chargement des notes…")
                Spacer()
            } else if let snapshot = viewModel.grades {
                let summary = computeSummary(for: snapshot)
                let colorMap = Dictionary(uniqueKeysWithValues: summary.subjectAverages.map { ($0.subject, $0.displayColor) })
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryCards(summary)

                        if !summary.subjectAverages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Moyennes par matière")
                                    .font(.headline)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                                    ForEach(summary.subjectAverages) { avg in
                                        SubjectAverageCardView(avg: avg)
                                    }
                                }
                            }
                        }

                        LazyVStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Détail des notes")
                                    .font(.headline)
                                Spacer()
                                Picker("Tri", selection: $groupBySubject) {
                                    Text("Chronologique").tag(false)
                                    Text("Par matière").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            if snapshot.grades.isEmpty {
                                Text("Aucune note pour cette période.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else if groupBySubject {
                                let grouped = Dictionary(grouping: snapshot.grades) { $0.subject }
                                ForEach(grouped.keys.sorted(), id: \.self) { subject in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(subject)
                                            .font(.subheadline.weight(.bold))
                                            .padding(.top, 6)
                                        ForEach(grouped[subject] ?? []) { grade in
                                            GradeRowView(grade: grade, color: colorMap[grade.subject] ?? grade.displayColor)
                                        }
                                    }
                                }
                            } else {
                                ForEach(snapshot.grades) { grade in
                                    GradeRowView(grade: grade, color: colorMap[grade.subject] ?? grade.displayColor)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                Text("Aucune donnée de notes.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(AmbientBackground())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Notes")
                    .font(.title3.bold())
            }

            ToolbarItem(placement: .principal) {
                if let periods = viewModel.grades?.periods, !periods.isEmpty {
                    Picker("Période", selection: Binding(
                        get: { viewModel.grades?.selectedPeriodID ?? periods.first?.id ?? "" },
                        set: { newID in
                            Task { await viewModel.selectGradesPeriod(newID) }
                        }
                    )) {
                        ForEach(periods) { period in
                            Text(period.name).tag(period.id)
                        }
                    }
                    .frame(maxWidth: 220)
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private func summaryCards(_ summary: ComputedGradesSummary) -> some View {
        HStack(spacing: 14) {
            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Moyenne générale")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if summary.isComputedLocally {
                            Text("Calculée")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(summary.overallAverage ?? "–")
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.25), value: summary.overallAverage)
                        Text("/ 20")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Moyenne de classe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(summary.classAverage ?? "–")
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.25), value: summary.classAverage)
                        Text("/ 20")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formatNumber(_ val: Double) -> String {
        String(format: "%.2f", val).replacingOccurrences(of: ".", with: ",")
    }
}

private struct SubjectAverageCardView: View {
    let avg: SubjectAverageItem
    @State private var animatedRatio: Double = 0

    private var targetRatio: Double {
        guard let num = avg.studentNumeric, avg.outOfNumeric > 0 else { return 0 }
        return min(1, max(0, num / avg.outOfNumeric))
    }

    var body: some View {
        GlassCard(cornerRadius: 14, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(avg.subject)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(avg.studentDisplay)/\(avg.outOfDisplay)")
                        .font(.subheadline.bold().monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: avg.studentDisplay)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(avg.displayColor)
                            .frame(width: geo.size.width * animatedRatio)
                    }
                }
                .frame(height: 6)

                Text("Classe : \(avg.classDisplay)/\(avg.outOfDisplay)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: avg.classDisplay)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                animatedRatio = targetRatio
            }
        }
        .onChange(of: targetRatio) { _, newValue in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                animatedRatio = newValue
            }
        }
    }
}

private struct GradeRowView: View {
    let grade: GradeItem
    let color: Color
    @State private var isHovered: Bool = false

    private var normalizedScore20: Double? {
        guard let val = grade.valueNumeric, grade.outOfNumeric > 0 else { return nil }
        return (val / grade.outOfNumeric) * 20.0
    }

    private var scoreColor: Color? {
        guard let on20 = normalizedScore20 else { return nil }
        if on20 >= 14 { return .green }
        if on20 >= 10 { return .accentColor }
        return .orange
    }

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(grade.subject)
                            .font(.subheadline.weight(.semibold))
                        if let comment = grade.comment, !comment.isEmpty {
                            Text("· \(comment)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 10) {
                        Text(shortDate(grade.date))
                        Text("Coef. \(formatCoef(grade.coefficient))")
                        Text("Classe : \(grade.classAverageDisplay)")
                        Text("Min \(grade.minDisplay) · Max \(grade.maxDisplay)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(grade.valueDisplay)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(scoreColor ?? .primary)
                        Text("/\(grade.outOfDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let on20 = normalizedScore20, grade.outOfNumeric != 20 {
                        Text("= \(formatNumber(on20))/20")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(scoreColor ?? .secondary)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.035 : 0))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isHovered ? 0.28 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }

    private func formatCoef(_ c: Double) -> String {
        c.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(c)) : String(format: "%.1f", c)
    }

    private func formatNumber(_ val: Double) -> String {
        String(format: "%.2f", val).replacingOccurrences(of: ".", with: ",")
    }
}
