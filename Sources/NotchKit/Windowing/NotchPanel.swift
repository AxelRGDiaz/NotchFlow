import AppKit
import SwiftUI

/// Ventana del notch: sin borde, no activa la app y flota justo por encima de
/// la barra de menús en todos los espacios.
final class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Un nivel por encima de la barra de menús; nada más alto.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Solo pasa a ser ventana clave si se le pide expresamente, para no
        // quitarle el teclado a la app que el usuario está usando.
        becomesKeyOnlyIfNeeded = true
        // Prolonga un notch negro: su contenido es siempre oscuro.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit no debe apartar la ventana de la barra de menús.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Vista contenedora que avisa cuando el cursor entra o sale de la ventana.
final class PointerTrackingView: NSView {
    var onPointerChange: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerChange?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerChange?()
    }
}

/// Acepta el primer clic aunque la ventana no sea la clave, de modo que los
/// botones respondan sin un clic previo de activación.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
