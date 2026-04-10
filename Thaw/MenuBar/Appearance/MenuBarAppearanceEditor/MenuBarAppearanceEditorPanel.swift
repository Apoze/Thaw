//
//  MenuBarAppearanceEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// A popover that contains a portable version of the menu bar
/// appearance editor interface.
@MainActor
final class MenuBarAppearanceEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The underlying popover.
    private var popover: NSPopover?

    /// An invisible window used to anchor the popover to the top of the screen.
    private var anchorWindow: NSWindow?

    private var editorAdapter: MenuBarAppearanceEditorAdapter?
    private var appearanceManager: MenuBarAppearanceManager?

    /// Sets up the popover.
    func performSetup(
        appearanceManager: MenuBarAppearanceManager,
        editorAdapter: MenuBarAppearanceEditorAdapter
    ) {
        self.appearanceManager = appearanceManager
        self.editorAdapter = editorAdapter
        configureObservers()
    }

    /// Shows the popover on the given screen.
    func show(on screen: NSScreen, onDone: (() -> Void)? = nil) {
        guard
            let appearanceManager,
            let editorAdapter,
            let anchorView = anchorView(for: screen)
        else {
            return
        }
        close()
        popover = makePopover(
            appearanceManager: appearanceManager,
            adapter: editorAdapter,
            onDone: onDone
        )
        updateContentSize()
        popover?.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)

        // Ensure the popover takes focus when shown.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes the popover if it is shown.
    func close() {
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_: Notification) {
        NSColorPanel.shared.hidesOnDeactivate = false
    }

    func popoverDidClose(_: Notification) {
        anchorWindow?.orderOut(nil)
        NSColorPanel.shared.hidesOnDeactivate = true
        NSColorPanel.shared.close()
    }

    // MARK: Private

    private func configureObservers() {
        guard let appearanceManager else {
            return
        }
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in
                self?.popover?.appearance = appearance
            }
            .store(in: &c)

        appearanceManager.$configuration
            .sink { [weak self] _ in
                self?.updateContentSize()
            }
            .store(in: &c)

        cancellables = c
    }

    private func makePopover(
        appearanceManager: MenuBarAppearanceManager,
        adapter: MenuBarAppearanceEditorAdapter,
        onDone: (() -> Void)?
    ) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.effectiveAppearance

        let controller = MenuBarAppearanceEditorHostingController(
            appearanceManager: appearanceManager,
            adapter: adapter,
            onDone: onDone
        )
        popover.contentViewController = controller
        return popover
    }

    private func updateContentSize() {
        guard
            let popover,
            let hostingController = popover.contentViewController as? MenuBarAppearanceEditorHostingController
        else {
            return
        }
        hostingController.updatePreferredContentSize()
        popover.contentSize = hostingController.preferredContentSize
    }

    private func anchorView(for screen: NSScreen) -> NSView? {
        let window: NSWindow
        if let anchorWindow {
            window = anchorWindow
        } else {
            let newWindow = NSWindow(
                contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .statusBar
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.contentView = NSView(
                frame: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
            anchorWindow = newWindow
            window = newWindow
        }

        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX, y: frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        return window.contentView
    }
}

// MARK: - MenuBarAppearanceEditorHostingController

@MainActor
private final class MenuBarAppearanceEditorHostingController: NSHostingController<MenuBarAppearanceEditorContentView> {
    private let appearanceManager: MenuBarAppearanceManager
    private var cancellables = Set<AnyCancellable>()

    init(
        appearanceManager: MenuBarAppearanceManager,
        adapter: MenuBarAppearanceEditorAdapter,
        onDone: (() -> Void)?
    ) {
        self.appearanceManager = appearanceManager
        super.init(
            rootView: MenuBarAppearanceEditorContentView(
                appearanceManager: appearanceManager,
                adapter: adapter,
                onDone: onDone
            )
        )
        updatePreferredContentSize()

        appearanceManager.$configuration
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.updatePreferredContentSize()
                }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreferredContentSize() {
        let configuration = appearanceManager.configuration
        let baseHeight: CGFloat = configuration.isDynamic ? 630 : 420
        let shapeBonus: CGFloat = configuration.shapeKind == .noShape ? 0 : 175
        let headingBonus: CGFloat = 32
        preferredContentSize = NSSize(width: 500, height: baseHeight + shapeBonus + headingBonus)
        view.setFrameSize(preferredContentSize)
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    @ObservedObject var appearanceManager: MenuBarAppearanceManager
    @ObservedObject var adapter: MenuBarAppearanceEditorAdapter
    let onDone: (() -> Void)?

    var body: some View {
        MenuBarAppearanceEditor(
            adapter: adapter,
            appearanceManager: appearanceManager,
            location: .panel,
            onDone: onDone
        )
    }
}
