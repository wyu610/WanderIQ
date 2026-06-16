import SwiftUI
import UniformTypeIdentifiers
import WanderIQKit

struct TripListView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthController.self) private var auth
    @State private var showingNewTrip = false
    @State private var showingImporter = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?
    private let account = AccountService()

    @ViewBuilder
    private var syncStatusFooter: some View {
        switch model.sync.status {
        case .idle:
            Label("Synced", systemImage: "checkmark.circle")
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } footer: {
                    syncStatusFooter
                }
            }
            .refreshable { await model.sync.fetchNow() }
            .navigationTitle("Trips")
            .navigationDestination(for: UUID.self) { id in
                TripDetailView(tripID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Sign Out") { Task { await signOut() } }
                        Button("Delete Account…", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Trip")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewTrip = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text]) { result in
                importTrip(result)
            }
            .sheet(isPresented: $showingNewTrip) {
                NewTripView()
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("This permanently deletes your account and all your trips on every device. This can't be undone.")
            }
            .alert("Couldn't delete account", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func signOut() async {
        await auth.signOut()
        model.wipeLocalData()
    }

    private func deleteAccount() async {
        do {
            try await account.deleteAccount()
            await auth.signOut()
            model.wipeLocalData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importTrip(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "csv" {
            var trip = Trip(name: url.deletingPathExtension().lastPathComponent,
                            startDate: Date(timeIntervalSince1970: 0),
                            endDate: Date(timeIntervalSince1970: 0))
            TripExportCodec.importCSVItems(String(decoding: data, as: UTF8.self), into: &trip)
            model.addTrip(trip)
        } else if let trip = try? TripExportCodec.importJSON(data) {
            model.addTrip(trip)
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
