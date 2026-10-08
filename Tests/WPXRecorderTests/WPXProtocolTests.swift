import Foundation
import XCTest
@testable import WPXRecorder

final class WPXProtocolTests: XCTestCase {
    private let firstCapturedFrame: [UInt8] = [
        0xEE, 0x23, 0x00, 0xC5, 0x00, 0x01, 0x00,
        0x67, 0x46, 0x20, 0x46, 0x68, 0x05, 0x04, 0x00,
        0x68, 0x01, 0x00, 0xA7, 0x6D, 0x33, 0x00, 0x41,
        0x00, 0x00, 0x00, 0x58, 0x00, 0x25, 0x00, 0xF3,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]

    func testDecodesCapturedMeasurementAndTemperatureFields() {
        var parser = WPXFrameParser()
        let measurements = parser.append(Data(firstCapturedFrame))

        XCTAssertEqual(measurements.count, 1)
        guard let measurement = measurements.first else { return }
        XCTAssertEqual(measurement.sequence, 197)
        XCTAssertEqual(measurement.vrectV, 18.023, accuracy: 0.0001)
        XCTAssertEqual(measurement.voutV, 17.952, accuracy: 0.0001)
        XCTAssertEqual(measurement.currentA, 1.384, accuracy: 0.0001)
        XCTAssertEqual(measurement.mode, 4)
        XCTAssertEqual(measurement.frequencyHz, 360)
        XCTAssertEqual(measurement.rpp, 28.071, accuracy: 0.0001)
        XCTAssertEqual(measurement.coreTempC, 51)
        XCTAssertEqual(measurement.eloadTempC, 65)
        XCTAssertEqual(measurement.extProbeTempC, 0)
        XCTAssertEqual(measurement.bridgeTempC, 88)
        XCTAssertEqual(measurement.coilTempC, 37)
        XCTAssertEqual(measurement.runTimeS, 243)
    }

    func testDecodesSplitSerialFrame() {
        var parser = WPXFrameParser()
        let splitIndex = 13
        XCTAssertTrue(parser.append(Data(firstCapturedFrame[..<splitIndex])).isEmpty)
        let measurements = parser.append(Data(firstCapturedFrame[splitIndex...]))
        XCTAssertEqual(measurements.count, 1)
    }

    func testLiveSerialReaderSmokeWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["WPX_LIVE_SMOKE"] == "1" else {
            throw XCTSkip("Set WPX_LIVE_SMOKE=1 to test a connected WPX device.")
        }
        guard let port = WPXPortScanner.availablePorts().first else {
            throw XCTSkip("No WPX usbmodem port is connected.")
        }

        let receivedExpectation = expectation(description: "receive WPX measurements")
        let lock = NSLock()
        var receivedCount = 0
        var didFulfill = false
        var firstMeasurement: WPXMeasurement?

        let reader = try WPXSerialReader(
            path: port,
            onMeasurement: { measurement in
                lock.lock()
                receivedCount += 1
                firstMeasurement = firstMeasurement ?? measurement
                if receivedCount >= 3, !didFulfill {
                    didFulfill = true
                    receivedExpectation.fulfill()
                }
                lock.unlock()
            },
            onError: { error in
                XCTFail("Live serial reader failed: \(error.localizedDescription)")
            }
        )

        reader.start()
        wait(for: [receivedExpectation], timeout: 5)
        reader.stop()

        lock.lock()
        let count = receivedCount
        let measurement = firstMeasurement
        lock.unlock()

        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertNotNil(measurement)
    }

    @MainActor
    func testLiveRecordingCreatesTemperatureCSVWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["WPX_LIVE_SMOKE"] == "1" else {
            throw XCTSkip("Set WPX_LIVE_SMOKE=1 to test a connected WPX device.")
        }
        guard let port = WPXPortScanner.availablePorts().first else {
            throw XCTSkip("No WPX usbmodem port is connected.")
        }

        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WPXRecorderTests-\(UUID().uuidString)", isDirectory: true)
        let model = RecorderViewModel()
        model.selectedPort = port
        model.durationMinutes = "0.02"
        model.outputDirectoryURL = outputDirectory
        model.startRecording()

        let deadline = Date().addingTimeInterval(5)
        while model.isRecording && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if model.isRecording {
            model.stopRecording()
        }

        XCTAssertFalse(model.isRecording)
        XCTAssertGreaterThan(model.rowCount, 0)
        guard let csvURL = model.lastCSVURL else {
            XCTFail("No CSV URL was produced")
            return
        }
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("core_temp_c"))
        XCTAssertGreaterThan(csv.split(separator: "\n").count, 1)
    }
}
