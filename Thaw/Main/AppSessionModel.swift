//
//  AppSessionModel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Darwin.Mach

/// UI and session state owned by the active app instance.
@MainActor
final class AppSessionModel: ObservableObject {
    struct WindowCommands {
        let openWindow: (IceWindowIdentifier) -> Void
        let dismissWindow: (IceWindowIdentifier) -> Void
    }

    @Published private(set) var activeSpace = SpaceInfo.activeSpace()
    @Published var isUpdateConsentPresented = false
    @Published private(set) var openWindows = Set<IceWindowIdentifier>()

    let navigationState = AppNavigationState()

    private var cancellables = Set<AnyCancellable>()
    private var windowVisibilityCancellables = [IceWindowIdentifier: AnyCancellable]()
    private var memoryMonitoringTask: Task<Void, Never>?
    private var isRestarting = false
    private var hasCompletedRuntimeSetup = false
    private let diagLog = DiagLog(category: "AppSessionModel")
    private var windowCommands: WindowCommands?

    func completeRuntimeSetupIfNeeded(workspaceEventSource: WorkspaceEventSource) {
        guard !hasCompletedRuntimeSetup else {
            return
        }

        configureCancellables(workspaceEventSource: workspaceEventSource)
        startMemoryMonitoring()
        hasCompletedRuntimeSetup = true
    }

    func performSetup(windowCommands: WindowCommands) {
        guard self.windowCommands == nil else {
            return
        }

        self.windowCommands = windowCommands
        guard !openWindows.isEmpty else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for windowID in self.openWindows {
                windowCommands.openWindow(windowID)
            }
        }
    }

    func publisherForWindowVisibility(_ id: IceWindowIdentifier) -> AnyPublisher<Bool, Never> {
        $openWindows
            .map { $0.contains(id) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func bindWindow(_ id: IceWindowIdentifier, to window: NSWindow?) {
        windowVisibilityCancellables[id]?.cancel()

        guard let window else {
            handleWindowVisibilityChange(for: id, isVisible: false)
            return
        }

        windowVisibilityCancellables[id] = window.publisher(for: \.isVisible)
            .prepend(window.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                self?.handleWindowVisibilityChange(for: id, isVisible: isVisible)
            }
    }

    func openWindow(_ id: IceWindowIdentifier) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.openWindows.contains(id) {
                self.diagLog.debug("Window \(id) already open, activating existing window")
                self.activate(withPolicy: .regular)
                return
            }

            self.openWindows.insert(id)
            self.diagLog.debug("Opening window with id: \(id)")
            self.windowCommands?.openWindow(id)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.activate(withPolicy: .regular)
            }
        }
    }

    func dismissWindow(_ id: IceWindowIdentifier) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.openWindows.remove(id)
            self.diagLog.debug("Dismissing window with id: \(id)")
            self.windowCommands?.dismissWindow(id)
        }
    }

    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                NSRunningApplication.current.activate()
                return
            }

            NSRunningApplication.current.activate(from: frontmost)
        }
    }

    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }

    func relaunch() {
        restartSelf()
    }

    private func configureCancellables(workspaceEventSource: WorkspaceEventSource) {
        var c = Set<AnyCancellable>()

        workspaceEventSource.$isThawFrontmost
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &c)

        workspaceEventSource.$activeSpace
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] activeSpace in
                self?.activeSpace = activeSpace
            }
            .store(in: &c)

        cancellables = c
    }

    private func handleWindowVisibilityChange(for id: IceWindowIdentifier, isVisible: Bool) {
        if isVisible {
            openWindows.insert(id)
        } else {
            openWindows.remove(id)
        }

        guard id == .settings else {
            return
        }

        navigationState.isSettingsPresented = isVisible

        if isVisible {
            if !Defaults.bool(forKey: .hasSeenUpdateConsent) {
                isUpdateConsentPresented = true
            }
        } else {
            deactivate(withPolicy: .accessory)
        }
    }

    private func restartSelf() {
        guard !isRestarting else { return }
        isRestarting = true

        Task { @MainActor [diagLog] in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            config.createsNewApplicationInstance = true
            config.promptsUserIfNeeded = false

            if let url = Bundle.main.bundleURL as URL? {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                    try? await Task.sleep(for: .milliseconds(300))
                    NSApp.terminate(nil)
                } catch {
                    diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                    isRestarting = false
                }
            }
        }
    }

    private func startMemoryMonitoring() {
        memoryMonitoringTask?.cancel()
        memoryMonitoringTask = Task {
            let formatter = ISO8601DateFormatter()
            do {
                while true {
                    let memoryUsage = getMemoryInfo()
                    let timestamp = formatter.string(from: Date())

                    diagLog.info("Memory usage at \(timestamp): \(memoryUsage / 1024 / 1024)MB")

                    let memoryWarningThreshold: Int64 = 500 * 1024 * 1024
                    if memoryUsage > memoryWarningThreshold {
                        diagLog.warning("High memory usage detected: \(memoryUsage / 1024 / 1024)MB")
                    }

                    if openWindows.count > 5 {
                        diagLog.warning("Many open windows: \(openWindows.count)")
                    }

                    try await Task.sleep(for: .seconds(300))
                }
            } catch {
                // Exit cleanly when the task is cancelled.
            }
        }
    }

    private func getMemoryInfo() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / UInt32(MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        return Int64(info.phys_footprint)
    }
}
