import Foundation

public struct CalendarEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var calendarTitle: String?
    /// Color del calendario como componentes sRGB (0–1).
    public var calendarColor: [Double]?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        calendarTitle: String? = nil,
        calendarColor: [Double]? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
    }

    public enum Phase: Equatable, Sendable {
        case upcoming(startsIn: TimeInterval)
        case inProgress(remaining: TimeInterval)
        case ended
    }

    public func phase(at now: Date) -> Phase {
        if now >= end { return .ended }
        if now >= start { return .inProgress(remaining: end.timeIntervalSince(now)) }
        return .upcoming(startsIn: start.timeIntervalSince(now))
    }
}

/// Consultas puras sobre una lista de eventos ya cargada.
public enum EventTimeline {
    /// Evento en curso o siguiente. Los de día completo se excluyen: no tienen
    /// una hora de inicio útil para una cuenta atrás.
    public static func currentOrNext(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && $0.end > now }
            .min { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    public static func events(on day: Date, in events: [CalendarEvent], calendar: Calendar = .current) -> [CalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events
            .filter { $0.start < interval.end && $0.end > interval.start }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Próximo instante en que cambia lo que se muestra (empieza o termina un
    /// evento). Permite programar un único temporizador en lugar de sondear.
    public static func nextBoundary(in events: [CalendarEvent], after now: Date) -> Date? {
        events
            .filter { !$0.isAllDay }
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now }
            .min()
    }
}
