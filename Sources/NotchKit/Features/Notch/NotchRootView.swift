import SwiftUI

/// Contenido de la ventana del notch. Dibuja una forma negra pegada al borde
/// superior que crece desde el tamaño del notch hasta el panel expandido.
struct NotchRootView: View {
    let model: NotchViewModel
    let modules: ModuleCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = model.shapeSize
        let expanded = model.state.isExpanded
        let radius: CGFloat = expanded ? 24 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

        ZStack(alignment: .top) {
            // Sin notch físico, el reposo no debe dejar una píldora negra fija en
            // la barra de menús. Una opacidad mínima mantiene la zona sensible al
            // cursor y al clic: el sistema ignora los píxeles totalmente transparentes.
            Color.black
                .opacity(model.state == .idle && !model.geometry.hasPhysicalNotch ? 0.01 : 1)

            if expanded {
                ExpandedPanelView(model: model, modules: modules)
                    .frame(width: model.expandedSize.width, height: model.expandedSize.height)
                    .transition(.opacity)
            } else {
                Button {
                    model.send(.clicked)
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir el panel")

                if model.state == .compact {
                    CompactView(content: model.compactContent, notchWidth: model.geometry.notchRect.width)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(animation, value: model.state)
        .animation(animation, value: size)
        .ignoresSafeArea()
    }

    private var animation: Animation? {
        let duration = model.store.preferences.animationDuration
        guard duration > 0 else { return nil }
        // Con "Reducir movimiento" se sustituye el muelle por un fundido corto.
        if reduceMotion { return .easeOut(duration: min(duration, 0.15)) }
        return .spring(duration: duration, bounce: 0.12)
    }
}

struct CompactView: View {
    let content: CompactContent
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            item(content.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
                .frame(width: notchWidth)
            item(content.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func item(_ item: CompactContent.Item?) -> some View {
        if let item {
            HStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                if let end = item.countdownEnd {
                    // Se actualiza sola cada segundo; el rango no puede invertirse.
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                } else if let text = item.text {
                    Text(text)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
        }
    }
}
