import Foundation
import Darwin

enum WPXSerialError: LocalizedError {
    case openFailed(path: String, message: String)
    case configureFailed(message: String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path, message):
            return "포트를 열 수 없습니다.\n\(path)\n\(message)"
        case let .configureFailed(message):
            return "시리얼 포트 설정에 실패했습니다.\n\(message)"
        }
    }
}

enum WPXPortScanner {
    static func availablePorts() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let ports = entries
            .filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("tty.usbmodem") }
            .map { "/dev/\($0)" }

        return ports.sorted { lhs, rhs in
            let lhsPreferred = lhs.contains("/cu.usbmodem")
            let rhsPreferred = rhs.contains("/cu.usbmodem")
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs < rhs
        }
    }
}

final class WPXSerialReader {
    private let path: String
    private let onMeasurement: (WPXMeasurement) -> Void
    private let onError: (Error) -> Void
    private let queue: DispatchQueue
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var parser = WPXFrameParser()

    init(
        path: String,
        onMeasurement: @escaping (WPXMeasurement) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        self.path = path
        self.onMeasurement = onMeasurement
        self.onError = onError
        self.queue = DispatchQueue(label: "com.wpx.recorder.serial.\(UUID().uuidString)", qos: .userInitiated)

        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw WPXSerialError.openFailed(path: path, message: String(cString: strerror(errno)))
        }
        do {
            try Self.configure(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        fileDescriptor = descriptor
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: self.fileDescriptor, queue: self.queue)
            source.setEventHandler { [weak self] in
                self?.readAvailable()
            }
            source.resume()
            self.source = source
        }
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            if fileDescriptor >= 0 {
                Darwin.close(fileDescriptor)
                fileDescriptor = -1
            }
        }
    }

    deinit {
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
    }

    private func readAvailable() {
        guard fileDescriptor >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = bytes.withUnsafeMutableBytes { rawBuffer -> Int in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }

            if count > 0 {
                let data = Data(bytes[0..<count])
                for measurement in parser.append(data) {
                    onMeasurement(measurement)
                }
                continue
            }

            if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            let error = WPXSerialError.openFailed(path: path, message: String(cString: strerror(errno)))
            onError(error)
            return
        }
    }

    private static func configure(_ descriptor: Int32) throws {
        var settings = termios()
        guard tcgetattr(descriptor, &settings) == 0 else {
            throw WPXSerialError.configureFailed(message: String(cString: strerror(errno)))
        }

        cfmakeraw(&settings)
        cfsetispeed(&settings, speed_t(B115200))
        cfsetospeed(&settings, speed_t(B115200))
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSIZE)
        settings.c_cflag |= tcflag_t(CS8)

        guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            throw WPXSerialError.configureFailed(message: String(cString: strerror(errno)))
        }
    }
}
