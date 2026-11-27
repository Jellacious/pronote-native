import SwiftUI

struct NotebookView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("notebookShowOnlyUnjustified") private var showOnlyUnjustified: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                SectionErrorBanner(message: error, viewModel: viewModel) {
                    await viewModel.loadNotebook(periodID: viewModel.notebook?.selectedPeriodID, forceRefresh: true)
                }
            }

            if viewModel.isLoading && viewModel.notebook == nil {
                Spacer()
                ProgressView("Chargement de la vie scolaire…")
                Spacer()
            } else if let nb = viewModel.notebook {
                let totalMinutes = nb.absences.reduce(0) { $0 + ($1.hoursMissed * 60 + $1.minutesMissed) }
                let totalHoursStr = "\(totalMinutes / 60)h\(String(format: "%02d", totalMinutes % 60))"
                let unjustifiedAbsences = nb.absences.filter { !$0.justified }.count
                let displayedAbsences = showOnlyUnjustified ? nb.absences.filter { !$0.justified } : nb.absences
                let displayedDelays = showOnlyUnjustified ? nb.delays.filter { !$0.justified } : nb.delays

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            summaryPill(title: "Heures manquées", value: totalHoursStr, color: unjustifiedAbsences > 0 ? .red : .orange)
                            summaryPill(title: "Absences", value: "\(nb.absences.count) (\(unjustifiedAbsences) non just.)", color: .orange)
                            summaryPill(title: "Retards", value: "\(nb.delays.count)", color: .blue)
                            summaryPill(title: "Observations", value: "\(nb.observations.count)", color: .purple)
                        }

                        Toggle("Afficher uniquement les non justifiées", isOn: $showOnlyUnjustified.animation(.easeInOut(duration: 0.22)))
                            .toggleStyle(.checkbox)

                        if displayedAbsences.isEmpty && displayedDelays.isEmpty && (nb.observations.isEmpty || showOnlyUnjustified) {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.green)
                                Text("Rien à signaler sur cette période")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .transition(.opacity)
                        }

                        if !displayedAbsences.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Absences").font(.headline)
                                ForEach(displayedAbsences) { absence in
                                    absenceRow(absence)
                                }
                            }
                            .transition(.opacity)
                        }

                        if !displayedDelays.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Retards").font(.headline)
                                ForEach(displayedDelays) { delay in
                                    delayRow(delay)
                                }
                            }
                            .transition(.opacity)
                        }

                        if !nb.observations.isEmpty && !showOnlyUnjustified {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Observations").font(.headline)
                                ForEach(nb.observations) { obs in
                                    observationRow(obs)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(20)
                    .animation(.easeInOut(duration: 0.22), value: showOnlyUnjustified)
                }
            } else {
                Spacer()
                Text("Aucune donnée de vie scolaire.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Vie scolaire")
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let periods = viewModel.notebook?.periods, !periods.isEmpty {
                    Picker("Période", selection: Binding(
                        get: { viewModel.notebook?.selectedPeriodID ?? periods.first?.id ?? "" },
                        set: { newID in
                            Task { await viewModel.selectNotebookPeriod(newID) }
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

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: value)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func absenceRow(_ absence: AbsenceItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateRange(absence.startDate, absence.endDate))
                    .font(.subheadline.weight(.semibold))
                Text("\(absence.hoursMissed)h\(String(format: "%02d", absence.minutesMissed)) manquées" + (absence.reason.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            justifiedBadge(absence.justified)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func delayRow(_ delay: DelayItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(formatDate(delay.date)) · \(delay.minutes) min")
                    .font(.subheadline.weight(.semibold))
                if let reason = delay.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            justifiedBadge(delay.justified)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func observationRow(_ obs: ObservationItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(obs.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDate(obs.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let subject = obs.subject, !subject.isEmpty {
                Text(subject)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let reason = obs.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func justifiedBadge(_ justified: Bool) -> some View {
        Text(justified ? "Justifiée" : "Non justifiée")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((justified ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(justified ? .green : .red)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM yyyy"
        return df.string(from: date)
    }

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM HH:mm"
        return "\(df.string(from: start)) → \(df.string(from: end))"
    }
}
