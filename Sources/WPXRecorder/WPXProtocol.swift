import Foundation

struct WPXMeasurement: Sendable {
    let receivedAt: Date
    let sequence: Int
    let vrectV: Double
    let voutV: Double
    let currentA: Double
    let mode: Int
    let frequencyHz: Int
    let cep: Int
    let rpp: Double
    let coreTempC: Int
    let eloadTempC: Int
    let extProbeTempC: Int
    let bridgeTempC: Int
    let coilTempC: Int
    let runTimeS: Int
    let wh: Double
    let mah: Int
    let powerOffCount: Int

    var powerW: Double {
        voutV * currentA
    }

    static let csvHeader = "timestamp,elapsed_s,frame_sequence,vrect_v,vout_v,current_a,power_w,mode,frequency_hz,cep,rpp,core_temp_c,eload_temp_c,ext_probe_temp_c,bridge_temp_c,coil_temp_c,run_time_s,wh,mah,power_off_count"

    func csvLine(elapsed: TimeInterval) -> String {
        let timestamp = Self.timestampFormatter.string(from: receivedAt)
        return String(
            format: "%@,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.3f,%d,%d,%d,%d,%d,%d,%.3f,%d,%d",
            locale: Self.csvLocale,
            timestamp,
            elapsed,
            sequence,
            vrectV,
            voutV,
            currentA,
            powerW,
            mode,
            frequencyHz,
            cep,
            rpp,
            coreTempC,
            eloadTempC,
            extProbeTempC,
            bridgeTempC,
            coilTempC,
            runTimeS,
            wh,
            mah,
            powerOffCount
        )
    }

    private static let csvLocale = Locale(identifier: "en_US_POSIX")

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct WPXFrameParser {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [WPXMeasurement] {
        buffer.append(data)
        var measurements: [WPXMeasurement] = []

        while true {
            guard let start = buffer.firstIndex(of: 0xEE) else {
                buffer.removeAll(keepingCapacity: true)
                break
            }

            let bytesBeforeStart = buffer.distance(from: buffer.startIndex, to: start)
            if bytesBeforeStart > 0 {
                buffer.removeFirst(bytesBeforeStart)
            }

            guard buffer.count >= 2 else { break }
            let frameLength = Int(buffer[buffer.startIndex + 1]) + 5
            guard frameLength >= 7 else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= frameLength else { break }

            let frame = Array(buffer.prefix(frameLength))
            buffer.removeFirst(frameLength)
            if let measurement = parse(frame) {
                measurements.append(measurement)
            }
        }

        return measurements
    }

    private func parse(_ frame: [UInt8]) -> WPXMeasurement? {
        guard frame.count >= 7, frame[0] == 0xEE else { return nil }

        // The official WPX parser computes data[2] << 8 | data[1].
        let dataLength = Int(frame[2]) << 8 | Int(frame[1])
        let commandID = Int(frame[6]) << 8 | Int(frame[5])
        guard commandID == 0x0001, dataLength >= 2 else { return nil }

        let payloadLength = dataLength - 2
        let payloadStart = 7
        guard payloadLength == 33, frame.count >= payloadStart + payloadLength else {
            return nil
        }
        let payload = Array(frame[payloadStart..<(payloadStart + payloadLength)])

        func u16(_ offset: Int) -> Int {
            Int(payload[offset]) | (Int(payload[offset + 1]) << 8)
        }

        func u32(_ offset: Int) -> Int {
            Int(payload[offset]) |
                (Int(payload[offset + 1]) << 8) |
                (Int(payload[offset + 2]) << 16) |
                (Int(payload[offset + 3]) << 24)
        }

        func i8(_ offset: Int) -> Int {
            let value = Int(payload[offset])
            return value < 128 ? value : value - 256
        }

        return WPXMeasurement(
            receivedAt: Date(),
            sequence: Int(frame[3]),
            vrectV: Double(u16(0)) / 1000.0,
            voutV: Double(u16(2)) / 1000.0,
            currentA: Double(u16(4)) / 1000.0,
            mode: u16(6),
            frequencyHz: u16(8),
            cep: i8(10),
            rpp: Double(u16(11)) / 1000.0,
            coreTempC: u16(13),
            eloadTempC: u16(15),
            extProbeTempC: u16(17),
            bridgeTempC: u16(19),
            coilTempC: u16(21),
            runTimeS: u32(23),
            wh: Double(u16(27)) / 1000.0,
            mah: u16(29),
            powerOffCount: u16(31)
        )
    }
}
