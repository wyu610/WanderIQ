import SwiftUI
import PlanovaKit

struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let context: EditorContext
    let trip: Trip

    @State private var label = ""
    @State private var notes = ""
    @State private var owner = ""
    @State private var dayID: UUID?
    @State private var hasTime = false
    @State private var timeValue = Date()
    @State private var hasReminder = false
    @State private var reminderDate = Date()
    @State private var place: Place?
    @State private var showingPlaceSearch = false
    @State private var loaded = false

    private var kind: ItemKind {
        switch context.mode {
        case .add(let kind, _): return kind
        case .edit(let item): return item.kind
        }
    }

    private var editedItem: ChecklistItem? {
        if case .edit(let item) = context.mode { return item }
        return nil
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $label, axis: .vertical)
                    TextField("Notes", text: $notes, axis: .vertical)
                    if kind != .doc && kind != .hotel {
                        TextField("Owner", text: $owner)
                    }
                }
                if kind == .itinerary {
                    Section {
                        Picker("Day", selection: $dayID) {
                            ForEach(trip.days) { day in
                                Text("\(day.date, format: .dateTime.month().day()) \(day.title)")
                                    .tag(Optional(day.id))
                            }
                        }
                        Toggle("Time", isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker("", selection: $timeValue, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }
                Section {
                    Toggle("Reminder", isOn: $hasReminder.animation())
                        .onChange(of: hasReminder) { _, isOn in
                            if isOn { Task { await ReminderScheduler.requestAuthorization() } }
                        }
                    if hasReminder {
                        DatePicker("", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
                if kind == .itinerary || kind == .prep || kind == .hotel {
                    Section("Place") {
                        if let place {
                            Label(place.name, systemImage: "mappin.and.ellipse")
                            Button("Remove Place", role: .destructive) { self.place = nil }
                        } else {
                            Button {
                                showingPlaceSearch = true
                            } label: {
                                Label("Attach Place", systemImage: "mappin.and.ellipse")
                            }
                        }
                    }
                }
                if editedItem != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let item = editedItem {
                                model.deleteItem(id: item.id, in: trip.id)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editedItem == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populate)
            .sheet(isPresented: $showingPlaceSearch) {
                PlaceSearchView { place = $0 }
            }
        }
    }

    private func populate() {
        guard !loaded else { return }
        loaded = true
        switch context.mode {
        case .add(_, let day):
            dayID = day ?? trip.days.first?.id
        case .edit(let item):
            label = item.label
            notes = item.notes
            owner = item.owner ?? ""
            dayID = item.dayID
            if let t = item.time, let parsed = Self.timeFormatter.date(from: t) {
                hasTime = true
                timeValue = parsed
            }
            if let r = item.reminderDate {
                hasReminder = true
                reminderDate = r
            }
            place = item.place
        }
    }

    private func save() {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespaces)
        let time = (kind == .itinerary && hasTime) ? Self.timeFormatter.string(from: timeValue) : nil
        let reminder = hasReminder ? reminderDate : nil

        if var item = editedItem {
            item.label = label
            item.notes = notes
            item.owner = trimmedOwner.isEmpty ? nil : trimmedOwner
            item.dayID = (kind == .itinerary) ? dayID : nil
            item.time = time
            item.reminderDate = reminder
            item.place = place
            model.updateItem(item, in: trip.id)
        } else {
            let item = ChecklistItem(kind: kind, label: label, notes: notes,
                                     dayID: (kind == .itinerary) ? dayID : nil,
                                     time: time,
                                     owner: trimmedOwner.isEmpty ? nil : trimmedOwner,
                                     reminderDate: reminder,
                                     place: place)
            model.addItem(item, to: trip.id)
        }
        dismiss()
    }
}
