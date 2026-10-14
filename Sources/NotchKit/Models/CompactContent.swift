import CoreGraphics

/// Lo que se muestra en las alas del estado compacto. Vacío significa que no
/// hay actividad y el notch vuelve a reposo.
public struct CompactContent: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var systemImage: String
        public var text: String?
        public var accessibilityLabel: String

        public init(systemImage: String, text: String? = nil, accessibilityLabel: String) {
            self.systemImage = systemImage
            self.text = text
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public var leading: Item?
    public var trailing: Item?

    public init(leading: Item? = nil, trailing: Item? = nil) {
        self.leading = leading
        self.trailing = trailing
    }

    public var isEmpty: Bool { leading == nil && trailing == nil }

    /// Ancho que necesita cada ala. Las dos miden lo mismo para que la forma
    /// quede centrada en el notch.
    public var wingWidth: CGFloat {
        if isEmpty { return 0 }
        let hasText = leading?.text != nil || trailing?.text != nil
        return hasText ? 92 : 40
    }
}
