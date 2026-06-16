import SwiftUI
import WanderIQKit

struct PackingView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @State private var editing: EditorContext?

    private var items: [ChecklistItem] {
        trip.items
            .filter { $0.kind == .packing }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    ChecklistRow(item: item,
                                 onToggle: { model.toggle(itemID: item.id, in: trip.id) },
                                 onEdit: { editing = EditorContext(mode: .edit(item)) })
                }
                Button {
                    editing = EditorContext(mode: .add(.packing, dayID: nil))
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("Packing")
                    Spacer()
                    Text("\(items.filter(\.isDone).count)/\(items.count)").monospacedDigit()
                }
            }
            Section {
                Button {
                    model.resetPacking(in: trip.id)
                } label: {
                    Label("Reset packing list", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .warmCanvas()
        .sheet(item: $editing) { context in
            ItemEditorView(context: context, trip: trip)
        }
    }
}
