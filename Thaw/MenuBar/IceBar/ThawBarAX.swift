//
//  ThawBarAX.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import ApplicationServices
import Cocoa

@MainActor
enum ThawBarAX {
    private static let timeout: Float = 0.15

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var values: CFArray?
        guard AXUIElementCopyActionNames(element, &values) == .success else { return [] }
        return values as? [String] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute), let size: AXValue = attribute(element, kAXSizeAttribute), AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize
        else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func resolve(_ item: MenuBarItem) -> AXUIElement? {
        let deadline = ContinuousClock.now + .milliseconds(700)
        let pids = [item.sourcePID, item.ownerPID].compactMap(\.self).uniqued()
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, timeout)
            guard let bar: AXUIElement = attribute(app, kAXExtrasMenuBarAttribute), let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute)
            else { continue }
            let candidates = Array(children.prefix(128))
            for candidate in candidates {
                AXUIElementSetMessagingTimeout(candidate, timeout)
            }
            var frames = [CGRect?]()
            for candidate in candidates {
                guard ContinuousClock.now < deadline else { return nil }
                frames.append(frame(candidate))
            }
            let index = ThawBarMenuPolicy.candidateIndex(
                frames: frames,
                target: item.liveBounds,
                allowSingle: pid == item.sourcePID && item.tag.namespace != .controlCenter
            )
            if let index {
                return candidates[index]
            }
        }
        return nil
    }

    static func shownMenu(_ element: AXUIElement) -> AXUIElement? {
        if let menu: AXUIElement = attribute(element, "AXShownMenu") {
            return menu
        }
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        return children.first { child in
            let role: String? = attribute(child, kAXRoleAttribute)
            guard role == kAXMenuRole, let bounds = frame(child) else { return false }
            return bounds.width > 0 && bounds.height > 0
        }
    }
}

nonisolated enum ThawBarMenuPolicy {
    static func candidateIndex(frames: [CGRect?], target: CGRect, allowSingle: Bool) -> Int? {
        if allowSingle, frames.count == 1 {
            return 0
        }
        guard !target.isNull, !target.isEmpty else { return nil }
        let matches = frames.indices.filter { index in
            guard let frame = frames[index], !frame.isNull, !frame.isEmpty else { return false }
            return abs(frame.midX - target.midX) <= 8 && abs(frame.midY - target.midY) <= 8
        }
        return matches.count == 1 ? matches.first : nil
    }
}
