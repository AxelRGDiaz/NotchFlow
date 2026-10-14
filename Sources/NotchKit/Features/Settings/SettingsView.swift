import SwiftUI

enum SettingsTab: Hashable {
    case general
    case modules
    case apps
}

/// Pestaña seleccionada, para poder abrir la configuración en una concreta.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsTab = .general
}

struct SettingsView: View {
    let store: PreferencesStore
    let loginItem: LoginItemService
    let apps: ApplicationService
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsView(store: store, loginItem: loginItem)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ModuleSettingsView(store: store)
                .tabItem { Label("Módulos", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.modules)
            FavoriteAppsSettingsView(apps: apps)
                .tabItem { Label("Aplicaciones", systemImage: "app.badge") }
                .tag(SettingsTab.apps)
        }
        .frame(width: 480, height: 600)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var store: PreferencesStore
    let loginItem: LoginItemService

    var body: some View {
        let preferences = store.preferences
        Form {
            Section("Apertura") {
                Toggle("Abrir al pasar el cursor", isOn: $store.preferences.opensOnHover)
                    // Siempre debe quedar al menos una forma de abrir el panel.
                    .disabled(preferences.opensOnHover && !preferences.opensOnClick)
                if preferences.opensOnHover {
                    SecondsSlider("Retardo de apertura", value: $store.preferences.hoverOpenDelay, range: 0...1)
                }
                Toggle("Abrir al hacer clic", isOn: $store.preferences.opensOnClick)
                    .disabled(preferences.opensOnClick && !preferences.opensOnHover)
            }

            Section("Cierre") {
                Toggle("Cerrar al salir el cursor", isOn: $store.preferences.closesOnPointerExit)
                if preferences.closesOnPointerExit {
                    SecondsSlider("Retardo de cierre", value: $store.preferences.closeDelay, range: 0...3)
                }
            }

            Section {
                Picker("Tamaño del panel", selection: $store.preferences.panelSize) {
                    Text("Pequeño").tag(PanelSize.small)
                    Text("Mediano").tag(PanelSize.medium)
                    Text("Grande").tag(PanelSize.large)
                }
                SecondsSlider("Duración de las animaciones", value: $store.preferences.animationDuration, range: 0...1)
                LabeledContent("Ancho máximo junto al notch") {
                    HStack {
                        Slider(value: $store.preferences.maxWingWidth, in: 40...240, step: 10)
                        Text("\(Int(preferences.maxWingWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Picker("Apariencia", selection: $store.preferences.appearance) {
                    Text("Automática").tag(AppearanceMode.system)
                    Text("Clara").tag(AppearanceMode.light)
                    Text("Oscura").tag(AppearanceMode.dark)
                }
            } header: {
                Text("Aspecto")
            } footer: {
                Text("La apariencia se aplica a esta ventana. El panel del notch es siempre oscuro para fundirse con el notch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Reproducción de música", isOn: indicator(.music))
                Toggle("Próximo evento", isOn: indicator(.nextEvent))
                Toggle("Batería baja", isOn: indicator(.battery))
            } header: {
                Text("Junto al notch")
            } footer: {
                Text("Indicadores que aparecen a los lados del notch cuando hay actividad. Sin actividad no se muestra nada.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Sistema") {
                Toggle("Abrir al iniciar sesión", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .disabled(loginItem.state == .unavailable)
                if let message = loginItemMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restablecer la configuración", role: .destructive) {
                    store.reset()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    private func indicator(_ indicator: CompactIndicator) -> Binding<Bool> {
        Binding(
            get: { store.preferences.compactIndicators.contains(indicator) },
            set: { enabled in
                if enabled {
                    store.preferences.compactIndicators.insert(indicator)
                } else {
                    store.preferences.compactIndicators.remove(indicator)
                }
            }
        )
    }

    private var loginItemMessage: String? {
        if let error = loginItem.lastErrorMessage { return error }
        switch loginItem.state {
        case .requiresApproval:
            return String(localized: "Falta aprobarlo en Ajustes del Sistema > General > Ítems de inicio.")
        case .unavailable:
            return String(localized: "No disponible: la app debe ejecutarse desde su paquete .app.")
        case .enabled, .disabled:
            return nil
        }
    }
}

private struct SecondsSlider: View {
    let title: LocalizedStringKey
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>

    init(_ title: LocalizedStringKey, value: Binding<TimeInterval>, range: ClosedRange<TimeInterval>) {
        self.title = title
        self._value = value
        self.range = range
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 0.05)
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct ModuleSettingsView: View {
    let store: PreferencesStore

    var body: some View {
        let order = store.preferences.moduleOrder
        VStack(alignment: .leading, spacing: 8) {
            Text("Elige qué secciones aparecen en el panel y en qué orden. Arrastra para reordenar.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(order, id: \.self) { module in
                    HStack {
                        Label(module.title, systemImage: module.systemImage)
                        Spacer()
                        Button {
                            move(module, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(module == order.first)
                        .accessibilityLabel("Subir")
                        Button {
                            move(module, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(module == order.last)
                        .accessibilityLabel("Bajar")
                        Toggle("Visible", isOn: visibility(of: module))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .buttonStyle(.borderless)
                }
                .onMove { source, destination in
                    store.preferences.moduleOrder.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
        .padding(20)
    }

    private func visibility(of module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { !store.preferences.hiddenModules.contains(module) },
            set: { visible in
                if visible {
                    store.preferences.hiddenModules.remove(module)
                } else {
                    store.preferences.hiddenModules.insert(module)
                }
            }
        )
    }

    private func move(_ module: ModuleID, by offset: Int) {
        var order = store.preferences.moduleOrder
        guard let index = order.firstIndex(of: module), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        store.preferences.moduleOrder = order
    }
}

private struct FavoriteAppsSettingsView: View {
    let apps: ApplicationService

    var body: some View {
        let favorites = apps.favorites
        VStack(alignment: .leading, spacing: 8) {
            Text("Accesos directos que aparecen en el panel. Abren la aplicación; no sustituyen a su icono de la barra de menús.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(favorites) { app in
                    HStack {
                        Image(nsImage: apps.icon(for: app))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(app.displayName)
                        if apps.url(for: app) == nil {
                            Text("No instalada")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            apps.move(app, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(app == favorites.first)
                        .accessibilityLabel("Subir")
                        Button {
                            apps.move(app, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(app == favorites.last)
                        .accessibilityLabel("Bajar")
                        Button(role: .destructive) {
                            apps.remove(app)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel("Quitar \(app.displayName)")
                    }
                    .buttonStyle(.borderless)
                }
                .onMove { source, destination in
                    apps.move(fromOffsets: source, toOffset: destination)
                }
            }
            .overlay {
                if favorites.isEmpty {
                    Text("Aún no hay aplicaciones.")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Añadir aplicaciones…") {
                apps.presentAddPanel()
            }
        }
        .padding(20)
    }
}
