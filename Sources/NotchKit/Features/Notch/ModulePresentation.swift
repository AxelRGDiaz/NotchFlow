import SwiftUI

extension ModuleID {
    var title: LocalizedStringKey {
        switch self {
        case .music: "Música"
        case .calendar: "Calendario"
        case .apps: "Aplicaciones"
        case .quickControls: "Accesos rápidos"
        case .activity: "Actividad"
        }
    }

    var systemImage: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .apps: "square.grid.2x2"
        case .quickControls: "slider.horizontal.3"
        case .activity: "bell"
        }
    }
}
