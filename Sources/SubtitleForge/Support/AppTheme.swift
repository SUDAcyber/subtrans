import AppKit
import SwiftUI

enum AppColorSchemeMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return AppIconSymbol.appearance
        case .light:
            return AppIconSymbol.appearanceLight
        case .dark:
            return AppIconSymbol.appearanceDark
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppTheme {
    static let graphite = adaptive(
        light: NSColor(calibratedRed: 0.946, green: 0.934, blue: 0.902, alpha: 1),
        dark: NSColor(calibratedRed: 0.075, green: 0.073, blue: 0.067, alpha: 1)
    )
    static let graphiteRaised = adaptive(
        light: NSColor(calibratedRed: 0.986, green: 0.975, blue: 0.944, alpha: 1),
        dark: NSColor(calibratedRed: 0.115, green: 0.110, blue: 0.100, alpha: 1)
    )
    static let graphitePanel = adaptive(
        light: NSColor(calibratedRed: 0.884, green: 0.864, blue: 0.808, alpha: 1),
        dark: NSColor(calibratedRed: 0.150, green: 0.145, blue: 0.130, alpha: 1)
    )
    static let ivory = adaptive(
        light: NSColor(calibratedRed: 0.130, green: 0.118, blue: 0.095, alpha: 1),
        dark: NSColor(calibratedRed: 0.890, green: 0.860, blue: 0.770, alpha: 1)
    )
    static let mutedIvory = adaptive(
        light: NSColor(calibratedRed: 0.420, green: 0.390, blue: 0.325, alpha: 1),
        dark: NSColor(calibratedRed: 0.680, green: 0.650, blue: 0.580, alpha: 1)
    )
    static let brass = adaptive(
        light: NSColor(calibratedRed: 0.585, green: 0.385, blue: 0.145, alpha: 1),
        dark: NSColor(calibratedRed: 0.780, green: 0.580, blue: 0.320, alpha: 1)
    )
    static let blueSlate = adaptive(
        light: NSColor(calibratedRed: 0.265, green: 0.390, blue: 0.510, alpha: 1),
        dark: NSColor(calibratedRed: 0.380, green: 0.480, blue: 0.570, alpha: 1)
    )
    static let success = adaptive(
        light: NSColor(calibratedRed: 0.245, green: 0.485, blue: 0.300, alpha: 1),
        dark: NSColor(calibratedRed: 0.460, green: 0.670, blue: 0.480, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(calibratedRed: 0.680, green: 0.405, blue: 0.095, alpha: 1),
        dark: NSColor(calibratedRed: 0.820, green: 0.610, blue: 0.360, alpha: 1)
    )
    static let danger = adaptive(
        light: NSColor(calibratedRed: 0.690, green: 0.230, blue: 0.190, alpha: 1),
        dark: NSColor(calibratedRed: 0.820, green: 0.360, blue: 0.320, alpha: 1)
    )
    static let divider = adaptive(
        light: NSColor(calibratedRed: 0.755, green: 0.725, blue: 0.650, alpha: 1),
        dark: NSColor(calibratedRed: 0.220, green: 0.210, blue: 0.190, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
