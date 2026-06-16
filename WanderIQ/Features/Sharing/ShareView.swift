import SwiftUI

struct ShareView: View {
    let tripID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var members: [TripMember] = []
    @State private var email = ""
    @State private var role = "editor"
    @State private var error: String?
    @State private var busy = false
    private let service = SharingService()

    var body: some View {
        NavigationStack {
            Form {
                Section("People") {
                    if members.isEmpty {
                        Text("No one yet").foregroundStyle(.secondary)
                    }
                    ForEach(members) { m in
                        HStack {
                            Text(m.invited_email ?? "member")
                            Spacer()
                            Text("\(m.role) · \(m.status)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Invite by email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Role", selection: $role) {
                        Text("Editor").tag("editor")
                        Text("Viewer").tag("viewer")
                    }
                    Button("Add") { Task { await add() } }
                        .disabled(busy || email.isEmpty)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .warmCanvas()
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
    }

    private func load() async {
        do { members = try await service.members(tripID: tripID) }
        catch { self.error = error.localizedDescription }
    }

    private func add() async {
        busy = true; defer { busy = false }
        self.error = nil
        do {
            try await service.addMember(tripID: tripID,
                                        email: email.trimmingCharacters(in: .whitespaces),
                                        role: role)
            email = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
