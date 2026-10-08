import SwiftUI

struct ContentView: View {
    @StateObject private var model = RecorderViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            deviceSection
            recordingSection
            liveValuesSection
            footer
        }
        .padding(22)
        .frame(width: 700, height: 620)
        .onAppear {
            model.refreshPorts()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("WPX 데이터 기록기")
                    .font(.title2.weight(.semibold))
                Text("온도·전압·전류 데이터를 CSV로 저장합니다")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(model.isRecording ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                Text(model.isRecording ? "기록 중" : "대기")
                    .font(.callout.weight(.medium))
            }
        }
    }

    private var deviceSection: some View {
        GroupBox("장치") {
            HStack(spacing: 10) {
                Picker("시리얼 포트", selection: $model.selectedPort) {
                    Text("장치 선택").tag(String?.none)
                    ForEach(model.ports, id: \.self) { port in
                        Text(port).tag(Optional(port))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(model.isRecording)

                Button("새로고침") {
                    model.refreshPorts()
                }
                .disabled(model.isRecording)
            }
        }
    }

    private var recordingSection: some View {
        GroupBox("기록 설정") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("기록 시간")
                    TextField("분", text: $model.durationMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(model.isRecording)
                    Text("분")
                    Spacer()
                    if model.isRecording {
                        Text("남은 시간 \(model.remainingText)")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(model.outputDirectoryURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("저장 폴더 선택") {
                        model.chooseOutputDirectory()
                    }
                    .disabled(model.isRecording)
                }

                if model.isRecording {
                    ProgressView(value: model.progress)
                    Text("경과 시간 \(format(model.elapsedSeconds)) · \(model.rowCount)개 행")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(model.isRecording ? "기록 중지" : "기록 시작") {
                        if model.isRecording {
                            model.stopRecording()
                        } else {
                            model.startRecording()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                    if !model.isRecording, model.lastCSVURL != nil {
                        Button("CSV 위치 열기") {
                            model.openLastCSV()
                        }
                    }
                    Spacer()
                }
            }
            .padding(.top, 2)
        }
    }

    private var liveValuesSection: some View {
        GroupBox("현재 측정값") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricView(title: "Vout", value: model.latestMeasurement.map { String(format: "%.3f V", $0.voutV) } ?? "—")
                MetricView(title: "Iout", value: model.latestMeasurement.map { String(format: "%.3f A", $0.currentA) } ?? "—")
                MetricView(title: "Power", value: model.latestMeasurement.map { String(format: "%.3f W", $0.powerW) } ?? "—")
                MetricView(title: "Core", value: model.latestMeasurement.map { "\($0.coreTempC) °C" } ?? "—")
                MetricView(title: "E-load", value: model.latestMeasurement.map { "\($0.eloadTempC) °C" } ?? "—")
                MetricView(title: "Bridge", value: model.latestMeasurement.map { "\($0.bridgeTempC) °C" } ?? "—")
                MetricView(title: "Coil", value: model.latestMeasurement.map { "\($0.coilTempC) °C" } ?? "—")
                MetricView(title: "Probe", value: model.latestMeasurement.map { "\($0.extProbeTempC) °C" } ?? "—")
                MetricView(title: "Frequency", value: model.latestMeasurement.map { "\($0.frequencyHz) Hz" } ?? "—")
            }
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }
}
