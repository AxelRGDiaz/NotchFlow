import CoreGraphics

/// Marcos de la forma visible y de la ventana para cada estado. La ventana se
/// ajusta a la forma: en reposo ocupa solo el notch y nunca cubre zonas de la
/// barra de menús que no esté dibujando.
///
/// Todos los marcos están centrados en el notch; la vista se apoya en ello
/// para colocar la forma arriba y al centro de la ventana.
public struct NotchLayout: Equatable, Sendable {
    /// Espacio alrededor del panel expandido para dibujar su sombra.
    public static let shadowMargin: CGFloat = 28

    public var geometry: NotchGeometry
    public var contentSize: CGSize
    /// Ancho que pide el contenido compacto a cada lado del notch.
    public var wingWidth: CGFloat
    public var maxWingWidth: CGFloat

    public init(geometry: NotchGeometry, contentSize: CGSize, wingWidth: CGFloat, maxWingWidth: CGFloat) {
        self.geometry = geometry
        self.contentSize = contentSize
        self.wingWidth = wingWidth
        self.maxWingWidth = maxWingWidth
    }

    public func shapeFrame(for state: NotchStateMachine.State) -> CGRect {
        switch state {
        case .idle:
            geometry.notchRect
        case .compact:
            geometry.compactFrame(leadingWing: wingWidth, trailingWing: wingWidth, maxWing: maxWingWidth)
        case .expanded:
            geometry.expandedFrame(contentSize: contentSize)
        }
    }

    public func windowFrame(for state: NotchStateMachine.State) -> CGRect {
        let shape = shapeFrame(for: state)
        guard state.isExpanded else { return shape }
        let margin = Self.shadowMargin
        return CGRect(
            x: shape.minX - margin,
            y: shape.minY - margin,
            width: shape.width + margin * 2,
            height: shape.height + margin
        )
    }
}
