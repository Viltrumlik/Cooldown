import CooldownCore
import SwiftUI

struct TargetListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.isFirstScan {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for things to clean…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.group.rawValue.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.rows) { row in
                                TargetRowView(row: row)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 320)
    }
}

struct TargetRowView: View {
    @EnvironmentObject private var model: AppModel
    let row: TargetRow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { row.isEnabled },
                set: { model.setEnabled($0, for: row.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.info.title)
                    if row.info.risk == .caution {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Has a cost after cleaning, see the description")
                    }
                }
                Text(row.info.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            ScanValueView(scan: row.scan)
        }
        .opacity(row.scan == nil || row.hasWork ? 1 : 0.5)
    }
}

struct ScanValueView: View {
    let scan: ScanResult?

    var body: some View {
        Group {
            switch scan {
            case .none:
                ProgressView().controlSize(.small)
            case let .files(bytes, _):
                Text(ByteFormat.string(bytes))
                    .monospacedDigit()
            case let .processes(count):
                Text("\(count) running")
                    .foregroundStyle(.orange)
            case .empty:
                // A word here ("Clean") read like the Clean button; a quiet tick doesn't.
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Nothing to clean")
            case let .unavailable(reason):
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(reason)
            case .notApplicable:
                EmptyView()
            }
        }
        .font(.callout)
    }
}
