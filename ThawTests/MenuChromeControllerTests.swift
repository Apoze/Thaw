//
//  MenuChromeControllerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import XCTest
@testable import Thaw

@MainActor
final class MenuChromeControllerTests: XCTestCase {
    func testStatusItemIconRendererUsesHiddenVariantWhenSurfaceIsNotVisible() throws {
        let imageSet = ControlItemImageSet(
            name: .dot,
            hidden: .data(try makeSolidColorImageData(color: .systemRed)),
            visible: .data(try makeSolidColorImageData(color: .systemBlue))
        )

        let renderedImage = try XCTUnwrap(StatusItemIconRenderer.image(
            from: imageSet,
            customTemplate: false,
            isSurfaceVisible: false
        ))
        let components = try averageRGBComponents(for: renderedImage)

        XCTAssertGreaterThan(components.red, components.green)
        XCTAssertGreaterThan(components.red, components.blue)
    }

    func testStatusItemIconRendererUsesVisibleVariantWhenSurfaceIsVisible() throws {
        let imageSet = ControlItemImageSet(
            name: .dot,
            hidden: .data(try makeSolidColorImageData(color: .systemRed)),
            visible: .data(try makeSolidColorImageData(color: .systemBlue))
        )

        let renderedImage = try XCTUnwrap(StatusItemIconRenderer.image(
            from: imageSet,
            customTemplate: false,
            isSurfaceVisible: true
        ))
        let components = try averageRGBComponents(for: renderedImage)

        XCTAssertGreaterThan(components.blue, components.red)
        XCTAssertGreaterThan(components.blue, components.green)
    }

    func testStatusItemIconRendererResizesCustomImagesForMenuBarUse() throws {
        let image = NSImage(size: CGSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: image.size)).fill()
        image.unlockFocus()

        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let imageSet = ControlItemImageSet(name: .custom, image: .data(imageData))

        let renderedImage = try XCTUnwrap(StatusItemIconRenderer.image(
            from: imageSet,
            customTemplate: false,
            isSurfaceVisible: false
        ))

        XCTAssertLessThanOrEqual(renderedImage.size.width, 25.0)
        XCTAssertLessThanOrEqual(renderedImage.size.height, 17.0)
    }

    private func makeSolidColorImageData(color: NSColor, size: CGSize = CGSize(width: 12, height: 12)) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return try XCTUnwrap(image.tiffRepresentation)
    }

    private func averageRGBComponents(for image: NSImage) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let color = try XCTUnwrap(
            cgImage.averageColor(
                using: CGColorSpaceCreateDeviceRGB(),
                alphaThreshold: 0,
                option: [.ignoreAlpha]
            )
        )
        let converted = try XCTUnwrap(
            color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        )
        let components = try XCTUnwrap(converted.components)
        return (components[0], components[1], components[2])
    }
}
