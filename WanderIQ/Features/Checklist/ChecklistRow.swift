import SwiftUI
import UIKit
import WanderIQKit

/// What the item editor sheet was opened for.
struct EditorContext: Identifiable {
    enum Mode {
        case add(ItemKind, dayID: UUID?)
        case edit(ChecklistItem)
    }
    let id = UUID()
    let mode: Mode
}

struct ChecklistRow: View {
    let item: ChecklistItem
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let time = item.time, !time.isEmpty {
                            Text(time)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.teal.opacity(0.15), in: Capsule())
                                .foregroundStyle(.teal)
                        }
                        Text(item.label)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                        if let owner = item.owner, !owner.isEmpty {
                            Text(owner)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        if item.place != nil {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                        }
                    }
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let reminder = item.reminderDate {
                        Label {
                            Text(reminder, format: .dateTime.month().day().hour().minute())
                        } icon: {
                            Image(systemName: "bell")
                        }
                        .font(.caption2)
                        .foregroundStyle(.teal)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Edit", action: onEdit).tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let place = item.place {
                Button {
                    UIApplication.shared.open(MapLink.url(for: place))
                } label: {
                    Label("Map", systemImage: "map")
                }
                .tint(.teal)
            }
        }
    }
}
