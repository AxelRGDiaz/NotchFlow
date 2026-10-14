import SwiftUI

/// Estado del sistema y accesos a Ajustes. Solo el volumen se modifica desde
/// aquí; lo demás no tiene API pública de control y enlaza a su panel.
struct QuickControlsModuleView: View {
    let battery: BatteryService
    let audio: AudioService
    let wifi: WiFiService

    var body: some View {
        ModuleCard(module: .quickControls) {
            VStack(alignment: .leading, spacing: 9) {
                volumeRow
                if let status = battery.status {
                    SettingsLinkRow(
                        systemImage: Self.batteryImage(status),
                        title: "Batería",
                        value: Text(status.level, format: .percent.precision(.fractionLength(0))),
                        destination: .battery
                    )
                }
                SettingsLinkRow(
                    systemImage: wifi.state == .on ? "wifi" : "wifi.slash",
                    title: "Wi-Fi",
                    value: wifiValue,
                    destination: .wifi
                )
                SettingsLinkRow(systemImage: "sun.max", title: "Brillo", value: nil, destination: .displays)
                SettingsLinkRow(systemImage: "dot.radiowaves.left.and.right", title: "Bluetooth", value: nil, destination: .bluetooth)
            }
        }
    }

    @ViewBuilder
    private var volumeRow: some View {
        if let volume = audio.volume {
            HStack(spacing: 6) {
                PanelIconButton(
                    systemImage: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: volume.isMuted ? "Activar sonido" : "Silenciar",
                    size: 11
                ) {
                    audio.setMuted(!volume.isMuted)
                }
                if volume.isAdjustable {
                    Slider(
                        value: Binding(get: { volume.level }, set: { audio.setLevel($0) }),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .tint(.white)
                    .accessibilityLabel("Volumen")
                } else {
                    Text("Esta salida no permite ajustar el volumen")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        } else {
            SettingsLinkRow(systemImage: "speaker.slash", title: "Sin salida de audio", value: nil, destination: .sound)
        }
    }

    private var wifiValue: Text? {
        switch wifi.state {
        case .on: Text("Activado")
        case .off: Text("Desactivado")
        case .unavailable, .unauthorized: nil
        }
    }

    private static func batteryImage(_ status: BatteryStatus) -> String {
        if status.isCharging || status.isPluggedIn { return "battery.100.bolt" }
        switch status.level {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Fila que muestra un estado y abre el panel de Ajustes correspondiente.
private struct SettingsLinkRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: Text?
    let destination: SystemSettings

    var body: some View {
        Button {
            destination.open()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 11))
                Spacer(minLength: 4)
                if let value {
                    value
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir en Ajustes del Sistema")
        .accessibilityHint("Abre Ajustes del Sistema")
    }
}
