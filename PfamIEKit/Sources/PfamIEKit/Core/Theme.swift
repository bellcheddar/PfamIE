import SwiftUI

/// "Deep Field": the app should feel like an astronomy instrument pointed at
/// sequence space.
///
/// The palette is resolved in Swift rather than an asset catalog because
/// PfamIEKit imports neither UIKit nor AppKit, and `Color` has no
/// platform-independent dynamic initialiser. The root view puts a `Theme` in
/// the environment for the current appearance and every view reads it from
/// there, so light and dark stay a single source of truth across five targets.
public struct Theme: Sendable, Equatable {

    public let bgDeep: Color
    public let bgRaised: Color
    public let inkPrimary: Color
    public let inkSecondary: Color
    public let accentNova: Color
    public let accentPulsar: Color
    public let accentFlare: Color
    public let confidenceHigh: Color
    public let confidenceMid: Color
    public let confidenceLow: Color
    public let hairline: Color
    public let isDark: Bool

    public static let dark = Theme(
        bgDeep: Color(hex: 0x070B14),
        bgRaised: Color(hex: 0x0E1524),
        inkPrimary: Color(hex: 0xE8EDF7),
        inkSecondary: Color(hex: 0x8A96AD),
        accentNova: Color(hex: 0x5EEAD4),
        accentPulsar: Color(hex: 0xA78BFA),
        accentFlare: Color(hex: 0xFBBF24),
        confidenceHigh: Color(hex: 0x5EEAD4),
        confidenceMid: Color(hex: 0xFBBF24),
        confidenceLow: Color(hex: 0xFB7185),
        hairline: Color(hex: 0xE8EDF7).opacity(0.10),
        isDark: true
    )

    public static let light = Theme(
        bgDeep: Color(hex: 0xF5F7FB),
        bgRaised: Color(hex: 0xFFFFFF),
        inkPrimary: Color(hex: 0x101828),
        inkSecondary: Color(hex: 0x5B6779),
        accentNova: Color(hex: 0x0D9488),
        accentPulsar: Color(hex: 0x7C3AED),
        accentFlare: Color(hex: 0xD97706),
        confidenceHigh: Color(hex: 0x0D9488),
        confidenceMid: Color(hex: 0xD97706),
        confidenceLow: Color(hex: 0xBE123C),
        hairline: Color(hex: 0x101828).opacity(0.12),
        isDark: false
    )

    public static func resolve(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
    }

    public func colour(for band: Calibration.Band) -> Color {
        switch band {
        case .high: return confidenceHigh
        case .mid: return confidenceMid
        case .low: return confidenceLow
        case .none: return inkSecondary
        }
    }

    /// A clan's colour, from the stable hue the forge assigned it.
    ///
    /// The hue wheel is deliberately narrowed to the teal-to-violet arc the
    /// rest of the app lives in: a full rainbow over 891 clans reads as
    /// confetti and fights the amber query comet for attention.
    public func clanColour(hue: Double) -> Color {
        guard hue >= 0 else {
            // Unclanned families: neutral, so clans are what the eye picks out.
            return inkSecondary.opacity(0.55)
        }
        let arc = 0.42 + hue * 0.36        // roughly 150 to 280 degrees
        return Color(hue: arc, saturation: isDark ? 0.62 : 0.70,
                     brightness: isDark ? 0.92 : 0.72)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.dark
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// What the user chose in Settings, as opposed to what the system is doing.
public enum AppearanceChoice: String, CaseIterable, Sendable, Identifiable {
    case system, dark, light

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    /// nil means "follow the system", which is what `.preferredColorScheme`
    /// expects: passing a concrete scheme there would override the setting the
    /// user just asked us to respect.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
