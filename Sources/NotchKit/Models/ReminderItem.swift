import Foundation

/// Recordatorio pendiente tal como lo muestra el módulo de tareas.
public struct ReminderItem: Identifiable, Equatable, Sendable {
    /// `calendarItemIdentifier` de EventKit.
    public var id: String
    public var title: String
    public var dueDate: Date?
    public var listTitle: String?

    public init(id: String, title: String, dueDate: Date? = nil, listTitle: String? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.listTitle = listTitle
    }

    /// Primero los que tienen fecha, del más próximo al más lejano; después
    /// el resto en el orden en que llegan.
    public static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.enumerated().sorted { a, b in
            switch (a.element.dueDate, b.element.dueDate) {
            case let (x?, y?): x == y ? a.offset < b.offset : x < y
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): a.offset < b.offset
            }
        }.map(\.element)
    }
}
