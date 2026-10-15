import SwiftUI

extension ModuleID {
    var title: LocalizedStringKey {
        switch self {
        case .music: "Música"
        case .calendar: "Calendario"
        case .apps: "Aplicaciones"
        case .quickControls: "Accesos rápidos"
        case .activity: "Actividad"
        case .reminders: "Tareas"
        case .shelf: "Bandeja y AirDrop"
        case .camera: "Espejo"
        case .timer: "Temporizador"
        }
    }

    var systemImage: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .apps: "square.grid.2x2"
        case .quickControls: "slider.horizontal.3"
        case .activity: "bell"
        case .reminders: "checklist"
        case .shelf: "tray.and.arrow.down"
        case .camera: "person.crop.square"
        case .timer: "timer"
        }
    }
}
