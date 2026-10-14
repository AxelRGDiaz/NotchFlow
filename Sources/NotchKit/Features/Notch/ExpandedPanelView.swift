import SwiftUI

struct ExpandedPanelView: View {
    let model: NotchViewModel
    let modules: ModuleCoordinator

    var body: some View {
        let notch = model.geometry.notchRect
        let visible = model.store.preferences.visibleModules
        ScrollViewReader { scroll in
            VStack(spacing: 0) {
                header(visible: visible, notchWidth: model.geometry.hasPhysicalNotch ? notch.width : 0) { module in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scroll.scrollTo(module, anchor: .leading)
                    }
                }
                .frame(height: notch.height)

                content(visible: visible)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }

    /// Franja a la altura del notch: su centro queda tapado por el notch
    /// físico, así que solo se usan los laterales. A la izquierda, un botón
    /// por módulo para saltar a él; a la derecha, fijar y configuración.
    private func header(visible: [ModuleID], notchWidth: CGFloat, jump: @escaping (ModuleID) -> Void) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(visible, id: \.self) { module in
                    HeaderButton(systemImage: module.systemImage, label: module.title) {
                        jump(module)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
                .frame(width: notchWidth)

            HStack(spacing: 6) {
                HeaderButton(
                    systemImage: model.isPinned ? "pin.fill" : "pin",
                    label: model.isPinned ? "Dejar de fijar el panel" : "Fijar el panel"
                ) {
                    model.send(.pinToggled)
                }
                HeaderButton(systemImage: "gearshape", label: "Configuración") {
                    model.openSettings()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    /// Los módulos van en una fila desplazable en el orden configurado: no
    /// siempre caben todos a la vez en el ancho del panel.
    @ViewBuilder
    private func content(visible: [ModuleID]) -> some View {
        if visible.isEmpty {
            Text("No hay módulos visibles. Actívalos en Configuración.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visible, id: \.self) { module in
                        moduleView(module)
                            .id(module)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 12)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    @ViewBuilder
    private func moduleView(_ module: ModuleID) -> some View {
        switch module {
        case .music:
            MusicModuleView(music: modules.music)
        case .calendar:
            CalendarModuleView(calendar: modules.calendar)
        case .apps:
            AppsModuleView(apps: modules.apps) { model.openSettings(.apps) }
        case .quickControls:
            QuickControlsModuleView(battery: modules.battery, audio: modules.audio, wifi: modules.wifi)
        case .activity:
            ActivityModuleView(activity: modules.activity)
        }
    }
}

private struct HeaderButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help(label)
        .accessibilityLabel(label)
    }
}
