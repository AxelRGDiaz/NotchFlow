import SwiftUI

/// Actividad reciente de la propia app. No son las notificaciones del sistema:
/// macOS no permite leer las de otras aplicaciones.
struct ActivityModuleView: View {
    let activity: ActivityService

    var body: some View {
        ModuleCard(module: .activity) {
            if activity.items.isEmpty {
                ModuleMessage(text: "Sin actividad reciente. Aquí aparecen los avisos de NotchFlow: eventos próximos, cambios de canción y batería. Las notificaciones de otras apps no son accesibles.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(activity.items) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: Self.image(for: item.kind))
                                    .font(.system(size: 10))
                                    .frame(width: 14)
                                    .foregroundStyle(.white.opacity(0.6))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        if let detail = item.detail {
                                            Text(detail).lineLimit(1)
                                            Text("·")
                                        }
                                        Text(item.date, format: .dateTime.hour().minute())
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private static func image(for kind: ActivityItem.Kind) -> String {
        switch kind {
        case .eventSoon: "calendar"
        case .trackChanged: "music.note"
        case .batteryLow: "battery.25"
        case .chargingChanged: "bolt.fill"
        }
    }
}
