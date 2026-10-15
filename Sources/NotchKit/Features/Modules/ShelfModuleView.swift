import SwiftUI
import UniformTypeIdentifiers

/// Bandeja y AirDrop, como en NotchNook: a la izquierda una zona para enviar
/// por AirDrop; a la derecha los archivos guardados, que se sacan
/// arrastrándolos a otra app y siguen en la bandeja hasta que se quitan.
struct ShelfModuleView: View {
    let shelf: ShelfService

    var body: some View {
        ModuleCard(module: .shelf) {
            HStack(spacing: 10) {
                airDropZone
                    .frame(width: 128)
                tray
            }
            .frame(maxHeight: .infinity)
            .onAppear { shelf.pruneMissing() }
        }
    }

    /// Soltar aquí envía por AirDrop; un clic envía todo lo que hay en la bandeja.
    private var airDropZone: some View {
        let targeted = shelf.targetedZone == .airDrop
        return Button {
            shelf.sendViaAirDrop(shelf.items)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(targeted ? Color.white : Color(red: 0.39, green: 0.71, blue: 1))
                Text("AirDrop")
                    .font(.system(size: 13, weight: .semibold))
                Text(shelf.items.isEmpty ? "Suelta archivos" : "Enviar todo")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(targeted ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.45) : Color.white.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(shelf.items.isEmpty ? "Suelta archivos aquí para enviarlos por AirDrop" : "Enviar la bandeja por AirDrop")
        .dropDestination(for: URL.self) { urls, _ in
            shelf.sendViaAirDrop(urls)
            return true
        } isTargeted: { setTargeted(.airDrop, $0) }
    }

    private var tray: some View {
        let targeted = shelf.targetedZone == .shelf
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .medium))
                    Text("Suelta archivos aquí para guardarlos")
                        .font(.system(size: 12, weight: .medium))
                    Text("Luego arrástralos a donde los necesites")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text(shelf.items.count == 1 ? "1 archivo" : "\(shelf.items.count) archivos")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Vaciar") { shelf.clear() }
                        .buttonStyle(PanelButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            FileTile(url: url, shelf: shelf)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(.white.opacity(targeted ? 0.16 : 0.05)))
        .overlay(shape.strokeBorder(.white.opacity(targeted ? 0.6 : 0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { setTargeted(.shelf, $0) }
    }

    private func setTargeted(_ zone: ShelfDropZone, _ targeted: Bool) {
        if targeted {
            shelf.targetedZone = zone
        } else if shelf.targetedZone == zone {
            shelf.targetedZone = nil
        }
    }
}

/// Un archivo de la bandeja: se arrastra hacia fuera (y sigue en la bandeja),
/// doble clic lo abre y el botón de la esquina lo quita.
private struct FileTile: View {
    let url: URL
    let shelf: ShelfService

    /// Arrastra el archivo en sí (su URL), no una copia de su contenido: así
    /// el destino recibe el nombre original.
    private static func provider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 86)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag { Self.provider(for: url) }
        .onTapGesture(count: 2) { shelf.open(url) }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .help("Quitar de la bandeja")
            .accessibilityLabel("Quitar \(url.lastPathComponent)")
        }
        .help(url.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(url.lastPathComponent)
        .contextMenu {
            Button("Abrir") { shelf.open(url) }
            Button("Mostrar en Finder") { shelf.reveal(url) }
            Button("Enviar por AirDrop") { shelf.sendViaAirDrop([url]) }
            Divider()
            Button("Quitar de la bandeja") { shelf.remove(url) }
        }
    }
}
