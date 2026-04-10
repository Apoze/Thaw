//
//  IceBar.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "IceBarPanel")
    /// Compact bar adapter for session state and actions.
    private weak var adapter: IceBarAdapter?

    /// Manager for the Ice Bar's color.
    private let colorManager = IceBarColorManager()

    /// The currently displayed virtual group.
    private(set) var currentVirtualGroup: VirtualGroup?

    /// Distinguishes successive presentations so old async work cannot
    /// mutate a newer IceBar session.
    private(set) var presentationID = UUID()

    /// A Boolean value that indicates whether to show the panel at
    /// the mouse pointer's location, regardless of the user's
    /// settings.
    private var hotkeyLocationOverride = false

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a new Ice Bar panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "\(Constants.displayName) Bar")
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
    }

    /// Sets up the panel.
    func performSetup(with adapter: IceBarAdapter) {
        self.adapter = adapter
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide the panel when the active space or screen parameters change.
        Publishers.Merge(
            adapter?.activeSpaceDidChangePublisher ?? Empty<Void, Never>().eraseToAnyPublisher(),
            adapter?.displayConfigurationDidChangePublisher ?? Empty<Void, Never>().eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.hide()
        }
        .store(in: &c)

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let adapter else {
            return
        }

        func getOrigin(for iceBarLocation: IceBarLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let defaultOriginY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: defaultOriginY)
            }

            if hotkeyLocationOverride, let location = PointerLocation.appKit {
                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width
                let lowerBoundY = screen.frame.minY
                let upperBoundY = screen.frame.maxY - frame.height

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... (upperBoundX > lowerBoundX ? upperBoundX : lowerBoundX))
                let y = (location.y - frame.height / 2).clamped(to: lowerBoundY ... (upperBoundY > lowerBoundY ? upperBoundY : lowerBoundY))

                return CGPoint(x: x, y: y)
            }

            switch iceBarLocation {
            case .dynamic:
                let menuBarRect = CGRect(
                    x: screen.frame.minX,
                    y: screen.frame.maxY - menuBarHeight,
                    width: screen.frame.width,
                    height: menuBarHeight
                )
                if menuBarRect.contains(NSEvent.mouseLocation) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .iceIcon)
            case .mousePointer:
                guard let location = PointerLocation.appKit else {
                    return getOrigin(for: .iceIcon)
                }

                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width

                guard lowerBoundX <= upperBoundX else {
                    return originForRightOfScreen
                }

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... upperBoundX)

                return CGPoint(x: x, y: defaultOriginY)
            case .iceIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let itemBounds = adapter.statusItemFrame
                else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound ... upperBound), y: defaultOriginY)
            }
        }

        let location = adapter.iceBarLocation(for: screen.displayID)
        setFrameOrigin(getOrigin(for: location))
    }

    /// Shows the panel on the given screen, displaying a virtual group.
    func show(
        group: VirtualGroup,
        on screen: NSScreen,
        triggeredByHotkey: Bool = false
    ) {
        guard let adapter else {
            return
        }

        hotkeyLocationOverride = triggeredByHotkey && adapter.hotkeyUsesPointerLocation
        adapter.setIceBarPresented(true)
        presentationID = UUID()
        currentVirtualGroup = group

        contentView = VirtualIceBarHostingView(
            adapter: adapter,
            colorManager: colorManager,
            screen: screen,
            group: group,
            panel: self
        )

        updateOrigin(for: screen)
        orderFrontRegardless()
    }

    /// Hides the panel.
    func hide() {
        close()
    }

    override func close() {
        CustomTooltipPanel.shared.dismiss()
        contentView = nil
        orderOut(nil)
        super.close()
        presentationID = UUID()
        currentVirtualGroup = nil
        adapter?.setIceBarPresented(false)
    }
}

// MARK: - VirtualIceBarHostingView

private final class VirtualIceBarHostingView: NSHostingView<VirtualIceBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        adapter: IceBarAdapter,
        colorManager: IceBarColorManager,
        screen: NSScreen,
        group: VirtualGroup,
        panel: IceBarPanel
    ) {
        let rootView = VirtualIceBarContentView(
            adapter: adapter,
            colorManager: colorManager,
            screen: screen,
            group: group,
            panel: panel
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: VirtualIceBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

// MARK: - VirtualIceBarContentView

private struct VirtualIceBarContentView: View {
    @ObservedObject var adapter: IceBarAdapter
    @ObservedObject var colorManager: IceBarColorManager

    @State private var frame = CGRect.zero
    @State private var activationInFlight = Set<String>()

    let screen: NSScreen
    let group: VirtualGroup
    weak var panel: IceBarPanel?

    private var configuration: MenuBarAppearanceConfigurationV2 {
        adapter.appearanceManager.configuration
    }

    private var descriptors: [MenuExtraDescriptor] {
        adapter.descriptors(in: group, on: screen.displayID)
    }

    private var horizontalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 3
        }
        return configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
        }
        return screen.hasNotch ? 0 : 2
    }

    private var contentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - adapter.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var clipShape: some InsettableShape {
        if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: frame.height / 2, style: .circular)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: frame.height / 4, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous)
        }
    }

    private var isLightQuickAccessBackground: Bool {
        (NSColor.quickAccessBackground.cgColor.brightness ?? 0) > 0.67
    }

    var body: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(
                    activeSpace: adapter.activeSpace,
                    appearanceConfiguration: configuration,
                    colorInfo: colorManager.colorInfo,
                    usesSolidBackground: true
                )
                .foregroundStyle(isLightQuickAccessBackground ? .black : .white)
                .clipShape(clipShape)

            if configuration.current.hasBorder {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        .padding(5)
        .background {
            clipShape
                .fill(Color.quickAccessBackground)
        }
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
    }

    @ViewBuilder
    private var content: some View {
        if !adapter.isAccessibilityGranted {
            HStack(spacing: 8) {
                Text("Accessibility permission is required")
                Button("Open Settings") {
                    panel?.close()
                    adapter.requestAccessibilityPermission()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
        } else if !adapter.isReady && descriptors.isEmpty {
            HStack {
                Text("Loading menu extras…")
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
        } else if descriptors.isEmpty {
            Text("No items in this surface")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(descriptors) { descriptor in
                        VirtualIceBarItemView(
                            descriptor: descriptor,
                            isLoading: activationInFlight.contains(descriptor.id),
                            tooltipDelay: adapter.tooltipDelay,
                            isLightBackground: isLightQuickAccessBackground
                        ) { intent in
                            activate(descriptor, intent: intent)
                        }
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == screen.frame.width)
            .defaultScrollAnchor(.trailing)
        }
    }

    private func activate(
        _ descriptor: MenuExtraDescriptor,
        intent: ActivationIntent
    ) {
        guard descriptor.isInteractive else {
            return
        }
        guard activationInFlight.insert(descriptor.id).inserted else {
            return
        }

        let descriptorID = descriptor.id
        let presentationID = panel?.presentationID

        Task {
            let result = await adapter.activate(descriptor: descriptor, intent: intent)
            await MainActor.run {
                adapter.handleActivation(result, expectedPresentationID: presentationID)
                activationInFlight.remove(descriptorID)
            }
        }
    }
}

private struct VirtualIceBarItemView: View {
    @State private var isHovered = false

    let descriptor: MenuExtraDescriptor
    let isLoading: Bool
    let tooltipDelay: TimeInterval
    let isLightBackground: Bool
    let activate: (ActivationIntent) -> Void

    var body: some View {
        MenuExtraIconView(descriptor: descriptor, dimension: 20)
            .frame(width: 24, height: 24)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((isLightBackground ? Color.black : Color.white).opacity(isHovered ? 0.15 : 0))
                    .padding(.vertical, 2)
            }
            .overlay(alignment: .bottomTrailing) {
                statusOverlay
            }
            .contentShape(Rectangle())
            .help(descriptor.displayName)
            .overlay {
                VirtualIceBarItemClickView(
                    itemTitle: descriptor.displayName,
                    tooltipDelay: tooltipDelay,
                    leftClickAction: {
                        activate(.primary)
                    },
                    rightClickAction: {
                        activate(.secondary)
                    },
                    onHover: { hovering in
                        isHovered = hovering
                    }
                )
            }
            .accessibilityLabel(descriptor.displayName)
            .accessibilityHint(Text(descriptor.activationLabel))
            .opacity(descriptor.isInteractive ? 1 : 0.7)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
                .padding(2)
        } else if descriptor.capability == .unsupported {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.yellow)
                .padding(2)
        }
    }
}

private struct VirtualIceBarItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        let title: String
        let tooltipDelay: TimeInterval
        let leftClickAction: () -> Void
        let rightClickAction: () -> Void
        let onHover: (Bool) -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now
        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        private lazy var tooltipController = CustomTooltipController(text: title, view: self)
        private var tooltipTrackingArea: NSTrackingArea?

        init(
            title: String,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.title = title
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tooltipTrackingArea {
                removeTrackingArea(tooltipTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tooltipTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            tooltipController.scheduleShow(delay: tooltipDelay)
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            tooltipController.cancel()
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            tooltipController.cancel()
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            tooltipController.cancel()
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let itemTitle: String
    let tooltipDelay: TimeInterval
    let leftClickAction: () -> Void
    let rightClickAction: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> NSView {
        Represented(
            title: itemTitle,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }

    func updateNSView(_: NSView, context _: Context) {}
}
