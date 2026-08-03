import SwiftUI

struct MenuBarView: View {
    @ObservedObject var poller: StatusPoller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = poller.latest {
                row(icon: "circle.fill", label: "Health", value: "\(status.healthScore) · \(status.healthScoreMsg)", tint: healthColor(status.healthScore))
                row(icon: "cpu", label: "CPU", value: String(format: "%.1f%%", status.cpu.usage))
                row(icon: "memorychip", label: "Memory", value: String(format: "%.1f%%", status.memory.usedPercent))
                if let disk = status.primaryDisk {
                    row(icon: "internaldrive", label: "Disk", value: String(format: "%.0f%% used", disk.usedPercent))
                }
                row(icon: "bolt.fill", label: "Power draw", value: String(format: "%.1f W", status.thermal.systemPower))
                if let battery = status.battery {
                    row(icon: "battery.100", label: "Battery", value: "\(battery.percent)% · \(battery.status)")
                }
                if let proc = status.topProcess {
                    row(icon: "list.bullet", label: "Top process", value: "\(proc.name) · \(String(format: "%.0f%%", proc.cpu))")
                }
                Divider().padding(.vertical, 4)
            } else {
                ProgressView()
                    .padding(8)
            }
            Button("Quit Vitality") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 240)
        .padding(.vertical, 6)
    }

    private func row(icon: String, label: String, value: String, tint: Color = .secondary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func healthColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .yellow }
        return .red
    }
}
