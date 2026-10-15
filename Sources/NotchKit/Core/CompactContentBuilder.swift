import Foundation

/// Decide qué se muestra junto al notch a partir del estado de los servicios.
/// Es una función pura: devuelve también cuándo hay que volver a calcular,
/// para programar un único aviso en lugar de sondear.
public enum CompactContentBuilder {
    /// Un evento aparece cuando falta este tiempo o menos para que empiece.
    public static let eventLeadTime: TimeInterval = 30 * 60
    /// Tras empezar, el evento sigue visible este tiempo como "ahora".
    public static let eventLingerTime: TimeInterval = 5 * 60
    public static let lowBatteryLevel = 0.2
    /// Tras terminar, el temporizador sigue avisando en el ala este tiempo.
    public static let timerFinishedLinger: TimeInterval = 30

    public struct Input: Sendable {
        public var nowPlaying: NowPlaying?
        public var events: [CalendarEvent]
        public var battery: BatteryStatus?
        /// Siempre se muestra si está en marcha: lo ha iniciado el usuario.
        public var timer: CountdownTimer?
        public var indicators: Set<CompactIndicator>
        public var now: Date

        public init(
            nowPlaying: NowPlaying? = nil,
            events: [CalendarEvent] = [],
            battery: BatteryStatus? = nil,
            timer: CountdownTimer? = nil,
            indicators: Set<CompactIndicator>,
            now: Date
        ) {
            self.nowPlaying = nowPlaying
            self.events = events
            self.battery = battery
            self.timer = timer
            self.indicators = indicators
            self.now = now
        }
    }

    public struct Output: Equatable, Sendable {
        public var content: CompactContent
        /// Evento que ocupa el indicador, si lo hay.
        public var shownEventID: CalendarEvent.ID?
        public var nextRefresh: Date?
    }

    public static func build(_ input: Input) -> Output {
        var content = CompactContent()
        var refreshDates: [Date] = []
        var shownEventID: CalendarEvent.ID?

        // La música va a la derecha; temporizador, evento y batería comparten
        // la izquierda, en ese orden de prioridad.
        if let timer = input.timer {
            switch timer.state {
            case .running(let end):
                content.leading = .init(
                    systemImage: "timer",
                    countdownEnd: end,
                    accessibilityLabel: String(localized: "Temporizador en marcha")
                )
                // Al vencer, el servicio cambia el estado y se recalcula.
            case .paused(let remaining):
                content.leading = .init(
                    systemImage: "pause.fill",
                    text: CountdownTimer.format(remaining),
                    accessibilityLabel: String(localized: "Temporizador en pausa")
                )
            case .finished(let at) where input.now < at + timerFinishedLinger:
                content.leading = .init(
                    systemImage: "bell.fill",
                    text: String(localized: "Listo"),
                    accessibilityLabel: String(localized: "El temporizador ha terminado")
                )
                refreshDates.append(at + timerFinishedLinger)
            case .idle, .finished:
                break
            }
        }

        if input.indicators.contains(.music), let track = input.nowPlaying, track.isPlaying {
            content.trailing = .init(
                systemImage: "waveform",
                accessibilityLabel: String(localized: "Reproduciendo \(track.title)")
            )
        }

        if input.indicators.contains(.nextEvent) {
            let timed = input.events.filter { !$0.isAllDay }
            let upcoming = timed.filter { $0.start > input.now }.min { $0.start < $1.start }
            let justStarted = timed
                .filter { $0.start <= input.now && input.now < min($0.start + eventLingerTime, $0.end) }
                .max { $0.start < $1.start }

            if let upcoming, content.leading == nil {
                let startsIn = upcoming.start.timeIntervalSince(input.now)
                if startsIn <= eventLeadTime {
                    let minutes = max(Int((startsIn / 60).rounded(.up)), 1)
                    content.leading = .init(
                        systemImage: "calendar",
                        text: String(localized: "\(minutes) min"),
                        accessibilityLabel: String(localized: "\(upcoming.title) empieza en \(minutes) minutos")
                    )
                    shownEventID = upcoming.id
                    // Volver cuando cambie el número de minutos mostrado.
                    refreshDates.append(upcoming.start - TimeInterval(minutes - 1) * 60)
                } else {
                    refreshDates.append(upcoming.start - eventLeadTime)
                }
            }
            if content.leading == nil, let justStarted {
                content.leading = .init(
                    systemImage: "calendar",
                    text: String(localized: "ahora"),
                    accessibilityLabel: String(localized: "\(justStarted.title) acaba de empezar")
                )
                shownEventID = justStarted.id
                refreshDates.append(min(justStarted.start + eventLingerTime, justStarted.end))
            }
        }

        if content.leading == nil, input.indicators.contains(.battery),
           let battery = input.battery, !battery.isPluggedIn, battery.level <= lowBatteryLevel {
            let percent = Int((battery.level * 100).rounded())
            content.leading = .init(
                systemImage: "battery.25",
                text: String(localized: "\(percent) %"),
                accessibilityLabel: String(localized: "Batería baja: \(percent) por ciento")
            )
        }

        let nextRefresh = refreshDates.filter { $0 > input.now }.min()
        return Output(content: content, shownEventID: shownEventID, nextRefresh: nextRefresh)
    }
}

/// Texto de cuenta atrás de un evento para las vistas.
public enum EventCountdown {
    public static func text(for phase: CalendarEvent.Phase) -> String {
        switch phase {
        case .ended:
            String(localized: "terminado")
        case .inProgress(let remaining):
            String(localized: "en curso · quedan \(duration(remaining))")
        case .upcoming(let startsIn) where startsIn < 60:
            String(localized: "empieza ahora")
        case .upcoming(let startsIn):
            String(localized: "en \(duration(startsIn))")
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded(.up)), 1)
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
        }
        let days = hours / 24
        return days == 1 ? String(localized: "1 día") : String(localized: "\(days) días")
    }
}
