//
//  MenuExtraPresentation.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

extension MenuExtraDescriptor {
    @MainActor
    var resolvedIcon: NSImage? {
        if let bundleURL,
           let best = AssetCatalogReader.findBestIcon(in: bundleURL, hint: title)
        {
            return best.image
        }

        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let icon = app.icon
        {
            return icon
        }

        guard let bundleURL else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}

struct MenuExtraIconView: View {
    let descriptor: MenuExtraDescriptor
    let dimension: CGFloat

    var body: some View {
        if let icon = descriptor.resolvedIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dimension, height: dimension)
        } else {
            RoundedRectangle(cornerRadius: dimension / 4, style: .continuous)
                .fill(.secondary.opacity(0.2))
                .frame(width: dimension, height: dimension)
                .overlay {
                    Text(String(descriptor.displayName.prefix(1)).uppercased())
                        .font(.system(size: max(9, dimension * 0.42), weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct MenuExtraCapabilityBadge: View {
    let capability: MenuExtraCapability

    private var title: LocalizedStringKey {
        switch capability {
        case .axPress: "Clickable"
        case .openApp: "Open App"
        case .unsupported: "Unavailable"
        }
    }

    private var tint: Color {
        switch capability {
        case .axPress: .green
        case .openApp: .orange
        case .unsupported: .secondary
        }
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            }
            .foregroundStyle(tint)
    }
}
