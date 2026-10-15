import AppKit
import EventKit
import Observation

/// Tareas pendientes de Recordatorios mediante EventKit: se sincronizan con
/// iCloud como en la app del sistema. Se recarga cuando el sistema avisa de cambios.
@MainActor
@Observable
final class RemindersService: ServiceLifecycle {
    private(set) var status: ServiceStatus = .idle
    private(set) var items: [ReminderItem] = []
    /// Texto de la tarea que se está escribiendo en el panel.
    var draft = ""

    /// Se sustituye al obtener acceso: un almacén creado antes de concederlo
    /// puede seguir devolviendo una lista vacía.
    @ObservationIgnored private var store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    func start() {
        guard observer == nil else { return }
        observeStore()
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        reloadTask?.cancel()
        items = []
        status = .idle
    }

    /// Muestra el aviso del sistema la primera vez; después solo relee el estado.
    func requestAccess() {
        let store = StoreBox(store)
        Task { [weak self] in
            await Self.requestFullAccess(store)
            self?.reload()
        }
    }

    func reload() {
        reloadTask?.cancel()
        let authorization = EKEventStore.authorizationStatus(for: .reminder)
        Log.reminders.info("Autorización: \(authorization.rawValue)")
        switch authorization {
        case .fullAccess:
            if status != .available { renewStore() }
            status = .available
        case .notDetermined:
            status = .needsPermission(.reminders)
            items = []
            return
        default:
            status = .denied(.reminders)
            items = []
            return
        }

        let store = StoreBox(store)
        reloadTask = Task { [weak self] in
            let loaded = await Self.fetchPending(from: store.value)
            guard !Task.isCancelled else { return }
            Log.reminders.info("Tareas pendientes cargadas: \(loaded.count)")
            self?.items = ReminderItem.sorted(loaded)
        }
    }

    private func observeStore() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func renewStore() {
        store = EKEventStore()
        if observer != nil { observeStore() }
    }

    /// Crea la tarea escrita en `draft` en la lista predeterminada.
    func addDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, status == .available else { return }
        guard let list = store.defaultCalendarForNewReminders() else {
            Log.reminders.error("No hay una lista predeterminada de recordatorios")
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
            draft = ""
            reload()
        } catch {
            Log.reminders.error("No se pudo crear la tarea: \(error.localizedDescription, privacy: .public)")
        }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        // Desaparece al instante; la recarga confirma el cambio.
        items.removeAll { $0.id == item.id }
        do {
            try store.save(reminder, commit: true)
        } catch {
            Log.reminders.error("No se pudo completar la tarea: \(error.localizedDescription, privacy: .public)")
            reload()
        }
    }

    func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// EventKit responde en un hilo propio: ver `CalendarService.requestFullAccess`.
    nonisolated private static func requestFullAccess(_ store: StoreBox) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.value.requestFullAccessToReminders { @Sendable _, error in
                if let error {
                    Log.reminders.error("Fallo al solicitar acceso: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    nonisolated private static func fetchPending(from store: EKEventStore) async -> [ReminderItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                let items = (reminders ?? []).map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        dueDate: reminder.dueDateComponents?.date,
                        listTitle: reminder.calendar?.title
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// `EKEventStore` admite uso desde varios hilos pero no está marcado como `Sendable`.
    private struct StoreBox: @unchecked Sendable {
        let value: EKEventStore
        init(_ value: EKEventStore) { self.value = value }
    }
}
