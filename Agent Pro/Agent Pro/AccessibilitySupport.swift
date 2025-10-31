// AccessibilitySupport.swift
import SwiftUI

enum TextRole {
    case largeTitle, title1, title2, title3
    case headline, subheadline
    case body, callout, footnote, caption

    var textStyle: Font.TextStyle {
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
    // Applique une police relative (Dynamic Type) avec option design .rounded
    func accessibleFont(_ role: TextRole, weight: Font.Weight = .regular, rounded: Bool = true) -> some View {
        let design: Font.Design = rounded ? .rounded : .default
        return self
            .font(.system(role.textStyle, design: design))
            .fontWeight(weight)
    }

    // Pour les boutons icônes seuls (ex: cloche, FAB)
    func iconButtonA11y(_ label: String) -> some View {
        self.accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
    }

    // Pour laisser mieux respirer les gros titres aux grandes tailles
    func allowTextScaling() -> some View {
        self.minimumScaleFactor(0.85)
            .lineLimit(nil)
    }
}
