import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private weak var viewModel: AppViewModel?
    private weak var settings: AppSettings?
    private let onOpenMain: () -> Void

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: AppViewModel, settings: AppSettings, onOpenMain: @escaping () -> Void) {
        self.viewModel = viewModel
        self.settings = settings
        self.onOpenMain = onOpenMain
        super.init()

        settings.$menuBarEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        settings.$menuBarShowNextCourseText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        settings.$menuBarShowCourseName
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel?.refreshMenuBarText()
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        viewModel.$menuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        updateStatusItem()
    }

    func updateStatusItem() {
        guard let settings, let viewModel else { return }

        if !settings.menuBarEnabled {
            popover?.performClose(nil)
            popover = nil
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            NSApp.setActivationPolicy(.regular)
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Pronote Native")
                button.imagePosition = .imageLeading
                button.target = self
                button.action = #selector(togglePopover(_:))
            }
            statusItem = item
        }

        if let button = statusItem?.button {
            if settings.menuBarShowNextCourseText, let text = viewModel.menuBarText, !text.isEmpty {
                button.title = " \(text)"
            } else {
                button.title = ""
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }

        guard let button = statusItem?.button, let viewModel, let settings else { return }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                viewModel: viewModel,
                onOpenMain: { [weak self, weak pop] in
                    pop?.performClose(nil)
                    self?.onOpenMain()
                }
            )
            .environmentObject(settings)
            .preferredColorScheme(settings.colorScheme)
        )
        self.popover = pop
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    let onOpenMain: () -> Void
    @State private var selectedDayIndex: Int = 0

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.credentials == nil {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Connecte-toi à Pronote")
                        .font(.headline)
                    Button("Ouvrir Pronote") {
                        onOpenMain()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                coursesContent(at: now)
                Divider()
                footerView
            }
        }
        .padding(18)
        .frame(width: 350)
    }

    @ViewBuilder
    private func coursesContent(at now: Date) -> some View {
        let days = viewModel.upcomingScheduledDays(from: now)
        let idx = min(selectedDayIndex, max(0, days.count - 1))
        let selectedDay = days.isEmpty ? nil : days[idx]
        let currentCourse = (selectedDay?.isToday == true)
            ? selectedDay?.courses.first(where: { !$0.isCancelled && $0.startDate <= now && $0.endDate > now })
            : nil
        let upcomingCourses = Array((selectedDay?.courses ?? []).filter { $0.id != currentCourse?.id }.prefix(6))

        if let current = currentCourse {
            let total = max(1, current.endDate.timeIntervalSince(current.startDate))
            let elapsed = min(total, max(0, now.timeIntervalSince(current.startDate)))
            let remainingMin = max(1, Int(ceil(current.endDate.timeIntervalSince(now) / 60)))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EN COURS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(current.displayColor)
                    Spacer()
                    Text("encore \(remainingMin) min")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(current.subject)
                    .font(.title3.bold())
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(current.timeRangeString)
                    if let room = current.room, !room.isEmpty {
                        Text("· \(room)")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

                ProgressView(value: elapsed, total: total)
                    .tint(current.displayColor)
            }

            if !upcomingCourses.isEmpty {
                Divider()
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDay?.title ?? "Aujourd'hui")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if days.count > 1 {
                    HStack(spacing: 4) {
                        Button {
                            selectedDayIndex = max(0, idx - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(idx <= 0)

                        Button {
                            selectedDayIndex = min(days.count - 1, idx + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(idx >= days.count - 1)
                    }
                }
            }

            if upcomingCourses.isEmpty {
                if currentCourse == nil {
                    Text("Aucun cours à venir")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upcomingCourses) { course in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(course.displayColor)
                                .frame(width: 4, height: 34)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(hhmm(course.startDate))
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                Text(hhmm(course.endDate))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 46, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.subject)
                                    .font(.body.weight(.semibold))
                                    .strikethrough(course.isCancelled)
                                    .opacity(course.isCancelled ? 0.5 : 1)
                                    .lineLimit(1)

                                if let room = course.room, !room.isEmpty {
                                    Text(room)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 10) {
            Button {
                onOpenMain()
            } label: {
                Text("Ouvrir Pronote")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quitter")
                    .font(.callout)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func hhmm(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}
