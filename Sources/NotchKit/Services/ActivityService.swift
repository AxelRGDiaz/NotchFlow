import Foundation
import Observation

/// Actividad reciente generada por la propia app. Vive solo en memoria y no
/// incluye notificaciones de otras aplicaciones: macOS no da acceso a ellas.
@MainActor
@Observable
final class ActivityService {
    static let capacity = 30

    private(set) var items: [ActivityItem] = []

    func record(_ kind: ActivityItem.Kind, title: String, detail: String? = nil, date: Date = .now) {
        items.insert(ActivityItem(kind: kind, title: title, detail: detail, date: date), at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    func clear() {
        items = []
    }
}
