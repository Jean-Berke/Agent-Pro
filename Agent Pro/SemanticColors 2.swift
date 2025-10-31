// SemanticColors 2.swift
// Désactivé pour éviter les redéclarations (duplicata de SemanticColors.swift).
// Tu peux supprimer ce fichier du projet ou le retirer du Target Membership.

#if false
import SwiftUI

enum AppColors {
    static var background: Color { Color("Background", bundle: .main, default: AppTheme.lightGray) }
    static var card: Color { Color("CardBackground", bundle: .main, default: .white) }
    static var textPrimary: Color { Color("TextPrimary", bundle: .main, default: AppTheme.darkNavy) }
    static var textSecondary: Color { Color("TextSecondary", bundle: .main, default: AppTheme.darkGray) }
    static var tintPrimary: Color { Color("TintPrimary", bundle: .main, default: AppTheme.primaryBlue) }
    static var tintSecondary: Color { Color("TintSecondary", bundle: .main, default: AppTheme.secondaryBlue) }
    static var accent: Color { Color("Accent", bundle: .main, default: AppTheme.accentGold) }
    static var success: Color { Color("Success", bundle: .main, default: AppTheme.successGreen) }
    static var warning: Color { Color("Warning", bundle: .main, default: AppTheme.warningOrange) }
    static var error: Color { Color("Error", bundle: .main, default: AppTheme.errorRed) }
}

private extension Color {
    init(_ name: String, bundle: Bundle, default fallback: Color) {
        if UIColor(named: name, in: bundle, compatibleWith: nil) != nil { self = Color(name) } else { self = fallback }
    }
}
#endif
