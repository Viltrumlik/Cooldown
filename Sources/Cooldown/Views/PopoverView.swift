import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            StatusHeaderView(snapshot: model.snapshot)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            Divider()
            TargetListView()
            Divider()
            FooterView()
        }
        .frame(width: 380)
        .onAppear { model.refreshIfStale() }
        // MenuBarExtra keeps its window around; re-scan when it is shown again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: model.menuBarSymbol)
                .foregroundStyle(model.isHot ? Color.orange : Color.accentColor)
            Text("Cooldown")
                .font(.headline)
            Spacer()
            if model.phase == .scanning {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Scan again")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
