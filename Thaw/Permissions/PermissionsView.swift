//
//  PermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct PermissionsView: View {
    @ObservedObject var manager: PermissionService
    let adapter: PermissionsFlowAdapter

    @State private var showPermissionRecoveryAlert = false
    @State private var pendingPermissionRequests = Set<ObjectIdentifier>()

    private var continueButtonText: LocalizedStringKey {
        if case .hasRequired = manager.permissionsState {
            "Continue in Limited Mode"
        } else {
            "Continue"
        }
    }

    private var continueButtonForegroundStyle: some ShapeStyle {
        switch manager.permissionsState {
        case .missing:
            AnyShapeStyle(.secondary)
        case .hasAll:
            AnyShapeStyle(.primary)
        case .hasRequired:
            AnyShapeStyle(.yellow)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical)

            permissionsStack

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .frame(width: 550)
        .fixedSize()
        .alert("Accessibility permission has not applied yet", isPresented: $showPermissionRecoveryAlert) {
            Button("Relaunch Thaw") {
                adapter.relaunch()
            }
            Button("Try Again") {
                _ = manager.refreshPermissions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS sometimes keeps the current Thaw process untrusted until the app is fully relaunched after you allow Accessibility.")
        }
    }

    private var headerView: some View {
        Label {
            Text("Permissions")
                .font(.system(size: 40, weight: .medium))
        } icon: {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 85, height: 85)
            }
        }
    }

    private var explanationBox: some View {
        IceSection {
            VStack {
                Text("\(Constants.displayName) needs your permission to discover and activate menu extras.")
                    .fontWeight(.medium)
                Text("Absolutely no personal information is collected or stored.")
                    .bold()
                    .foregroundStyle(Color(red: 0.5, green: 0.75, blue: 1))
            }
            .padding()
        }
        .font(.title3)
    }

    private var permissionsStack: some View {
        VStack {
            explanationBox
            ForEach(manager.allPermissions) { permission in
                permissionBox(permission)
            }
        }
    }

    private var footerView: some View {
        HStack {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
    }

    private var continueButton: some View {
        Button {
            handleContinue()
        } label: {
            Text(continueButtonText)
                .frame(maxWidth: .infinity)
                .foregroundStyle(continueButtonForegroundStyle)
        }
    }

    private func permissionBox(_ permission: Permission) -> some View {
        IceSection {
            VStack(spacing: 12) {
                Text(permission.title)
                    .font(.title.weight(.medium))
                    .underline()

                VStack(spacing: 2) {
                    Text("\(Constants.displayName) needs this to:")
                        .font(.title3)
                        .bold()

                    VStack(alignment: .leading) {
                        ForEach(permission.details, id: \.self) { detail in
                            HStack {
                                Text("•").bold()
                                Text(detail).fontWeight(.medium)
                            }
                        }
                    }
                }

                Button {
                    requestPermission(permission)
                } label: {
                    if permission.hasPermission {
                        Text("Permission Granted")
                            .foregroundStyle(.green)
                    } else if pendingPermissionRequests.contains(ObjectIdentifier(permission)) {
                        Text("Waiting for Permission…")
                    } else {
                        Text("Grant Permission")
                    }
                }
                .disabled(permission.hasPermission)
                .help(
                    pendingPermissionRequests.contains(ObjectIdentifier(permission))
                        ? String(localized: "Click again if macOS did not apply the permission yet.")
                        : ""
                )

                if !permission.isRequired {
                    CalloutBox("\(Constants.displayName) can work in a limited mode without this permission.") {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }

    private func requestPermission(_ permission: Permission) {
        let permissionID = ObjectIdentifier(permission)

        if manager.refreshPermission(permission) {
            pendingPermissionRequests.remove(permissionID)
            return
        }

        manager.requestPermission(permission)

        guard !pendingPermissionRequests.contains(permissionID) else {
            return
        }

        pendingPermissionRequests.insert(permissionID)
        Task {
            await manager.waitForPermission(permission)
            await MainActor.run {
                pendingPermissionRequests.remove(permissionID)
                adapter.reopenPermissionsWindow()
            }
        }
    }

    private func handleContinue() {
        let permissionsState = manager.refreshPermissions()

        guard permissionsState != .missing else {
            showPermissionRecoveryAlert = true
            return
        }

        adapter.completePermissionsFlow()
    }
}
