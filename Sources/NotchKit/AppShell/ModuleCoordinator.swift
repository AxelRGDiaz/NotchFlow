import Foundation
import Observation

/// Posee los servicios de los módulos. Arranca solo los que hacen falta según
/// la configuración, deriva de ellos el contenido compacto y anota la actividad.
@MainActor
final class ModuleCoordinator {
    let store: PreferencesStore
    let model: NotchViewModel
    let music: MusicService
    let calendar = CalendarService()
    let apps: ApplicationService
    let battery = BatteryService()
    let audio = AudioService()
    let wifi = WiFiService()
    let activity = ActivityService()

    private enum ServiceKey: CaseIterable {
        case music, calendar, apps, battery, audio, wifi
    }

    private struct Snapshot {
        var visible: Set<ModuleID>
        var indicators: Set<CompactIndicator>
        var nowPlaying: NowPlaying?
        var events: [CalendarEvent]
        var battery: BatteryStatus?
        var isExpanded: Bool
    }

    private var isStarted = false
    private var running: Set<ServiceKey> = []
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private var wasExpanded = false

    private var lastTrackKey: String?
    private var lastPluggedIn: Bool?
    private var lowBatteryReported = false
    private var announcedEventIDs: Set<CalendarEvent.ID> = []

    init(store: PreferencesStore, model: NotchViewModel) {
        self.store = store
        self.model = model
        // MediaRemote primero (cualquier reproductor); Apple Music como respaldo.
        let systemAdapter: [any MusicPlayerAdapter] = SystemNowPlayingAdapter().map { [$0] } ?? []
        music = MusicService(adapters: systemAdapter + [AppleMusicAdapter(runner: AppleScriptRunner())])
        apps = ApplicationService(store: store)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        refreshTask?.cancel()
        ServiceKey.allCases.forEach { setRunning($0, false) }
        model.setCompactContent(CompactContent())
    }

    /// Tras reactivar el equipo pueden haberse perdido avisos del sistema.
    func refreshAfterWake() {
        if running.contains(.music) { music.refresh() }
        if running.contains(.calendar) { calendar.reload() }
        if running.contains(.battery) { battery.refresh() }
        if running.contains(.wifi) { wifi.refresh() }
    }

    // MARK: - Observación

    /// Lee lo necesario dentro del seguimiento y aplica los cambios fuera, para
    /// no registrar como dependencias las propiedades que aquí se modifican.
    private func observe() {
        generation += 1
        let current = generation
        let snapshot = withObservationTracking {
            Snapshot(
                visible: Set(store.preferences.visibleModules),
                indicators: store.preferences.compactIndicators,
                nowPlaying: music.nowPlaying,
                events: calendar.events,
                battery: battery.status,
                isExpanded: model.state.isExpanded
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                // Un seguimiento antiguo no debe abrir una segunda cadena.
                guard let self, self.isStarted, self.generation == current else { return }
                self.observe()
            }
        }
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        let visible = snapshot.visible
        let indicators = snapshot.indicators
        setRunning(.music, visible.contains(.music) || indicators.contains(.music))
        setRunning(.calendar, visible.contains(.calendar) || indicators.contains(.nextEvent))
        setRunning(.apps, visible.contains(.apps))
        setRunning(.battery, visible.contains(.quickControls) || visible.contains(.activity) || indicators.contains(.battery))
        setRunning(.audio, visible.contains(.quickControls))
        setRunning(.wifi, visible.contains(.quickControls))

        // Al abrir el panel se actualiza la posición de la pista y se relee el
        // permiso del calendario, que el usuario puede haber cambiado en Ajustes.
        if snapshot.isExpanded, !wasExpanded {
            if running.contains(.music) { music.refresh() }
            if running.contains(.calendar), calendar.status != .available { calendar.reload() }
        }
        wasExpanded = snapshot.isExpanded

        let now = Date.now
        let output = CompactContentBuilder.build(.init(
            nowPlaying: snapshot.nowPlaying,
            events: snapshot.events,
            battery: snapshot.battery,
            indicators: indicators,
            now: now
        ))
        model.setCompactContent(output.content)
        recordActivity(snapshot, shownEventID: output.shownEventID, now: now)
        scheduleRefresh(at: output.nextRefresh, now: now)
    }

    private func scheduleRefresh(at date: Date?, now: Date) {
        refreshTask?.cancel()
        guard let date else { return }
        let delay = max(date.timeIntervalSince(now), 1)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isStarted else { return }
            self.observe()
        }
    }

    private func setRunning(_ key: ServiceKey, _ shouldRun: Bool) {
        guard shouldRun != running.contains(key) else { return }
        let service: any ServiceLifecycle = switch key {
        case .music: music
        case .calendar: calendar
        case .apps: apps
        case .battery: battery
        case .audio: audio
        case .wifi: wifi
        }
        if shouldRun {
            running.insert(key)
            service.start()
        } else {
            running.remove(key)
            service.stop()
        }
    }

    // MARK: - Actividad

    private func recordActivity(_ snapshot: Snapshot, shownEventID: CalendarEvent.ID?, now: Date) {
        if let track = snapshot.nowPlaying, track.isPlaying {
            let key = track.trackID ?? "\(track.title)|\(track.artist ?? "")"
            if key != lastTrackKey {
                lastTrackKey = key
                activity.record(.trackChanged, title: track.title, detail: track.artist, date: now)
            }
        }

        if let battery = snapshot.battery {
            let percent = String(localized: "\(Int((battery.level * 100).rounded())) %")
            if let lastPluggedIn, lastPluggedIn != battery.isPluggedIn {
                let title = battery.isPluggedIn
                    ? String(localized: "Cargador conectado")
                    : String(localized: "Cargador desconectado")
                activity.record(.chargingChanged, title: title, detail: percent, date: now)
            }
            lastPluggedIn = battery.isPluggedIn

            let isLow = !battery.isPluggedIn && battery.level <= CompactContentBuilder.lowBatteryLevel
            if isLow, !lowBatteryReported {
                activity.record(.batteryLow, title: String(localized: "Batería baja"), detail: percent, date: now)
            }
            lowBatteryReported = isLow
        }

        if let shownEventID, !announcedEventIDs.contains(shownEventID),
           let event = snapshot.events.first(where: { $0.id == shownEventID }) {
            announcedEventIDs.insert(shownEventID)
            activity.record(.eventSoon, title: event.title, detail: EventCountdown.text(for: event.phase(at: now)), date: now)
        }
    }
}
