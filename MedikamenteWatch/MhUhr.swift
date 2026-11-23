import SwiftUI

// ============================================================================
// Minze & Honig 2.0 – Farben und Schrift der Uhr
// Quelle: DesignGuide/tokens/design-tokens.json (semantic.dark). Die Uhr ist
// immer dunkel; nur Rollen, keine Skalenwerte. Ohne UIKit-Teile (watchOS).
// Figtree steht in UIAppFonts der Info.plist (Fonts/Figtree-*.ttf).
// ============================================================================

private func farbe(_ wert: UInt32) -> Color {
  Color(
    red: Double((wert >> 16) & 0xFF) / 255,
    green: Double((wert >> 8) & 0xFF) / 255,
    blue: Double(wert & 0xFF) / 255)
}

/// Dunkle Rollen des Guides (Namen wie in design-tokens.json).
enum MhUhr {
  static let surface = farbe(0x262A28)
  static let text = farbe(0xE6EAE7)
  static let textStrong = farbe(0xFFFFFF)
  static let textSecondary = farbe(0xA9B0AB)
  static let link = farbe(0xA8D5BA)
  static let primary = farbe(0x82BD9B)
}

extension Font {
  /// Figtree 400/500/600 mit Dynamic Type (keine Kursive, kein Bold).
  static func figtree(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-Regular", size: groesse, relativeTo: stil)
  }

  static func figtreeMedium(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-Medium", size: groesse, relativeTo: stil)
  }

  static func figtreeSemiBold(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-SemiBold", size: groesse, relativeTo: stil)
  }
}
