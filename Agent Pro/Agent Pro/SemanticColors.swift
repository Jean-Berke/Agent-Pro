// SemanticColors.swift
import SwiftUI

enum AppColors {
    // Fond global
    static var background: Color {
        // Prend l’asset "Background" si présent, sinon couleur système dynamique
        Color("Background", bundle: .main, default: Color(uiColor: .systemGroupedBackground))
    }
    // Fond des cartes
    static var card: Color {
        Color("CardBackground", bundle: .main, default: Color(uiColor: .secondarySystemGroupedBackground))
    }
    // Textes
    static var textPrimary: Color {
        // Utilise l’asset si dispo, sinon Color.primary (s’adapte clair/sombre)
        Color("TextPrimary", bundle: .main, default: Color.primary)
    }
    static var textSecondary: Color {
        Color("TextSecondary", bundle: .main, default: Color.secondary)
    }
    // Teintes (si tu veux qu’elles soient 100% dynamiques aussi, on peut passer sur .tintColor)
    static var tintPrimary: Color {
        Color("TintPrimary", bundle: .main, default: Color.accentColor)
    }
    static var tintSecondary: Color {
        Color("TintSecondary", bundle: .main, default: Color.accentColor.opacity(0.85))
    }
    static var accent: Color {
        Color("Accent", bundle: .main, default: Color.orange)
    }
    // États
    static var success: Color {
        Color("Success", bundle: .main, default: Color.green)
    }
    static var warning: Color {
        Color("Warning", bundle: .main, default: Color.orange)
    }
    static var error: Color {
        Color("Error", bundle: .main, default: Color.red)
    }
}

// Helper: charge un asset s’il existe, sinon renvoie un fallback (ici dynamique)
private extension Color {
    init(_ name: String, bundle: Bundle, default fallback: Color) {
        if UIColor(named: name, in: bundle, compatibleWith: nil) != nil {
            self = Color(name)
        } else {
            self = fallback
        }
    }
}
