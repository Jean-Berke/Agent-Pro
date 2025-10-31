// AccessibilitySupport 2.swift
// Désactivé pour éviter les redéclarations (duplicata de AccessibilitySupport.swift).
// Tu peux supprimer ce fichier du projet ou le retirer du Target Membership.

#if false
import SwiftUI

enum TextRole {
    case largeTitle, title1, title2, title3
    case headline, subheadline
    case body, callout, footnote, caption

    var font: Font {
        switch self {
        case .largeTitle: return .largeTitle
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption
        }
    }
}

extension View {
    func accessibleFont(_ role: TextRole, weight: Font.Weight = .regular, rounded: Bool = true) -> some View {
        let base = role.font
        if rounded { return self.font(.system(base, design: .rounded)).fontWeight(weight) }
        else { return self.font(base).fontWeight(weight) }
    }

    func iconButtonA11y(_ label: String) -> some View {
        self.accessibilityLabel(Text(label)).accessibilityAddTraits(.isButton)
    }

    func allowTextScaling() -> some View {
        self.minimumScaleFactor(0.85).lineLimit(nil)
    }
}
#endif
