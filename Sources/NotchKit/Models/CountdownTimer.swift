import Foundation

/// Temporizador de cuenta atrás. Guarda instantes, no un contador: no
/// necesita ningún reloj para avanzar y el tiempo restante se calcula al leerlo.
public struct CountdownTimer: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Listo para empezar con `duration`.
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }

    public static let durationRange: ClosedRange<TimeInterval> = 60...(24 * 3600)

    /// Duración elegida; se conserva al reiniciar.
    public private(set) var duration: TimeInterval
    public private(set) var state: State = .idle

    public init(duration: TimeInterval = 5 * 60) {
        self.duration = duration.clamped(to: Self.durationRange)
    }

    /// Solo se cambia con el temporizador parado: vuelve a `idle` con la nueva duración.
    public mutating func setDuration(_ value: TimeInterval) {
        duration = value.clamped(to: Self.durationRange)
        state = .idle
    }

    public mutating func start(now: Date) {
        switch state {
        case .idle, .finished:
            state = .running(end: now + duration)
        case .paused(let remaining):
            state = .running(end: now + remaining)
        case .running:
            break
        }
    }

    public mutating func pause(now: Date) {
        guard case .running(let end) = state else { return }
        state = .paused(remaining: max(end.timeIntervalSince(now), 0))
    }

    public mutating func reset() {
        state = .idle
    }

    /// Pasa a `finished` si ya venció. Devuelve `true` si acaba de terminar.
    public mutating func finishIfDue(now: Date) -> Bool {
        guard case .running(let end) = state, end <= now else { return false }
        state = .finished(at: end)
        return true
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: duration
        case .running(let end): max(end.timeIntervalSince(now), 0)
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    /// Fracción consumida, de 0 a 1.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining(at: now) / duration, 0), 1)
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Texto "m:ss" o "h:mm:ss".
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (hours, minutes, rest) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
