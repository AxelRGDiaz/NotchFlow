import SwiftUI

/// Panel expandido: una franja a la altura del notch, una fila de pestañas
/// justo debajo y el módulo elegido ocupando todo el ancho.
struct ExpandedPanelView: View {
    let model: NotchViewModel
    let modules: ModuleCoordinator

    var body: some View {
        let notch = model.geometry.notchRect
        let visible = model.store.preferences.visibleModules
        let current = model.currentModule(in: visible)
        VStack(spacing: 0) {
            header(notchWidth: model.geometry.hasPhysicalNotch ? notch.width : 0)
                .frame(height: notch.height)

            if let current {
                ModuleTabs(visible: visible, current: current) { module in
                    withAnimation(.easeInOut(duration: 0.2)) { model.selectedModule = module }
                }
                .padding(.top, 6)
                .padding(.bottom, 10)

                moduleView(current)
                    .id(current)
                    .transition(.opacity)
                    .padding(.bottom, 16)
            } else {
                Text("No hay módulos visibles. Actívalos en Configuración.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    /// Franja a la altura del notch: su centro queda tapado por el notch
    /// físico, así que solo se usan los laterales, con poco contenido para
    /// que nunca llegue a quedar debajo.
    private func header(notchWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
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
        .padding(.horizontal, 16)
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
        case .reminders:
            RemindersModuleView(reminders: modules.reminders)
        case .shelf:
            ShelfModuleView(shelf: modules.shelf)
        case .camera:
            CameraModuleView(camera: modules.camera)
        case .timer:
            TimerModuleView(timer: modules.timer)
        }
    }
}

/// Pestañas de los módulos: la elegida muestra icono y nombre; el resto,
/// solo el icono. Si no caben (panel pequeño), el nombre se omite.
private struct ModuleTabs: View {
    let visible: [ModuleID]
    let current: ModuleID
    let select: (ModuleID) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsTitle: true)
            row(showsTitle: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(showsTitle: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(visible, id: \.self) { module in
                let selected = module == current
                Button {
                    select(module)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: module.systemImage)
                            .font(.system(size: 15, weight: selected ? .semibold : .medium))
                        if selected, showsTitle {
                            Text(module.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, selected && showsTitle ? 14 : 0)
                    .frame(minWidth: 40, minHeight: 34)
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.8))
                    .background(selected ? Color.white : Color.white.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(module.title)
                .accessibilityLabel(module.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

private struct HeaderButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help(label)
        .accessibilityLabel(label)
    }
}
