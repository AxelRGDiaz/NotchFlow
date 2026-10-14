import AppKit

/// Datos de una pantalla que necesita la geometría, desacoplados de `NSScreen`
/// para poder probarla. Coordenadas globales de AppKit (origen abajo a la izquierda).
public struct ScreenDescriptor: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?
    public var menuBarHeight: CGFloat
    public var isBuiltIn: Bool

    public init(
        displayID: CGDirectDisplayID,
        frame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeft: CGRect? = nil,
        auxiliaryTopRight: CGRect? = nil,
        menuBarHeight: CGFloat = 24,
        isBuiltIn: Bool = false
    ) {
        self.displayID = displayID
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.menuBarHeight = menuBarHeight
        self.isBuiltIn = isBuiltIn
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxiliaryTopLeft != nil && auxiliaryTopRight != nil
    }
}

extension ScreenDescriptor {
    @MainActor
    public init(_ screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let id = CGDirectDisplayID(number?.uint32Value ?? 0)
        self.init(
            displayID: id,
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            isBuiltIn: CGDisplayIsBuiltin(id) != 0
        )
    }
}

/// Geometría del notch y de los marcos que la interfaz ocupa a su alrededor.
public struct NotchGeometry: Equatable, Sendable {
    /// Tamaño de la "píldora" usada en pantallas sin notch físico.
    public static let virtualNotchWidth: CGFloat = 190
    private static let fallbackMenuBarHeight: CGFloat = 24

    public let screenFrame: CGRect
    /// Rectángulo del notch físico, o de la píldora virtual si no hay notch.
    public let notchRect: CGRect
    public let hasPhysicalNotch: Bool
    /// Ancho libre a cada lado del notch dentro de la barra de menús.
    public let leadingSpace: CGFloat
    public let trailingSpace: CGFloat

    public init(screen: ScreenDescriptor) {
        screenFrame = screen.frame
        if screen.hasNotch, let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight {
            hasPhysicalNotch = true
            notchRect = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaTop,
                width: right.minX - left.maxX,
                height: screen.safeAreaTop
            )
        } else {
            hasPhysicalNotch = false
            let height = screen.menuBarHeight > 0 ? screen.menuBarHeight : Self.fallbackMenuBarHeight
            let width = min(Self.virtualNotchWidth, screen.frame.width)
            notchRect = CGRect(
                x: (screen.frame.midX - width / 2).rounded(),
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
        }
        leadingSpace = notchRect.minX - screen.frame.minX
        trailingSpace = screen.frame.maxX - notchRect.maxX
    }

    /// Pantalla donde debe vivir la interfaz: la que tiene notch; si no hay,
    /// la integrada; si tampoco, la primera (la principal de `NSScreen.screens`).
    public static func preferredScreen(from screens: [ScreenDescriptor]) -> ScreenDescriptor? {
        screens.first(where: \.hasNotch) ?? screens.first(where: \.isBuiltIn) ?? screens.first
    }

    /// Marco del estado compacto: el notch más un "ala" a cada lado. Las alas
    /// se limitan a `maxWing` y al espacio real disponible, porque tapan menús
    /// e iconos de estado cuya extensión no es consultable por API pública.
    public func compactFrame(leadingWing: CGFloat, trailingWing: CGFloat, maxWing: CGFloat) -> CGRect {
        let leading = clamp(leadingWing, upTo: min(maxWing, leadingSpace))
        let trailing = clamp(trailingWing, upTo: min(maxWing, trailingSpace))
        return CGRect(
            x: notchRect.minX - leading,
            y: notchRect.minY,
            width: notchRect.width + leading + trailing,
            height: notchRect.height
        )
    }

    /// Marco del panel expandido: cuelga del borde superior, centrado en el
    /// notch. La franja superior (altura del notch) queda reservada porque el
    /// notch físico tapa su centro; el contenido va debajo.
    public func expandedFrame(contentSize: CGSize) -> CGRect {
        let width = min(max(contentSize.width, notchRect.width), screenFrame.width)
        let height = min(contentSize.height + notchRect.height, screenFrame.height)
        var x = (notchRect.midX - width / 2).rounded()
        x = min(max(x, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    private func clamp(_ value: CGFloat, upTo limit: CGFloat) -> CGFloat {
        min(max(value, 0), max(limit, 0))
    }
}
