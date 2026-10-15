import SwiftUI

/// Contenedor común de un módulo: ocupa todo el ancho del panel bajo las
/// pestañas, que ya muestran su nombre.
struct ModuleCard<Content: View>: View {
    let module: ModuleID
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(module.title)
    }
}

/// Estado sin datos de un módulo: explica qué ocurre y, si procede, qué hacer.
struct ModuleMessage: View {
    let text: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(configuration.isPressed ? 0.28 : 0.16), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Botón de icono sin fondo para controles dentro de las tarjetas.
struct PanelIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 14, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Texto que explica al usuario un estado de permiso de un servicio.
extension ServiceStatus {
    var isPermissionProblem: Bool {
        switch self {
        case .needsPermission, .denied: true
        default: false
        }
    }
}
