import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Design tokens — Cochicho dark bento, one hot accent.
/// Shared by the app and the widget so health colours stay consistent.
enum Theme {

    // MARK: Surfaces

    /// Warm charcoal from the product reference. These are intentionally
    /// opaque colours so a widget snapshot stays readable.
    static let bg = Color(hex: 0x131211)
    static let pageBg = bg
    static let sidebarBg = Color(hex: 0x0F0E0D)
    static let card = Color(hex: 0x1D1C1B)
    static let cardBg = card
    /// Quiet in the normal theme. It is not used as a text colour.
    static let cardBorder = Color.white.opacity(0.10)
    static let hairline = cardBorder
    /// Used when the user asks macOS for more contrast.
    static let hairlineStrong = Color.white.opacity(0.24)
    static let progressTrack = Color.white.opacity(0.12)
    static let grid = Color.white.opacity(0.08)
    static let chipFill = Color.white.opacity(0.06)

    // MARK: Ink

    static let ink = Color(hex: 0xF2EFEA)
    /// The first pass used 42% white here, which measured about 4.03:1
    /// against a card. Keep secondary text above the normal-text target.
    static let inkDim = Color.white.opacity(0.52)
    static let inkSecondary = inkDim
    static let inkFaint = inkDim
    static let inkTertiary = inkFaint

    // Semantic aliases keep new surfaces named by role instead of by the
    // visual treatment that happened to be used for the first dashboard.
    static let textPrimary = ink
    static let textSecondary = inkSecondary
    static let textTertiary = inkTertiary

    // MARK: Brand

    static let accent = Color(hex: 0xFF4500)
    static let accentSoft = accent.opacity(0.20)
    static let accentStrong = accent
    static let action = accent
    static let focusRing = accent

    // MARK: Status

    static let ok = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let statusGood = ok
    static let statusWarn = Color(hex: 0xE0A020)
    static let statusCrit = accent

    // MARK: Chart slots (dark-card categorical)

    static let slotCPU = Color(red: 0.36, green: 0.62, blue: 0.98)
    static let slotGPU = Color(red: 0.66, green: 0.52, blue: 0.92)
    static let slotRAM = Color(red: 0.28, green: 0.78, blue: 0.68)
    /// Rose stays distinct from the amber warning ramp. Disk identity must not
    /// make a normal reading look like a warning.
    static let slotDisk = Color(hex: 0xE98AAE)

    // MARK: Shape

    static let cardRadius: CGFloat = 20
    static let nestedRadius: CGFloat = 12
    static let alertRadius: CGFloat = 14
    static let sidebarItemRadius: CGFloat = 10
    static let iconWell: CGFloat = 28
    static let pagePadding: CGFloat = 20
    static let sectionGap: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let gridGap: CGFloat = 12

    // MARK: Typography

    /// Use the system face for explanations and actions. Monospace is for
    /// values, timestamps and short instrument labels where aligned columns
    /// help the eye compare readings.
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func instrument(_ size: CGFloat = 11, _ weight: Font.Weight = .medium) -> Font {
        mono(size, weight)
    }

    #if canImport(AppKit)
    static var pageBgNS: NSColor { NSColor(hex: 0x131211) }
    static var sidebarBgNS: NSColor { NSColor(hex: 0x0F0E0D) }
    #endif
}

// MARK: - Card chrome

struct ThemeCardBackground: View {
    var radius: CGFloat = Theme.cardRadius
    var padded: Bool = false

    /// macOS exposes Increase Contrast through NSWorkspace rather than the
    /// SwiftUI accessibilityContrast environment key (which is unavailable
    /// on the deployment target). Button Shapes is a useful additional cue.
    @Environment(\.accessibilityShowBorders) private var showAccessibilityBorders
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shouldUseStrongBorder: Bool {
        #if canImport(AppKit)
        return showAccessibilityBorders || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        return showAccessibilityBorders
        #endif
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(reduceTransparency ? Theme.card : Theme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        shouldUseStrongBorder ? Theme.hairlineStrong : Theme.hairline,
                        lineWidth: shouldUseStrongBorder ? 1.25 : 1
                    )
            )
    }
}

extension View {
    /// Flat dark card — fill + hairline, no shadow.
    func themeCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = Theme.cardPadding) -> some View {
        self
            .padding(padding)
            .background(ThemeCardBackground(radius: radius))
    }

    /// Dim circle behind an SF Symbol (sidebar / section icons).
    func themeIconWell(size: CGFloat = Theme.iconWell, selected: Bool = false) -> some View {
        self
            .frame(width: size, height: size)
            .background(
                Circle().fill(selected ? Theme.accent.opacity(0.25) : Color.white.opacity(0.07))
            )
            .overlay(
                Circle().stroke(selected ? Theme.accent.opacity(0.72) : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Circle())
    }
}

// MARK: - Numbered card header ("01 MIC" in tracked mono caps)

struct ThemeCardHeader: View {
    let number: String
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Theme.inkDim

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(Theme.instrument(11))
                .foregroundStyle(Theme.inkFaint)
            Text(title)
                .font(Theme.instrument(11, .medium))
                .tracking(2)
                .foregroundStyle(Theme.inkDim)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.instrument(11, .medium))
                    .tracking(1)
                    .foregroundStyle(trailingColor)
            }
        }
        .textCase(.uppercase)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small stat block: label on top, big mono value below.
struct ThemeStat: View {
    let label: String
    let value: String
    var color: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.instrument(10))
                .tracking(1.5)
                .foregroundStyle(Theme.inkFaint)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.mono(20, .medium))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pill button in the house style.
struct ThemePillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.instrument(11, .medium))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(prominent ? Color.black : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(prominent ? Theme.accent : Color.white.opacity(0.07))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

#if canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
