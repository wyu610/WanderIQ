import SwiftUI
import WanderIQKit

struct PrepView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @State private var editing: EditorContext?

    var body: some View {
        List {
            section(kind: .prep, title: "Bookings")
            section(kind: .hotel, title: "Hotels")
            section(kind: .doc, title: "Documents")
        }
        .sheet(item: $editing) { context in
            ItemEditorView(context: context, trip: trip)
        }
    }

    @ViewBuilder
    private func section(kind: ItemKind, title: LocalizedStringKey) -> some View {
        let items = trip.items
            .filter { $0.kind == kind }
            .sorted { $0.sortOrder < $1.sortOrder }
        Section {
            ForEach(items) { item in
                ChecklistRow(item: item,
                             onToggle: { model.toggle(itemID: item.id, in: trip.id) },
                             onEdit: { editing = EditorContext(mode: .edit(item)) })
            }
            Button {
                editing = EditorContext(mode: .add(kind, dayID: nil))
            } label: {
                Label("Add Item", systemImage: "plus")
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(items.filter(\.isDone).count)/\(items.count)").monospacedDigit()
            }
        }
    }
}
