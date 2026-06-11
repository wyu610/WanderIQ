import SwiftUI
import PlanovaKit

struct TripListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewTrip = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.store.trips) { trip in
                    NavigationLink(value: trip.id) {
                        TripRowView(trip: trip)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteTrip(id: model.store.trips[index].id)
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: UUID.self) { id in
                TripDetailView(tripID: id)
            }
            .toolbar {
                Button {
                    showingNewTrip = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingNewTrip) {
                NewTripView()
            }
        }
    }
}

struct TripRowView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name).font(.headline)
            HStack(spacing: 8) {
                Text(trip.startDate, format: .dateTime.year().month().day())
                Text("–")
                Text(trip.endDate, format: .dateTime.month().day())
                if !trip.items.isEmpty {
                    Spacer()
                    Text("\(trip.items.filter(\.isDone).count)/\(trip.items.count)")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct NewTripView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                DatePicker("Start", selection: $start, displayedComponents: .date)
                DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        var days: [TripDay] = []
        var date = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: max(start, end))
        while date <= last {
            days.append(TripDay(date: date, city: "", title: ""))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        model.addTrip(Trip(name: name, startDate: start, endDate: end, days: days))
        dismiss()
    }
}
