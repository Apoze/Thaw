//
//  MenuBarItemContainer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A view that is drawn in the style of the menu bar.
///
/// - Important: This view performs drawing on layers above and
///   below the content view. The resulting view will probably look
///   incorrect if the content view's background is not transparent.
struct MenuBarItemContainer<Content: View>: View {
    private let activeSpace: SpaceInfo
    private let appearanceConfiguration: MenuBarAppearanceConfigurationV2
    private let colorInfo: MenuBarAverageColorInfo?
    private let usesSolidBackground: Bool
    private let content: Content

    private var foreground: Color {
        colorInfo?.isBright == true ? .black : .white
    }

    private var configuration: MenuBarAppearancePartialConfiguration {
        appearanceConfiguration.current
    }

    init(
        activeSpace: SpaceInfo,
        appearanceConfiguration: MenuBarAppearanceConfigurationV2,
        colorInfo: MenuBarAverageColorInfo?,
        usesSolidBackground: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.activeSpace = activeSpace
        self.appearanceConfiguration = appearanceConfiguration
        self.colorInfo = colorInfo
        self.usesSolidBackground = usesSolidBackground
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(foreground)
            .background {
                contentBackground
            }
            .overlay {
                contentOverlay
                    .opacity(0.2)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var contentBackground: some View {
        if usesSolidBackground {
            Color.quickAccessBackground
        } else if activeSpace.isFullscreen {
            Color.black
        } else if let colorInfo {
            Color(cgColor: colorInfo.color)
        } else {
            Color.defaultLayoutBar
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        if !activeSpace.isFullscreen {
            if case .solid = configuration.tintKind {
                Color(cgColor: configuration.tintColor)
            } else if
                case .gradient = configuration.tintKind,
                let color = configuration.tintGradient.averageColor()
            {
                Color(cgColor: color)
            }
        }
    }
}

extension View {
    func menuBarItemContainer(
        activeSpace: SpaceInfo,
        appearanceConfiguration: MenuBarAppearanceConfigurationV2,
        colorInfo: MenuBarAverageColorInfo?,
        usesSolidBackground: Bool = false
    ) -> some View {
        MenuBarItemContainer(
            activeSpace: activeSpace,
            appearanceConfiguration: appearanceConfiguration,
            colorInfo: colorInfo,
            usesSolidBackground: usesSolidBackground
        ) { self }
    }
}

extension Color {
    /// Dedicated solid background for the Quick Access surface.
    static var quickAccessBackground: Color {
        Color(nsColor: .quickAccessBackground)
    }
}

extension NSColor {
    /// Dedicated solid background for the Quick Access surface.
    static var quickAccessBackground: NSColor {
        NSColor(
            srgbRed: 0.13,
            green: 0.14,
            blue: 0.16,
            alpha: 1
        )
    }
}
