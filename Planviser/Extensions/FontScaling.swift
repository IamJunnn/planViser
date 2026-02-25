import SwiftUI

// MARK: - Environment key for font scale factor

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

// MARK: - Scaled font ViewModifier

struct ScaledFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.fontScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: round(baseSize * scale), weight: resolvedWeight))
    }

    private var resolvedWeight: Font.Weight {
        if let weight { return weight }
        switch style {
        case .headline: return .bold
        default: return .regular
        }
    }

    /// Approximate macOS base sizes for standard text styles.
    private var baseSize: CGFloat {
        switch style {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .subheadline: return 11
        case .body:        return 13
        case .callout:     return 12
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 9
        @unknown default:  return 13
        }
    }
}

// MARK: - Scaled font by raw point size

struct ScaledFontSizeModifier: ViewModifier {
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design?
    let monospacedDigit: Bool
    @Environment(\.fontScale) private var scale

    func body(content: Content) -> some View {
        var font: Font = .system(size: round(baseSize * scale), weight: weight, design: design ?? .default)
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight))
    }

    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFontSizeModifier(baseSize: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }
}
