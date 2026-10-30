import AppKit
import CooldownCore
import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.awaitingConfirmation {
                Label(
                    "Your selection includes items marked ⚠︎. They cost a re-download or can't be undone. Click again to confirm.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.cleanTapped()
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.awaitingConfirmation ? Color.orange : Color.accentColor)
            .controlSize(.large)
            // Deliberately no Return shortcut: deleting files takes a click.
            .disabled(model.isBusy || model.selectedRows.isEmpty)

            if let report = model.lastReport {
                reportLine(report)
            }

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .help(model.launchAtLoginError ?? "Start Cooldown when you log in")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)

            if let error = model.launchAtLoginError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var buttonTitle: String {
        switch model.phase {
        case let .cleaning(done, total):
            return "Cleaning… \(done)/\(total)"
        case .scanning where model.isFirstScan:
            return "Scanning…"
        default:
            break
        }
        if model.awaitingConfirmation { return "Confirm & Clean" }

        let bytes = model.selectedBytes
        let processes = model.selectedProcessCount
        switch (bytes > 0, processes > 0) {
        case (true, true):
            return "Clean \(ByteFormat.string(bytes)) · stop \(processes) process\(processes == 1 ? "" : "es")"
        case (true, false):
            return "Clean \(ByteFormat.string(bytes))"
        case (false, true):
            return "Stop \(processes) process\(processes == 1 ? "" : "es")"
        case (false, false):
            return model.selectedRows.isEmpty ? "Nothing to clean" : "Clean"
        }
    }

    private func reportLine(_ report: CleanReport) -> some View {
        var parts = ["Freed \(ByteFormat.string(report.freedBytes))"]
        if report.stoppedProcesses > 0 {
            parts.append("stopped \(report.stoppedProcesses)")
        }
        if !report.errors.isEmpty {
            parts.append("\(report.errors.count) warning\(report.errors.count == 1 ? "" : "s")")
        }
        return HStack(spacing: 4) {
            Image(systemName: report.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(report.errors.isEmpty ? Color.green : Color.orange)
            Text(parts.joined(separator: " · "))
            Text("at ") + Text(report.finishedAt, style: .time)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(report.errors.joined(separator: "\n"))
    }
}
