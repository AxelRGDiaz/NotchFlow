import SwiftUI

/// Accesos directos a las aplicaciones favoritas. El punto indica que la app
/// está abierta; no representa su icono de la barra de menús.
struct AppsModuleView: View {
    let apps: ApplicationService
    let onOpenSettings: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 68), spacing: 12)]

    var body: some View {
        ModuleCard(module: .apps) {
            if apps.favorites.isEmpty {
                ModuleMessage(text: "Añade tus aplicaciones favoritas para abrirlas desde aquí.", actionTitle: "Elegir aplicaciones") {
                    onOpenSettings()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(apps.favorites) { app in
                            Button {
                                apps.open(app)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: apps.icon(for: app))
                                        .resizable()
                                        .frame(width: 52, height: 52)
                                    Circle()
                                        .fill(.white.opacity(apps.isRunning(app) ? 0.7 : 0))
                                        .frame(width: 4, height: 4)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(app.displayName)
                            .accessibilityLabel(app.displayName)
                            .accessibilityValue(apps.isRunning(app) ? Text("Abierta") : Text(""))
                        }
                    }
                }
            }
        }
    }
}
