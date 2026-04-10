//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @ObservedObject var adapter: MenuBarLayoutEditorAdapter

    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false
    @State private var isConfirmingIconReset = false
    @State private var hasOverrides = !AssetCatalogReader.overrides.isEmpty
    @State private var draggedDescriptorID: String?

    var body: some View {
        IceForm(spacing: 20) {
            header
            layoutBars
            iconOverrideControls
            resetControls
        }
        .task {
            await adapter.refresh()
        }
    }

    private var header: some View {
        IceSection {
            VStack(spacing: 3) {
                Text("Arrange menu extras across Quick Access, Panel, and Archive.")
                    .font(.title3.bold())
                Text("This editor controls Thaw’s own layout. It never changes the native macOS menu bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Items in Quick Access stay in the native menu bar and also appear in Thaw’s compact bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Right-click an item for quick actions.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(VirtualGroup.allCases) { group in
                layoutBar(for: group)
            }
        }
    }

    @ViewBuilder
    private func layoutBar(for group: VirtualGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.localizedTitle)
                    .font(.headline)
                    .padding(.leading, 8)

                Spacer()

                Text("\(adapter.descriptors(in: group).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }

            VirtualLayoutBar(
                descriptors: adapter.descriptors(in: group),
                group: group,
                draggedDescriptorID: $draggedDescriptorID,
                moveDescriptor: adapter.moveDescriptor
            )
        }
    }

    private var iconOverrideControls: some View {
        IceSection {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon overrides")
                        .font(.headline)
                    Text("Export your overrides to share or reset back to application defaults.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Export to Clipboard") {
                        exportOverridesToClipboard()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOverrides)

                    Button("Reset All") {
                        isConfirmingIconReset = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasOverrides)
                }
            }
        }
        .onAppear {
            hasOverrides = !AssetCatalogReader.overrides.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            hasOverrides = !AssetCatalogReader.overrides.isEmpty
        }
        .alert("Reset all icon overrides?", isPresented: $isConfirmingIconReset) {
            Button("Reset", role: .destructive) {
                resetAllIconOverrides()
            }
            Button("Cancel", role: .cancel) {
                isConfirmingIconReset = false
            }
        } message: {
            Text("This will remove all custom icon selections and revert every icon to its default.")
        }
    }

    private var resetControls: some View {
        IceSection {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset Thaw layout")
                        .font(.headline)
                    Text("Restores Thaw’s suggested layout, clears Quick Access ordering, and keeps everything inside Thaw’s own UI contract.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    isConfirmingReset = true
                } label: {
                    if isResettingLayout {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore Suggested Layout")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout)
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Restore suggested layout?", isPresented: $isConfirmingReset) {
            Button("Restore", role: .destructive) {
                resetLayout()
            }
            Button("Cancel", role: .cancel) {
                isConfirmingReset = false
            }
        } message: {
            Text("This restores Thaw’s own grouping and ordering. It does not modify the native macOS menu bar.")
        }
    }

    private func exportOverridesToClipboard() {
        let overrides = AssetCatalogReader.overrides
        guard !overrides.isEmpty else { return }
        if let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }

    private func resetAllIconOverrides() {
        AssetCatalogReader.overrides = [:]
        hasOverrides = false
    }

    private func resetLayout() {
        isResettingLayout = true
        resetStatus = nil

        Task { @MainActor in
            await adapter.resetSuggestedLayout()
            resetStatus = .success
            isResettingLayout = false
        }
    }

    private enum ResetStatus {
        case success

        var message: String {
            switch self {
            case .success:
                "Default Thaw layout restored."
            }
        }

        var isError: Bool {
            false
        }
    }
}

private struct VirtualLayoutBar: View {
    let descriptors: [MenuExtraDescriptor]
    let group: VirtualGroup
    @Binding var draggedDescriptorID: String?
    let moveDescriptor: (String, VirtualGroup, String?) -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if descriptors.isEmpty {
                    Text(emptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(descriptors) { descriptor in
                        VirtualLayoutItemChip(
                            descriptor: descriptor,
                            isBeingDragged: draggedDescriptorID == descriptor.id,
                            moveToGroup: { destination in
                                moveDescriptor(descriptor.id, destination, nil)
                            }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let sourceID = items.first, sourceID != descriptor.id else {
                                return false
                            }
                            moveDescriptor(sourceID, group, descriptor.id)
                            draggedDescriptorID = nil
                            return true
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .background {
            backgroundShape
                .fill(Color.secondary.opacity(0.08))
        }
        .overlay {
            backgroundShape
                .strokeBorder(.quaternary)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let sourceID = items.first else {
                return false
            }
            moveDescriptor(sourceID, group, nil)
            draggedDescriptorID = nil
            return true
        }
    }

    private var emptyMessage: String {
        switch group {
        case .pinned:
            "Drop items here to show them in Thaw’s top bar"
        case .hidden:
            "Drop items here to keep them one click away"
        case .archive:
            "Drop items here to keep them out of the main panel"
        }
    }
}

private struct VirtualLayoutItemChip: View {
    @State private var isHovered = false

    let descriptor: MenuExtraDescriptor
    let isBeingDragged: Bool
    let moveToGroup: (VirtualGroup) -> Void

    var body: some View {
        MenuExtraIconView(descriptor: descriptor, dimension: 22)
            .frame(width: 30, height: 30)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(isHovered || isBeingDragged ? 0.18 : 0.08))
            }
            .overlay(alignment: .bottomTrailing) {
                if descriptor.capability == .unsupported {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
            .help("\(descriptor.displayName)\n\(descriptor.applicationName)")
            .contextMenu {
                ForEach(VirtualGroup.allCases) { group in
                    Button(group.localizedTitle) {
                        moveToGroup(group)
                    }
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .draggable(descriptor.id) {
                MenuExtraIconView(descriptor: descriptor, dimension: 22)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
    }
}
