import AppKit
import Observation

/// Temporizador del panel. Sigue contando con el panel cerrado; al terminar
/// hace sonar una alarma y lo anota en la actividad. Solo hay una tarea de un disparo
/// programada para el final, nunca un reloj periódico.
@MainActor
@Observable
final class TimerService {
    nonisolated static let durationKey = "timer.duration"
    /// Duraciones rápidas, en minutos.
    nonisolated static let presets: [Int] = [1, 5, 10, 15, 25, 45]

    private(set) var timer: CountdownTimer
    /// Se invoca al terminar, para anotarlo en la actividad.
    @ObservationIgnored var onFinish: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private let alarm = AlarmPlayer()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.durationKey)
        timer = CountdownTimer(duration: saved > 0 ? saved : 5 * 60)
    }

    func setMinutes(_ minutes: Int) {
        guard !timer.isRunning else { return }
        stopAlarm()
        timer.setDuration(TimeInterval(minutes) * 60)
        defaults.set(timer.duration, forKey: Self.durationKey)
    }

    /// Suma o resta minutos a la duración elegida (solo parado).
    func adjust(byMinutes delta: Int) {
        let minutes = Int((timer.duration / 60).rounded()) + delta
        setMinutes(max(minutes, 1))
    }

    func toggle() {
        stopAlarm()
        if timer.isRunning {
            timer.pause(now: .now)
            finishTask?.cancel()
        } else {
            timer.start(now: .now)
            scheduleFinish()
        }
    }

    func reset() {
        stopAlarm()
        finishTask?.cancel()
        timer.reset()
    }

    func stopAlarm() {
        alarm.stop()
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        guard case .running(let end) = timer.state else { return }
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            if self.timer.finishIfDue(now: .now) {
                self.alarm.play(maxDuration: CompactContentBuilder.timerFinishedLinger)
                self.onFinish?()
            } else {
                // El reloj del sistema pudo cambiar; se vuelve a programar.
                self.scheduleFinish()
            }
        }
    }
}
