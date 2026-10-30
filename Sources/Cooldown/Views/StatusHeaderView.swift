import AppKit
import CooldownCore
import SwiftUI

/// CPU speed / memory / disk at a glance, plus what is eating the CPU.
struct StatusHeaderView: View {
    let snapshot: SystemSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                cpuTile
                memoryTile
                diskTile
            }
            if let swap = snapshot?.swap, swap.used > 0 {
                swapLine(swap)
            }
            if let processes = snapshot?.topProcesses, !processes.isEmpty {
                topProcesses(processes)
            }
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private var cpuTile: some View {
        if let limit = snapshot?.cpuSpeedLimit {
            StatTile(
                title: "CPU speed",
                value: "\(limit)%",
                caption: limit >= 90 ? "Full speed" : "Slowed by heat",
                tint: limit >= 90 ? .green : (limit >= 70 ? .orange : .red)
            )
        } else {
            let thermal = snapshot?.thermal ?? .nominal
            StatTile(
                title: "Thermal",
                value: snapshot == nil ? "–" : thermal.label,
                caption: thermal >= .serious ? "Slowed by heat" : "No throttling",
                tint: thermal >= .serious ? .red : (thermal == .fair ? .orange : .green)
            )
        }
    }

    private var memoryTile: some View {
        let pressure = snapshot?.memoryPressure
        let tint: Color = {
            switch pressure {
            case .critical: return .red
            case .warning: return .orange
            default: return .green
            }
        }()
        return StatTile(
            title: "Memory",
            value: snapshot?.memoryFreePercent.map { "\($0)% free" } ?? "–",
            caption: pressure.map { "Pressure \($0.label)" } ?? memoryCaption,
            tint: tint
        )
    }

    private var memoryCaption: String {
        guard let total = snapshot?.physicalMemory, total > 0 else { return " " }
        return "\(ByteFormat.string(total)) installed"
    }

    private var diskTile: some View {
        let free = snapshot?.diskFree
        let total = snapshot?.diskTotal
        let lowSpace = free.map { $0 < 20_000_000_000 } ?? false
        return StatTile(
            title: "Disk",
            value: free.map(ByteFormat.string) ?? "–",
            caption: total.map { "free of \(ByteFormat.string($0))" } ?? " ",
            tint: lowSpace ? .orange : .primary
        )
    }

    // MARK: Details

    private func swapLine(_ swap: SwapUsage) -> some View {
        let heavy = swap.used > 2_000_000_000
        return HStack(spacing: 4) {
            Image(systemName: "arrow.left.arrow.right")
            Text("Swap: \(ByteFormat.string(swap.used)) used")
            if heavy {
                Text("· a restart clears it")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(heavy ? Color.orange : Color.secondary)
    }

    private func topProcesses(_ processes: [ProcessSample]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("TOP CPU")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
            ForEach(processes.prefix(3)) { process in
                HStack(spacing: 6) {
                    Text(String(format: "%.0f%%", process.cpuPercent))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(process.cpuPercent >= 50 ? Color.orange : Color.secondary)
                    Text(process.name)
                        .lineLimit(1)
                    if let hint = process.hint {
                        Text(hint)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
