//
//  MenuBarSearchPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Ifrit
import SwiftUI

private struct MenuBarSearchPanelKey: EnvironmentKey {
    static let defaultValue: MenuBarSearchPanel? = nil
}

extension EnvironmentValues {
    var menuBarSearchPanel: MenuBarSearchPanel? {
        get { self[MenuBarSearchPanelKey.self] }
        set { self[MenuBarSearchPanelKey.self] = newValue }
    }
}

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarSearchPanel")

    /// Runtime surface required by the search panel.
    private var panelAdapter: MenuBarSearchPanelAdapter?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Model for menu bar item search.
    private let model = MenuBarSearchModel()

    /// Read-only search adapter over the discovery runtime.
    private var searchAdapter: MenuBarSearchAdapter?

    /// Monitor for mouse down events.
    private lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
        guard
            let self,
            event.window !== self
        else {
            return event
        }
        close()
        return event
    }

    /// Monitor for key down events.
    private lazy var keyDownMonitor = EventMonitor.universal(
        for: [.keyDown]
    ) { [weak self] event in
        let keyCode = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)

        if keyCode == .comma, modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option), !modifiers.contains(.shift) {
            self?.close()
            self?.panelAdapter?.openSettings()
            return nil
        }

        if keyCode == .e, modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option), !modifiers.contains(.shift) {
            self?.startEditingSelectedItem()
            return nil
        }

        return event
    }

    @MainActor
    func startEditingSelectedItem() {
        guard let selection = model.selection,
              case .item = selection,
              let descriptor = descriptor(for: selection)
        else {
            return
        }
        model.editingName = descriptor.customName ?? ""
        model.editingItemID = descriptor.id
    }

    func descriptor(for selection: MenuBarSearchModel.ItemID) -> MenuExtraDescriptor?
    {
        switch selection {
        case let .item(id):
            return searchAdapter?.descriptor(withID: id)
        case .header:
            return nil
        }
    }

    @MainActor
    func saveEditingName() {
        guard let editingItemID = model.editingItemID else {
            return
        }
        Self.diagLog.debug("Saving editing name for descriptor: \(editingItemID)")
        defer {
            model.editingItemID = nil
            model.editingName = ""
        }

        guard
            let searchAdapter,
            let descriptor = searchAdapter.descriptor(withID: editingItemID)
        else {
            Self.diagLog.error("Cannot save editing name, no matching item")
            return
        }
        let newName = model.editingName.trimmingCharacters(in: .whitespaces)
        Task { @MainActor [searchAdapter] in
            await searchAdapter.rename(
                descriptorID: descriptor.id,
                to: newName.isEmpty ? nil : newName
            )
        }
        model.objectWillChange.send()
    }

    /// The default screen to show the panel on.
    var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    private(set) var presentationID = UUID()

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool {
        true
    }

    /// Creates a menu bar search panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .titled, .fullSizeContentView, .nonactivatingPanel,
                .utilityWindow, .hudWindow,
            ],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [
            .fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace,
        ]
        // Close panel when it loses key focus (e.g., another app gets focus)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        // setFrameAutosaveName("MenuBarSearchPanel") // Manual persistence is used instead.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Called when the panel loses key focus.
    @objc private func panelResignedKey(_: Notification) {
        close()
    }

    /// Performs the initial setup of the panel.
    func performSetup(with panelAdapter: MenuBarSearchPanelAdapter) {
        self.panelAdapter = panelAdapter
        searchAdapter = panelAdapter.searchAdapter
        configureCancellables()
        model.performSetup(
            with: self,
            displayConfigurationDidChangePublisher: panelAdapter.displayConfigurationDidChangePublisher
        )
    }

    /// Configures the internal observers for the panel.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        // Save the frame when the application terminates.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if let screen = self.screen {
                    self.saveFrameForDisplay(screen)
                }
            }
            .store(in: &c)

        // Close the panel when the active space changes, or when the screen parameters change.
        Publishers.Merge(
            panelAdapter?.activeSpaceDidChangePublisher ?? Empty<Void, Never>().eraseToAnyPublisher(),
            panelAdapter?.displayConfigurationDidChangePublisher ?? Empty<Void, Never>().eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            // Force close and clear any cached screen references on hot-plug
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Shows the search panel on the given screen.
    func show(on screen: NSScreen? = nil) {
        guard let panelAdapter, let searchAdapter else {
            return
        }

        presentPreparedPanel(
            on: screen,
            panelAdapter: panelAdapter,
            searchAdapter: searchAdapter
        )
    }

    @MainActor
    private func presentPreparedPanel(
        on screen: NSScreen?,
        panelAdapter: MenuBarSearchPanelAdapter,
        searchAdapter: MenuBarSearchAdapter
    ) {
        guard let screen = screen ?? defaultScreen else {
            Self.diagLog.error("Missing screen for search panel")
            return
        }

        // Important that we set the navigation state before updating the cache.
        panelAdapter.setSearchPresented(true)

        let hostingView = MenuBarSearchHostingView(
            searchAdapter: searchAdapter,
            model: model,
            displayID: screen.displayID,
            panel: self
        )
        hostingView.setFrameSize(hostingView.intrinsicContentSize)

        // Try to load saved frame for current display
        if let savedFrame = loadFrameForDisplay(screen) {
            // Convert relative position back to absolute coordinates
            let visibleFrame = screen.visibleFrame
            let absoluteFrame = CGRect(
                x: savedFrame.origin.x + visibleFrame.minX,
                y: savedFrame.origin.y + visibleFrame.minY,
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            // Ensure frame is within this display's visible frame
            let adjustedFrame = CGRect(
                x: max(visibleFrame.minX, min(absoluteFrame.origin.x, visibleFrame.maxX - hostingView.intrinsicContentSize.width)),
                y: max(visibleFrame.minY, min(absoluteFrame.origin.y, visibleFrame.maxY - hostingView.intrinsicContentSize.height)),
                width: hostingView.intrinsicContentSize.width,
                height: hostingView.intrinsicContentSize.height
            )

            setFrame(adjustedFrame, display: false)
        } else {
            // No saved frame for this display, center on screen
            let centered = CGPoint(
                x: screen.visibleFrame.midX - hostingView.intrinsicContentSize.width / 2,
                y: screen.visibleFrame.midY - hostingView.intrinsicContentSize.height / 2
            )

            setFrame(CGRect(origin: centered, size: hostingView.intrinsicContentSize), display: false)
        }

        contentView = hostingView
        presentationID = UUID()
        makeKeyAndOrderFront(nil)

        mouseDownMonitor.start()
        keyDownMonitor.start()
    }

    /// Toggles the panel's visibility.
    func toggle() {
        if isVisible {
            close()
        } else {
            show(on: nil)
        }
    }

    @MainActor
    func handleActivation(
        _ result: PanelInteractionResult,
        expectedPresentationID: UUID?
    ) {
        panelAdapter?.handleActivation(
            result,
            expectedPresentationID: expectedPresentationID
        )
    }

    /// Dismisses the search panel.
    @MainActor
    override func close() {
        // Only save if window is actually visible and has content
        if isVisible, let screen = screen, contentView != nil {
            saveFrameForDisplay(screen)
        }
        model.searchText = ""
        model.editingItemID = nil
        super.close()
        contentView = nil
        presentationID = UUID()
        mouseDownMonitor.stop()
        keyDownMonitor.stop()
        panelAdapter?.setSearchPresented(false)
    }

    override func cancelOperation(_: Any?) {
        if model.editingItemID != nil {
            cancelEditing()
        } else if model.searchText != "" {
            model.searchText = ""
        } else {
            close()
        }
    }

    @MainActor
    func cancelEditing() {
        model.editingItemID = nil
        model.editingName = ""
    }

    /// Saves the frame for a specific display.
    private func saveFrameForDisplay(_ screen: NSScreen) {
        // Only save if window is visible and has content
        guard isVisible, contentView != nil else {
            return
        }

        // Get current window frame and ensure we're saving from the right screen
        let currentFrame = frame
        let actualScreen = NSScreen.screens.first { $0.visibleFrame.intersects(currentFrame) } ?? screen

        guard let uuidString = DisplayUUID.string(for: actualScreen.displayID) else {
            return
        }

        // Save position relative to the display's visible frame for consistency
        let visibleFrame = actualScreen.visibleFrame
        let relativeFrame = CGRect(
            x: currentFrame.minX - visibleFrame.minX,
            y: currentFrame.minY - visibleFrame.minY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"
        UserDefaults.standard.set(relativeFrame.dictionaryRepresentation as NSDictionary, forKey: keyString)
        UserDefaults.standard.synchronize()
    }

    /// Loads the saved frame for a specific display.
    private func loadFrameForDisplay(_ screen: NSScreen) -> CGRect? {
        guard let uuidString = DisplayUUID.string(for: screen.displayID) else {
            return nil
        }
        let keyString = "\(Defaults.Key.menuBarSearchPanelFrameWithConfig.rawValue)\(uuidString)"

        guard let frameDict = UserDefaults.standard.dictionary(forKey: keyString) else {
            return nil
        }

        guard let savedFrame = CGRect(dictionaryRepresentation: frameDict as CFDictionary) else {
            return nil
        }
        return savedFrame
    }

    func openSettings() {
        panelAdapter?.openSettings()
    }

    func openAdvancedSettings() {
        panelAdapter?.openAdvancedSettings()
    }
}

private final class MenuBarSearchHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        searchAdapter: MenuBarSearchAdapter,
        model: MenuBarSearchModel,
        displayID: CGDirectDisplayID,
        panel: MenuBarSearchPanel
    ) {
        super.init(
            rootView: AnyView(
                MenuBarSearchContentView(displayID: displayID, panel: panel) { [weak panel] in
                    panel?.close()
                }
                .environmentObject(searchAdapter)
                .environmentObject(model)
            )
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

private struct MenuBarSearchContentView: View {
    private typealias ListItem = SectionedListItem<MenuBarSearchModel.ItemID>

    @EnvironmentObject var searchAdapter: MenuBarSearchAdapter
    @EnvironmentObject var model: MenuBarSearchModel
    @FocusState private var searchFieldIsFocused: Bool

    let displayID: CGDirectDisplayID
    let panel: MenuBarSearchPanel
    let closePanel: () -> Void

    private var hasItems: Bool {
        !searchAdapter.descriptors.isEmpty
    }

    private var bottomBarPadding: CGFloat {
        if #available(macOS 26.0, *) { 7 } else { 5 }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            mainContent
            bottomBar
        }
        .environment(\.menuBarSearchPanel, panel)
        .background {
            VisualEffectView(material: .sheet, blendingMode: .behindWindow)
                .opacity(0.5)
        }
        .frame(width: 600, height: 400)
        .fixedSize()
        .task {
            searchFieldIsFocused = true
        }
        .onChange(of: model.searchText, initial: true) {
            updateDisplayedItems()
            selectFirstDisplayedItem()
        }
        .onChange(of: searchAdapter.snapshot, initial: true) {
            updateDisplayedItems()
            if model.selection == nil {
                selectFirstDisplayedItem()
            }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        let promptText = Text("Search menu extras…")

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                TextField(text: $model.searchText, prompt: promptText) {
                    promptText
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .font(.system(size: 18))
                .textContentType(.none)
                .autocorrectionDisabled(true)

                Spacer()
            }
            .padding(15)
            .focused($searchFieldIsFocused)

            Divider()
        }
    }

    private func openPermissionsSettings() {
        closePanel()
        panel.openAdvancedSettings()
    }

    @ViewBuilder
    private var mainContent: some View {
        if hasItems {
            SectionedList(
                selection: $model.selection,
                items: $model.displayedItems,
                isEditing: model.editingItemID != nil
            )
            .contentPadding(8)
            .scrollContentBackground(.hidden)
        } else {
            VStack {
                Text("Loading menu extras…")
                    .font(.title2)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack {
            SettingsButton {
                closePanel()
                panel.openSettings()
            }

            Spacer()

            if let selection = model.selection, let descriptor = panel.descriptor(for: selection) {
                if model.editingItemID == nil {
                    EditNameButton {
                        panel.startEditingSelectedItem()
                    }
                    ShowItemButton(descriptor: descriptor) {
                        performAction(for: descriptor)
                    }
                } else {
                    EditDiscardButton {
                        panel.cancelEditing()
                    }
                    EditConfirmButton {
                        panel.saveEditingName()
                    }
                }
            }
        }
        .padding(bottomBarPadding)
        .background(.thinMaterial)
        .buttonStyle(BottomBarButtonStyle())
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func selectFirstDisplayedItem() {
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
    }

    private func updateDisplayedItems() {
        struct SearchItem: Searchable {
            let listItem: ListItem
            let title: String

            var properties: [FuseProp] {
                [FuseProp(title)]
            }
        }
        typealias ScoredItem = (listItem: ListItem, score: Double)

        let searchItems: [SearchItem] = VirtualGroup.allCases
            .reduce(into: []) { items, name in
                let headerItem = ListItem.header(id: .header(name)) {
                    Text(name.localizedTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                items.append(SearchItem(listItem: headerItem, title: name.id))

                for descriptor in searchAdapter.descriptors(in: name, on: displayID)
                    .reversed()
                {
                    let listItem = ListItem.item(id: .item(descriptor.id)) {
                        performAction(for: descriptor)
                    } content: {
                        MenuBarSearchItemView(descriptor: descriptor)
                    }
                    items.append(SearchItem(listItem: listItem, title: descriptor.displayName))
                }
            }

        if model.searchText.isEmpty {
            model.displayedItems = searchItems.map { $0.listItem }
        } else {
            let selectableItems = searchItems.filter {
                $0.listItem.isSelectable
            }
            // Using weighted search via FuseProp
            let fuseResults = model.fuse.searchSync(model.searchText, in: selectableItems, by: \.properties)

            model.displayedItems = fuseResults
                .map { result in
                    let item = selectableItems[result.index]
                    let score = 1.0 - result.diffScore
                    return ScoredItem(item.listItem, score)
                }
                .sorted { (lhs: ScoredItem, rhs: ScoredItem) -> Bool in
                    lhs.score > rhs.score
                }
                .map { $0.listItem }
        }
    }

    private func performAction(for descriptor: MenuExtraDescriptor) {
        if model.editingItemID == descriptor.id {
            return
        }
        Task {
            let presentationID = await MainActor.run { panel.presentationID }
            let result = await searchAdapter.activate(canonicalID: descriptor.canonicalID)
            await MainActor.run {
                panel.handleActivation(
                    result,
                    expectedPresentationID: presentationID
                )
            }
        }
    }
}

private struct EditNameButton: View {
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(String(localized: "Edit Name"))
                    .padding(.leading, 5)

                HStack(spacing: 0) {
                    Text("⌘")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background {
                    backgroundShape
                        .fill(.regularMaterial)
                        .brightness(0.25)
                        .opacity(0.5)
                }
                .foregroundStyle(.secondary)

                Text("+")

                HStack(spacing: 0) {
                    Text("E")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background {
                    backgroundShape
                        .fill(.regularMaterial)
                        .brightness(0.25)
                        .opacity(0.5)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EditConfirmButton: View {
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(
                    String(localized: "Confirm")
                )
                .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .bold()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background {
                        backgroundShape
                            .fill(.regularMaterial)
                            .brightness(0.25)
                            .opacity(0.5)
                    }
            }
        }
    }
}

private struct EditDiscardButton: View {
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(
                    String(localized: "Discard")
                )
                .padding(.leading, 5)

                Text("⎋")
                    .font(.system(size: 12))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background {
                        backgroundShape
                            .fill(.regularMaterial)
                            .brightness(0.25)
                            .opacity(0.5)
                    }
            }
        }
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.iceCubeStroke)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

private struct ShowItemButton: View {
    let descriptor: MenuExtraDescriptor
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(descriptor.activationLabel)
                .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .bold()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background {
                        backgroundShape
                            .fill(.regularMaterial)
                            .brightness(0.25)
                            .opacity(0.5)
                    }
            }
        }
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(3)
            .background {
                borderShape
                    .fill(.regularMaterial)
                    .brightness(0.25)
                    .opacity(
                        configuration.isPressed ? 0.5 : isHovering ? 0.25 : 0
                    )
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

@MainActor
private let controlCenterIcon: NSImage? = {
    guard
        let app =
        NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.apple.controlcenter"
            )
            .first
    else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @Environment(\.menuBarSearchPanel) var panel
    @EnvironmentObject var model: MenuBarSearchModel

    let descriptor: MenuExtraDescriptor
    @FocusState private var isEditing: Bool

    private var appIcon: NSImage? {
        if descriptor.bundleIdentifier == "com.apple.controlcenter" {
            return controlCenterIcon
        }
        if let bundleURL = descriptor.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
        return NSRunningApplication(processIdentifier: descriptor.ownerPID)?.icon
    }

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var dimension: CGFloat {
        if #available(macOS 26.0, *) { 26 } else { 24 }
    }

    private var padding: CGFloat {
        if #available(macOS 26.0, *) { 6 } else { 8 }
    }

    var body: some View {
        HStack {
            if model.editingItemID == descriptor.id {
                HStack(spacing: 8) {
                    labelIcon
                    TextField(descriptor.title, text: $model.editingName)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .focused($isEditing)
                        .textContentType(.none)
                        .autocorrectionDisabled(true)
                        .onSubmit {
                            panel?.saveEditingName()
                        }
                        .onExitCommand {
                            model.editingItemID = nil
                            model.editingName = ""
                        }
                        .onAppear {
                            isEditing = true
                        }
                        .onDisappear {
                            isEditing = false
                        }
                }
            } else {
                Label {
                    labelText
                } icon: {
                    labelIcon
                }
            }
            Spacer()
            itemView
        }
        .padding(padding)
    }

    private var labelText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(descriptor.displayName)
            Text(descriptor.applicationName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var labelIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dimension, height: dimension)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.gradient)
                .strokeBorder(Color.primary.gradient.quaternary)
                .overlay {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .padding(3)
                        .shadow(radius: 2)
                }
                .padding(2.5)
                .shadow(color: .black.opacity(0.1), radius: 2)
                .frame(width: dimension, height: dimension)
        }
    }

    private var itemView: some View {
        HStack(spacing: 6) {
            Text(descriptor.activationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if descriptor.capability == .unsupported {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "return")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: dimension)
        .background {
            backgroundShape
                .fill(.regularMaterial)
        }
        .overlay {
            backgroundShape
                .strokeBorder(.quaternary)
        }
    }
}
