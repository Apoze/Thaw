//
//  MenuChromeController.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

@MainActor
enum StatusItemIconRenderer {
    static func image(
        from imageSet: ControlItemImageSet,
        customTemplate: Bool,
        isSurfaceVisible: Bool
    ) -> NSImage? {
        let sourceImage = isSurfaceVisible ? imageSet.visible : imageSet.hidden
        guard let image = sourceImage.nsImage(customTemplate: customTemplate) else {
            return nil
        }

        guard case .custom = imageSet.name else {
            return image
        }

        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let ratio = max(originalWidth / 25, originalHeight / 17)
        let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
        return image.resized(to: newSize)
    }
}

@MainActor
final class MenuChromeController: NSObject, ObservableObject {
    struct Dependencies {
        let generalSettings: GeneralSettings
        let commandRouter: CommandRouter
        let displayService: DisplayService
        let iceBarAdapter: IceBarAdapter
        let searchPanelAdapter: MenuBarSearchPanelAdapter
        let appearanceManager: MenuBarAppearanceManager
        let appearanceEditorAdapter: MenuBarAppearanceEditorAdapter
    }

    private let diagLog = DiagLog(category: "MenuChromeController")

    private var dependencies: Dependencies?
    private var cancellables = Set<AnyCancellable>()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    @Published private(set) var statusItemFrameSnapshot: CGRect?

    private let iceBarPanel = IceBarPanel()
    private let searchPanel = MenuBarSearchPanel()
    private let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    func performSetup(with dependencies: Dependencies) {
        self.dependencies = dependencies

        iceBarPanel.performSetup(with: dependencies.iceBarAdapter)
        searchPanel.performSetup(with: dependencies.searchPanelAdapter)
        appearanceEditorPanel.performSetup(
            appearanceManager: dependencies.appearanceManager,
            editorAdapter: dependencies.appearanceEditorAdapter
        )

        configureStatusItem()
        configureCancellables()
    }

    var statusItemFrame: CGRect? {
        guard
            let button = statusItem.button,
            let window = button.window
        else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var currentIceBarGroup: VirtualGroup? {
        iceBarPanel.currentVirtualGroup
    }

    func isIceBarVisible(for group: VirtualGroup) -> Bool {
        iceBarPanel.isVisible && iceBarPanel.currentVirtualGroup == group
    }

    var currentIceBarPresentationID: UUID {
        iceBarPanel.presentationID
    }

    var isSearchPanelVisible: Bool {
        searchPanel.isVisible
    }

    func showIceBar(
        group: VirtualGroup,
        on screen: NSScreen,
        triggeredByHotkey: Bool
    ) {
        iceBarPanel.show(
            group: group,
            on: screen,
            triggeredByHotkey: triggeredByHotkey
        )
    }

    func closeIceBar() {
        iceBarPanel.close()
    }

    func closeIceBarIfPresentationMatches(_ presentationID: UUID?) {
        guard let presentationID else {
            iceBarPanel.close()
            return
        }

        guard iceBarPanel.presentationID == presentationID else {
            return
        }

        iceBarPanel.close()
    }

    func closeIceBarIfPresented(group: VirtualGroup) {
        guard iceBarPanel.currentVirtualGroup == group else {
            return
        }
        iceBarPanel.close()
    }

    func showSearchPanel(on screen: NSScreen? = nil) {
        searchPanel.show(on: screen)
    }

    func closeSearchPanel() {
        searchPanel.close()
    }

    func closeSearchPanelIfPresentationMatches(_ presentationID: UUID?) {
        guard let presentationID else {
            searchPanel.close()
            return
        }

        guard searchPanel.presentationID == presentationID else {
            return
        }

        searchPanel.close()
    }

    @objc func showAppearanceEditorPanel() {
        guard let screen = dependencies?.displayService.preferredPresentationScreen() ?? NSScreen.main else {
            return
        }
        appearanceEditorPanel.show(on: screen)
    }

    private func configureStatusItem() {
        statusItem.isVisible = dependencies?.generalSettings.showIceIcon ?? true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemAction(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = Constants.displayName
        updateStatusItemAppearance()
    }

    private func configureCancellables() {
        guard let dependencies else {
            return
        }

        var c = Set<AnyCancellable>()

        dependencies.generalSettings.$showIceIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showIceIcon in
                self?.statusItem.isVisible = showIceIcon
                self?.updateStatusItemAppearance()
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        Publishers.CombineLatest(
            dependencies.generalSettings.$iceIcon,
            dependencies.generalSettings.$customIceIconIsTemplate
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateStatusItemAppearance()
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        Publishers.Merge(
            iceBarPanel.publisher(for: \.isVisible).map { _ in },
            searchPanel.publisher(for: \.isVisible).map { _ in }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.updateStatusItemAppearance()
        }
        .store(in: &c)

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        statusItem.publisher(for: \.button)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        statusItem.publisher(for: \.button)
            .removeNil()
            .flatMap { $0.publisher(for: \.window) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        statusItem.publisher(for: \.button)
            .removeNil()
            .flatMap { $0.publisher(for: \.window).removeNil() }
            .flatMap { $0.publisher(for: \.frame) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemFrameSnapshot()
            }
            .store(in: &c)

        cancellables = c
        updateStatusItemFrameSnapshot()
    }

    private func updateStatusItemAppearance() {
        guard let dependencies else {
            statusItem.button?.image = nil
            return
        }

        let image = StatusItemIconRenderer.image(
            from: dependencies.generalSettings.iceIcon,
            customTemplate: dependencies.generalSettings.customIceIconIsTemplate,
            isSurfaceVisible: iceBarPanel.isVisible || searchPanel.isVisible
        )
        statusItem.button?.image = image
    }

    @objc private func handleStatusItemAction(_ sender: Any?) {
        guard let commandRouter = dependencies?.commandRouter else {
            return
        }

        guard let event = NSApp.currentEvent else {
            commandRouter.route(.toggleThawBar, source: "status-item")
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusItemMenu(sender)
        } else {
            commandRouter.route(.toggleThawBar, source: "status-item")
        }
    }

    private func showStatusItemMenu(_ sender: Any?) {
        let menu = NSMenu(title: Constants.displayName)

        let searchItem = NSMenuItem(
            title: String(localized: "Search"),
            action: #selector(openSearch),
            keyEquivalent: ""
        )
        searchItem.target = self
        menu.addItem(searchItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(sender)
        statusItem.menu = nil
    }

    @objc private func openSearch() {
        dependencies?.commandRouter.route(.openSearch, source: "status-item-menu")
    }

    @objc private func openSettings() {
        dependencies?.commandRouter.route(.openSettings, source: "status-item-menu")
    }

    @objc private func quitApp() {
        diagLog.info("Status item requested app termination")
        NSApp.terminate(nil)
    }

    private func updateStatusItemFrameSnapshot() {
        guard statusItem.isVisible else {
            statusItemFrameSnapshot = nil
            return
        }
        statusItemFrameSnapshot = statusItemFrame
    }
}
