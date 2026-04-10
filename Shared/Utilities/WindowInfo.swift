//
//  WindowInfo.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Information for a window.
struct WindowInfo {
    /// The window's identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the window.
    let ownerPID: pid_t

    /// The window's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The window's layer number.
    let layer: Int

    /// The window's title.
    let title: String?

    /// The name of the process that owns the window.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    let ownerName: String?

    /// A Boolean value that indicates whether the window is on screen.
    let isOnScreen: Bool

    /// Options that specify the identifiers in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        ///
        /// Public window APIs only expose visible windows, so this currently
        /// resolves to the same behavior as `.onScreen`.
        static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    /// Options that specify the identifiers in a menu bar window list.
    struct MenuBarWindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        ///
        /// Public window APIs only expose visible windows, so this currently
        /// resolves to the same behavior as `.onScreen`.
        static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)

        /// Specifies only windows that represent menu bar items.
        static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    /// The application that owns the window.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// A Boolean value that indicates whether the window belongs to the
    /// window server.
    var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    /// A Boolean value that indicates whether the window is a menu-related window.
    ///
    /// This property returns `true` if the window's layer corresponds to a
    /// pop-up menu, status window, or main menu, or if it belongs to the
    /// Window Server (which often owns the actual menu windows for apps).
    var isMenuRelated: Bool {
        let level = CGWindowLevel(Int32(layer))
        return level == CGWindowLevelForKey(.popUpMenuWindow) ||
            level == CGWindowLevelForKey(.popUpMenuWindow) - 1 ||
            level == CGWindowLevelForKey(.statusWindow) ||
            level == CGWindowLevelForKey(.mainMenuWindow) ||
            isWindowServerWindow
    }

    /// Creates a window with the given dictionary.
    fileprivate init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: Any],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let layer = info[kCGWindowLayer] as? Int
        else {
            return nil
        }
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.title = info[kCGWindowName] as? String
        self.ownerName = info[kCGWindowOwnerName] as? String
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }

    /// Creates a window with the given window identifier.
    ///
    /// - Parameter windowID: A window identifier.
    init?(windowID: CGWindowID) {
        guard
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [CFDictionary],
            let dictionary = list.first,
            let window = WindowInfo(dictionary: dictionary)
        else {
            return nil
        }
        self = window
    }

    /// Returns the current bounds of the window.
    func currentBounds() -> CGRect? {
        WindowInfo(windowID: windowID)?.bounds
    }
}

// MARK: - Window List

extension WindowInfo {
    private static let diagLog = DiagLog(category: "WindowInfo")

    private static func menuBarHeightEstimate(for screen: NSScreen) -> CGFloat {
        let visibleInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return visibleInset > 0 ? visibleInset : NSStatusBar.system.thickness
    }

    private static var menuBarBandHeightEstimate: CGFloat {
        max(
            44,
            NSScreen.screens.map { menuBarHeightEstimate(for: $0) + 8 }.max() ?? (NSStatusBar.system.thickness + 8)
        )
    }

    private static func menuBarBand(for screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarBandHeightEstimate,
            width: screen.frame.width,
            height: menuBarBandHeightEstimate
        )
    }

    private static func intersectsMenuBarBand(_ bounds: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            menuBarBand(for: screen).intersects(bounds)
        }
    }

    private static func isMenuBarWindow(_ window: WindowInfo) -> Bool {
        window.isWindowServerWindow &&
            window.layer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            intersectsMenuBarBand(window.bounds)
    }

    private static func isMenuBarItemWindow(_ window: WindowInfo) -> Bool {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return abs(window.layer - statusLevel) <= 1 &&
            intersectsMenuBarBand(window.bounds)
    }

    private static func createWindowDictionaries(option: WindowListOption = []) -> [CFDictionary] {
        var cgOptions: CGWindowListOption = [.excludeDesktopElements]

        if option.contains(.onScreen) || option.contains(.activeSpace) {
            cgOptions.insert(.optionOnScreenOnly)
        } else {
            cgOptions.insert(.optionAll)
        }

        guard let list = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [CFDictionary] else {
            diagLog.warning("createWindowDictionaries: CGWindowListCopyWindowInfo returned nil")
            return []
        }

        return list
    }

    /// Creates a list of windows from the given list of window identifiers.
    ///
    /// - Parameter windowIDs: A list of window identifiers.
    static func createWindows(from windowIDs: [CGWindowID]) -> [WindowInfo] {
        guard !windowIDs.isEmpty else {
            return []
        }

        let windowLookup = Dictionary(
            uniqueKeysWithValues: createWindowDictionaries()
                .compactMap { WindowInfo(dictionary: $0) }
                .map { ($0.windowID, $0) }
        )

        let orderedWindows = windowIDs.compactMap { windowLookup[$0] }
        if orderedWindows.count != windowIDs.count {
            diagLog.debug(
                "createWindows: resolved \(orderedWindows.count) windows for \(windowIDs.count) requested window IDs"
            )
        }

        return orderedWindows
    }

    /// Creates a list of windows using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func createWindows(option: WindowListOption = []) -> [WindowInfo] {
        createWindowDictionaries(option: option).compactMap { WindowInfo(dictionary: $0) }
    }

    /// Creates a list of on-screen windows using the public CGWindowList API.
    static func createOnScreenWindowsPublic(excludingDesktopElements: Bool = true) -> [WindowInfo] {
        var options: CGWindowListOption = [.optionOnScreenOnly]
        if excludingDesktopElements {
            options.insert(.excludeDesktopElements)
        }
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [CFDictionary] else {
            diagLog.warning("createOnScreenWindowsPublic: CGWindowListCopyWindowInfo returned nil")
            return []
        }
        return list.compactMap { WindowInfo(dictionary: $0) }
    }

    /// Creates a list of windows for the elements in the menu bar
    /// using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func createMenuBarWindows(option: MenuBarWindowListOption = []) -> [WindowInfo] {
        var windowOptions = WindowListOption()
        if option.contains(.onScreen) || option.contains(.activeSpace) {
            windowOptions.insert(.onScreen)
        }

        let windows = createWindows(option: windowOptions)

        if option.contains(.itemsOnly) {
            return windows.filter(isMenuBarItemWindow)
        }

        return windows.filter { isMenuBarWindow($0) || isMenuBarItemWindow($0) }
    }
}

// MARK: - Specific Windows

extension WindowInfo {
    /// Returns the wallpaper window for the given display from the
    /// given list of windows.
    static func wallpaperWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayBounds = CGDisplayBounds(display)
        return windows.first { window in
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
                window.title?.hasPrefix("Wallpaper") == true &&
                displayBounds.contains(window.bounds)
        }
    }

    /// Creates and returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        wallpaperWindow(from: createWindows(option: .onScreen), for: display)
    }

    /// Returns the menu bar window for the given display from the
    /// given list of windows.
    static func menuBarWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        let displayBounds = CGDisplayBounds(display)
        return windows.first { window in
            isMenuBarWindow(window) &&
                window.isOnScreen &&
                displayBounds.contains(window.bounds)
        }
    }

    /// Creates and returns the menu bar window for the given display.
    static func menuBarWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        menuBarWindow(from: createMenuBarWindows(option: .onScreen), for: display)
    }
}

// MARK: WindowInfo: Codable

extension WindowInfo: Codable {}

// MARK: WindowInfo: Equatable

extension WindowInfo: Equatable {
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.windowID == rhs.windowID &&
            lhs.ownerPID == rhs.ownerPID &&
            lhs.bounds == rhs.bounds &&
            lhs.layer == rhs.layer &&
            lhs.title == rhs.title &&
            lhs.ownerName == rhs.ownerName &&
            lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: WindowInfo: Hashable

extension WindowInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
        hasher.combine(layer)
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
    }
}
