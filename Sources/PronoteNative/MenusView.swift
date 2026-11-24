import SwiftUI

struct MenusView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                SectionErrorBanner(message: error, viewModel: viewModel) {
                    await viewModel.loadMenus(forceRefresh: true)
                }
            }

            if viewModel.isLoading && viewModel.menus == nil {
                Spacer()
                ProgressView("Chargement du menu de la cantine…")
                Spacer()
            } else if let snapshot = viewModel.menus, !snapshot.days.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(snapshot.days) { day in
                            MenuDayCardView(day: day)
                        }
                    }
                    .padding(20)
                }
                .id(snapshot.days.first?.id)
                .transition(.opacity)
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Aucun menu disponible pour cette semaine")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .background(AmbientBackground())
        .animation(.easeInOut(duration: 0.22), value: viewModel.menus?.days.first?.id)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Cantine")
                    .font(.title3.bold())
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Button {
                        Task { await viewModel.shiftMenusWeek(by: -7) }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button("Cette semaine") {
                        viewModel.menusDate = Date()
                        Task { await viewModel.loadMenus(forceRefresh: true) }
                    }
                    Button {
                        Task { await viewModel.shiftMenusWeek(by: 7) }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

private struct MenuDayCardView: View {
    let day: MenuDayItem
    @State private var isHovered: Bool = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayTitle(day.date))
                    .font(.headline)
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                Spacer()
                if isToday {
                    Text("Aujourd'hui")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !day.lunch.isEmpty {
                mealBlock(title: "Midi", sections: day.lunch)
            }
            if !day.dinner.isEmpty {
                Divider()
                mealBlock(title: "Soir", sections: day.dinner)
            }
            if day.lunch.isEmpty && day.dinner.isEmpty {
                Text("Pas de service")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.025 : 0))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isToday
                        ? Color.accentColor.opacity(isHovered ? 0.65 : 0.45)
                        : (isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func mealBlock(title: String, sections: [MealSectionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(sections) { sec in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sec.category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(sec.dishes) { dish in
                        HStack(spacing: 6) {
                            Text(dish.name)
                                .font(.subheadline)
                            ForEach(dish.labels, id: \.self) { lbl in
                                Text(lbl)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEEE d MMM"
        return df.string(from: date).capitalized
    }
}
