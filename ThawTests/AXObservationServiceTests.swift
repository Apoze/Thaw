//
//  AXObservationServiceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import XCTest
@testable import Thaw

@MainActor
final class AXObservationServiceTests: XCTestCase {
    func testObservationInvalidationEmitterCoalescesSamePendingInvalidation() async throws {
        let accumulator = InvalidationAccumulator()
        var capturedContinuation: AsyncStream<DiscoveryInvalidation>.Continuation?
        let stream = AsyncStream<DiscoveryInvalidation>(bufferingPolicy: .bufferingNewest(4)) {
            capturedContinuation = $0
        }
        guard let continuation = capturedContinuation else {
            XCTFail("Failed to create invalidation stream continuation")
            return
        }

        let emitter = ObservationInvalidationEmitter(
            delay: .milliseconds(30),
            continuation: continuation
        )

        let consumer = Task {
            for await invalidation in stream {
                await accumulator.append(invalidation)
            }
        }

        await emitter.schedule(bundleID: "com.example.ax", processIdentifier: 101)
        await emitter.schedule(bundleID: "com.example.ax", processIdentifier: 101)

        try? await Task.sleep(for: .milliseconds(120))
        await emitter.finish()
        _ = await consumer.value

        let values = await accumulator.snapshot()
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(
            values.first,
            .axStructureChanged(bundleID: "com.example.ax", processIdentifier: 101)
        )
    }

    func testObservationInvalidationEmitterCoalescesDistinctPIDsAndGlobalRecoverySeparately() async throws {
        let accumulator = InvalidationAccumulator()
        var capturedContinuation: AsyncStream<DiscoveryInvalidation>.Continuation?
        let stream = AsyncStream<DiscoveryInvalidation>(bufferingPolicy: .bufferingNewest(8)) {
            capturedContinuation = $0
        }
        guard let continuation = capturedContinuation else {
            XCTFail("Failed to create invalidation stream continuation")
            return
        }

        let emitter = ObservationInvalidationEmitter(
            delay: .milliseconds(30),
            continuation: continuation
        )

        let consumer = Task {
            for await invalidation in stream {
                await accumulator.append(invalidation)
            }
        }

        await emitter.schedule(bundleID: "com.example.ax", processIdentifier: 101)
        await emitter.schedule(bundleID: "com.example.ax", processIdentifier: 101)
        await emitter.schedule(bundleID: "com.example.ax", processIdentifier: 202)
        await emitter.scheduleObservationRecovery()
        await emitter.scheduleObservationRecovery()

        try? await Task.sleep(for: .milliseconds(120))
        await emitter.finish()
        _ = await consumer.value

        let values = await accumulator.snapshot()
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(
            values.filter { $0 == .axStructureChanged(bundleID: "com.example.ax", processIdentifier: 101) }.count,
            1
        )
        XCTAssertEqual(
            values.filter { $0 == .axStructureChanged(bundleID: "com.example.ax", processIdentifier: 202) }.count,
            1
        )
        XCTAssertEqual(values.filter { $0 == .observationRecoveryRequired }.count, 1)
    }
}

private actor InvalidationAccumulator {
    private var values = [DiscoveryInvalidation]()

    func append(_ invalidation: DiscoveryInvalidation) {
        values.append(invalidation)
    }

    func snapshot() -> [DiscoveryInvalidation] {
        values
    }
}
