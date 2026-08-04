import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

enum Support {

    /// Lightning (LNURL-pay) address donations go to.
    ///
    /// Public on purpose — it is in a public repo and printed on screen. A
    /// LNURL is bech32, so it carries its own checksum: a copy-paste that
    /// loses a character fails in the wallet rather than sending anywhere.
    static let lnurl = "lnurl1dp68gurn8ghj7ampd3kx2ar0veekzar0wd5xjtnrdakj7tnhv4kxctttdehhwm30d3h82unvwqhkyctndpn82mrrdaexkwp58q7qfu9t"

    /// What most desktop wallets register for, so the QR has a use on a
    /// machine that is not holding a phone.
    static var walletURL: URL? { URL(string: "lightning:\(lnurl)") }

    /// Head and tail only. The full 110 characters would wrap to four lines of
    /// bech32 that nobody reads; the ends are what you actually check against
    /// your wallet after pasting.
    static var abbreviated: String {
        "\(lnurl.prefix(12))…\(lnurl.suffix(8))"
    }

    static func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lnurl, forType: .string)
    }

    /// Side of the rendered QR bitmap, in points. The real size is rounded down
    /// to a whole number of pixels per module — see `qrImage()`.
    static let qrTargetSide: CGFloat = 156

    /// The generator emits one pixel per module (39 across for this address).
    /// Handing that to SwiftUI and letting it stretch produces a soft grey mess
    /// that scanners refuse, so the upscale is done here, once, by drawing with
    /// interpolation switched off.
    ///
    /// The factor is a whole number on purpose: at 3.79 pixels per module some
    /// modules land 4 pixels wide and their neighbours 3, and that uneven grid
    /// is exactly what makes a QR fail to decode at an angle.
    ///
    /// Uppercased first — bech32 is case-insensitive, and an all-uppercase
    /// payload lets the encoder pick QR alphanumeric mode over byte mode. Same
    /// address, 39 modules instead of far more, easier to scan.
    static func qrImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(lnurl.uppercased().utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }

        let native = NSCIImageRep(ciImage: output)
        let source = NSImage(size: native.size)
        source.addRepresentation(native)

        // Two device pixels per point on Retina, so aim for double and round
        // down to a whole multiple of the module grid.
        let factor = max(1, (qrTargetSide * 2 / output.extent.width).rounded(.down))
        let side = output.extent.width * factor

        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        image.unlockFocus()
        return image
    }
}

struct SupportPane: View {
    let back: () -> Void

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Buy me a coffee", back: back)

            Text("Vitality is free, and stays free. If it earned its place in your menu bar, a coffee over Lightning is very welcome.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            qrCard

            Text(Support.abbreviated)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            copyButton
                .padding(.horizontal, 14)
                .padding(.top, 10)

            if Support.walletURL != nil {
                MenuActionRow(icon: "bolt.fill", label: "Open in wallet") {
                    if let url = Support.walletURL { NSWorkspace.shared.open(url) }
                }
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 6)
        .onDisappear { resetTask?.cancel() }
    }

    /// Always dark-on-white, in both themes.
    ///
    /// The generator draws black modules on a transparent background. Left to
    /// inherit the popover's material that becomes black-on-dark-grey in dark
    /// mode — which looks fine and scans in nothing.
    private var qrCard: some View {
        Group {
            if let qr = Support.qrImage() {
                Image(nsImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: Support.qrTargetSide, height: Support.qrTargetSide)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 60))
                    .foregroundStyle(.black.opacity(0.25))
                    .frame(width: Support.qrTargetSide, height: Support.qrTargetSide)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
        // In light mode a white card on a light popover has no edge of its own.
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)))
        .frame(maxWidth: .infinity)
    }

    private var copyButton: some View {
        Button(action: copy) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 11))
                Text(copied ? "Copied" : "Copy Lightning address")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(copied ? Color.green.opacity(0.18) : Color.primary.opacity(0.09))
            )
            .foregroundStyle(copied ? Color.green : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copy() {
        Support.copyToPasteboard()
        copied = true

        // Restart the countdown on every press, so a second click doesn't get
        // its confirmation cut short by the first one's timer.
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
