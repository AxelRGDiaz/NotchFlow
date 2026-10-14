import AppKit
import EventKit
import Observation

/// Eventos del calendario del usuario mediante EventKit: desde el inicio de
/// hoy hasta varios días después. Se recarga cuando el sistema avisa de cambios.
@MainActor
@Observable
final class CalendarService: ServiceLifecycle {
    nonisolated static let lookAheadDays = 7

    private(set) var status: ServiceStatus = .idle
    private(set) var events: [CalendarEvent] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for (name, object) in [(Notification.Name.EKEventStoreChanged, store as AnyObject?), (.NSCalendarDayChanged, nil)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        reload()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        reloadTask?.cancel()
        events = []
        status = .idle
    }

    /// Muestra el aviso del sistema la primera vez; después solo relee el estado.
    func requestAccess() {
        let store = StoreBox(store)
        Task { [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.value.requestFullAccessToEvents { _, error in
                    if let error {
                        Log.calendar.error("Fallo al solicitar acceso: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume()
                }
            }
            self?.reload()
        }
    }

    func reload() {
        reloadTask?.cancel()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            status = .available
        case .notDetermined:
            status = .needsPermission(.calendar)
            events = []
            return
        default:
            // Denegado, restringido o solo escritura: no se pueden leer eventos.
            status = .denied(.calendar)
            events = []
            return
        }

        let store = StoreBox(store)
        reloadTask = Task { [weak self] in
            // La consulta de EventKit es síncrona; se hace fuera del hilo principal.
            let loaded = await Task.detached { Self.fetchEvents(from: store.value, now: .now) }.value
            guard !Task.isCancelled else { return }
            self?.events = loaded
        }
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    nonisolated private static func fetchEvents(from store: EKEventStore, now: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: lookAheadDays, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                CalendarEvent(
                    // Las repeticiones de un evento comparten identificador.
                    id: "\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSinceReferenceDate)",
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                    calendarTitle: event.calendar?.title,
                    calendarColor: event.calendar?.color.usingColorSpace(.sRGB).map {
                        [Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)]
                    }
                )
            }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// `EKEventStore` admite uso desde varios hilos pero no está marcado como `Sendable`.
    private struct StoreBox: @unchecked Sendable {
        let value: EKEventStore
        init(_ value: EKEventStore) { self.value = value }
    }
}
