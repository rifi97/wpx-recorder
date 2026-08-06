import AppKit
import Combine
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var ports: [String] = []
    @Published var selectedPort: String?
    @Published var durationMinutes = "1"
    @Published var outputDirectoryURL: URL
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var rowCount = 0
    @Published private(set) var latestMeasurement: WPXMeasurement?
    @Published private(set) var statusMessage = "장치를 연결한 뒤 기록 시간을 설정하세요."
    @Published private(set) var lastCSVURL: URL?
    @Published private(set) var errorMessage: String?

    private var reader: WPXSerialReader?
    private var csvHandle: FileHandle?
    private var startDate: Date?
    private var durationSeconds: TimeInterval = 0
    private var completionWorkItem: DispatchWorkItem?
    private var progressTimer: Timer?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        outputDirectoryURL = documents.appendingPathComponent("WPX Records", isDirectory: true)
        refreshPorts()
    }

    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(elapsedSeconds / durationSeconds, 0), 1)
    }

    var remainingText: String {
        let remaining = max(durationSeconds - elapsedSeconds, 0)
        return Self.formatDuration(remaining)
    }

    func refreshPorts() {
        ports = WPXPortScanner.availablePorts()
        if let selectedPort, ports.contains(selectedPort) {
            return
        }
        selectedPort = ports.first
        if ports.isEmpty {
            statusMessage = "WPX 시리얼 포트를 찾지 못했습니다."
        } else {
            statusMessage = "장치를 선택하고 기록 시작을 누르세요."
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "CSV 저장 폴더 선택"
        panel.message = "WPX 기록 CSV를 저장할 폴더를 선택하세요."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectoryURL

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectoryURL = url
            statusMessage = "저장 폴더: \(url.path)"
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil

        guard let selectedPort, !selectedPort.isEmpty else {
            errorMessage = "먼저 WPX 장치를 선택하세요."
            return
        }

        guard let minutes = Double(durationMinutes.replacingOccurrences(of: ",", with: ".")), minutes > 0 else {
            errorMessage = "기록 시간은 0보다 큰 분 단위 숫자로 입력하세요."
            return
        }

        let directory = outputDirectoryURL
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = "WPX_\(Self.filenameFormatter.string(from: Date())).csv"
            let url = directory.appendingPathComponent(filename)
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            let handle = try FileHandle(forWritingTo: url)
            handle.write(Data((WPXMeasurement.csvHeader + "\n").utf8))

            let newReader = try WPXSerialReader(
                path: selectedPort,
                onMeasurement: { [weak self] measurement in
                    Task { @MainActor [weak self] in
                        self?.receive(measurement)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleReaderError(error)
                    }
                }
            )

            csvHandle = handle
            lastCSVURL = url
            reader = newReader
            durationSeconds = minutes * 60
            startDate = Date()
            elapsedSeconds = 0
            rowCount = 0
            latestMeasurement = nil
            isRecording = true
            statusMessage = "기록 중: \(url.lastPathComponent)"
            newReader.start()

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.elapsedSeconds = Date().timeIntervalSince(self.startDate ?? Date())
                    if self.elapsedSeconds >= self.durationSeconds {
                        self.finishRecording()
                    }
                }
            }

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishRecording()
                }
            }
            completionWorkItem = workItem
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + durationSeconds, execute: workItem)
        } catch {
            csvHandle?.closeFile()
            csvHandle = nil
            errorMessage = error.localizedDescription
            statusMessage = "기록을 시작하지 못했습니다."
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    func openLastCSV() {
        guard let lastCSVURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCSVURL])
    }

    private func receive(_ measurement: WPXMeasurement) {
        guard isRecording else { return }
        let elapsed = measurement.receivedAt.timeIntervalSince(startDate ?? measurement.receivedAt)
        csvHandle?.write(Data((measurement.csvLine(elapsed: elapsed) + "\n").utf8))
        latestMeasurement = measurement
        rowCount += 1
        elapsedSeconds = elapsed
    }

    private func finishRecording() {
        guard isRecording else { return }
        completionWorkItem?.cancel()
        completionWorkItem = nil
        progressTimer?.invalidate()
        progressTimer = nil
        reader?.stop()
        reader = nil
        csvHandle?.synchronizeFile()
        csvHandle?.closeFile()
        csvHandle = nil
        isRecording = false
        elapsedSeconds = min(elapsedSeconds, durationSeconds)
        statusMessage = "기록 완료: \(rowCount)개 행 저장"
    }

    private func handleReaderError(_ error: Error) {
        guard isRecording else { return }
        errorMessage = error.localizedDescription
        finishRecording()
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
