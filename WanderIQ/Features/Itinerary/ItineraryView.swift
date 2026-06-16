import SwiftUI
import WanderIQKit

struct ItineraryView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @State private var expanded: Set<UUID> = []
    @State private var didSetInitialExpansion = false
    @State private var editing: EditorContext?
    @State private var mapDay: TripDay?

    var body: some View {
        List {
            ForEach(trip.days) { day in
                daySection(day)
            }
        }
        .listStyle(.sidebar)
        .warmCanvas()
        .sheet(item: $editing) { context in
            ItemEditorView(context: context, trip: trip)
        }
        .sheet(item: $mapDay) { day in
            DayMapView(day: day,
                       items: trip.items.filter { $0.dayID == day.id })
        }
        .onAppear(perform: setInitialExpansion)
    }

    @ViewBuilder
    private func daySection(_ day: TripDay) -> some View {
        let items = ItinerarySort.daySorted(
            trip.items
                .filter { $0.dayID == day.id }
                .sorted { $0.sortOrder < $1.sortOrder }
        )
        Section(isExpanded: expansionBinding(for: day.id)) {
            ForEach(items) { item in
                ChecklistRow(item: item,
                             onToggle: { model.toggle(itemID: item.id, in: trip.id) },
                             onEdit: { editing = EditorContext(mode: .edit(item)) })
            }
            Button {
                editing = EditorContext(mode: .add(.itinerary, dayID: day.id))
            } label: {
                Label("Add Item", systemImage: "plus")
            }
            if items.contains(where: { $0.place?.latitude != nil }) {
                Button {
                    mapDay = day
                } label: {
                    Label("Day Map", systemImage: "map")
                }
            }
        } header: {
            DayHeader(day: day,
                      done: items.filter(\.isDone).count,
                      total: items.count,
                      isToday: Calendar.current.isDateInToday(day.date))
        }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func setInitialExpansion() {
        guard !didSetInitialExpansion else { return }
        didSetInitialExpansion = true
        if let today = trip.days.first(where: { Calendar.current.isDateInToday($0.date) }) {
            expanded = [today.id]
        } else if let first = trip.days.first {
            expanded = [first.id]
        }
    }
}

struct DayHeader: View {
    let day: TripDay
    let done: Int
    let total: Int
    let isToday: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(day.date, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                if !day.title.isEmpty {
                    Text(day.title).font(.subheadline)
                }
                if !day.city.isEmpty {
                    Text(day.city).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if isToday {
                Text("Today")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.teal, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(done)/\(total)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(done == total && total > 0 ? .green : .secondary)
        }
        .textCase(nil)
    }
}
