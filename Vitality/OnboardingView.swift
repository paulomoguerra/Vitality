import AppKit
import SwiftUI

/// First-run setup, shown only when Mole is missing.
///
/// Vitality is a front end for the `mo` CLI and is inert without it, so a menu
/// bar item quietly reporting "can't read system status" is a dead end for
/// anyone who doesn't already know what Mole is. This turns that into an action.
struct OnboardingView: View {
    /// Called once Mole has been detected, so the host can close the window.
    var onReady: () -> Void

    @State private var isInstalled = MoleCLI.isInstalled
    @State private var hasHomebrew = MoleCLI.isHomebrewInstalled
    @State private var didLaunchInstaller = false
    @State private var errorMessage: String?
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if isInstalled {
                ready
            } else if hasHomebrew {
                installStep
            } else {
                homebrewStep
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(26)
        .frame(width: 460, height: 380)
        .onAppear(perform: startPolling)
        .onDisappear { pollTimer?.invalidate(); pollTimer = nil }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                HealthRing(score: isInstalled ? 100 : nil, lineWidth: 6)
                Image(systemName: isInstalled ? "checkmark" : "waveform.path.ecg")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isInstalled ? .green : .secondary)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Vitality").font(.system(size: 19, weight: .semibold))
                Text("One thing to set up first.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vitality reads your Mac's vital signs using **Mole**, a free open-source command-line tool. It isn't installed yet.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                switch MoleCLI.installMole() {
                case .success:
                    didLaunchInstaller = true
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.message
                }
            } label: {
                Label("Install Mole", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if didLaunchInstaller {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the install to finish in Terminal…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("This opens Terminal and runs `brew install mole`. Vitality shows you the real output rather than hiding it — the install can ask for your password.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var homebrewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vitality needs **Mole**, which is installed with **Homebrew** — and Homebrew isn't on this Mac yet.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            } label: {
                Label("Get Homebrew", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Text("Vitality doesn't install Homebrew for you — that's a system-wide change that should come from Homebrew's own instructions, not from an app you just opened.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mole is installed. Vitality is ready.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
            Text("Vitality lives in your menu bar — click the gauge icon up top. To add a widget, right-click the desktop, choose Edit Widgets, and search for Vitality.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start using Vitality") { onReady() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
    }

    private var footer: some View {
        HStack {
            Button("Check again") { recheck() }
                .controlSize(.small)
            Spacer()
            Text("Mole is a separate GPL-3.0 project by tw93.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    /// Polls rather than asking the user to click. The install finishes in a
    /// Terminal window Vitality has no callback from, so the app watches for
    /// the binary to appear and updates itself.
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in recheck() }
        }
    }

    private func recheck() {
        hasHomebrew = MoleCLI.isHomebrewInstalled
        let nowInstalled = MoleCLI.isInstalled
        if nowInstalled != isInstalled {
            isInstalled = nowInstalled
            if nowInstalled { errorMessage = nil }
        }
    }
}
