import SwiftUI

struct CalendarModuleView: View {
    let calendar: CalendarService

    var body: some View {
        ModuleCard(module: .calendar) {
            switch calendar.status {
            case .available:
                // Refresca la cuenta atrás cada minuto, solo con el panel abierto.
                TimelineView(.everyMinute) { context in
                    agenda(now: context.date)
                }
            case .needsPermission:
                ModuleMessage(
                    text: "Para mostrar tus próximos eventos hace falta acceso a tus calendarios. Los datos no salen de tu Mac.",
                    actionTitle: "Permitir acceso"
                ) {
                    calendar.requestAccess()
                }
            case .denied:
                ModuleMessage(
                    text: "El acceso al calendario está denegado. Actívalo en Ajustes del Sistema > Privacidad y seguridad > Calendarios, con acceso completo.",
                    actionTitle: "Abrir Ajustes"
                ) {
                    SystemSettings.calendarPrivacy.open()
                }
            case .failed(let message), .unsupported(let message):
                ModuleMessage(text: LocalizedStringKey(message))
            case .idle:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func agenda(now: Date) -> some View {
        let pending = calendar.events.filter { $0.end > now }
        let next = EventTimeline.currentOrNext(in: pending, at: now)
        let rest = pending.filter { $0.id != next?.id }

        if pending.isEmpty {
            ModuleMessage(text: "No hay eventos en los próximos \(CalendarService.lookAheadDays) días.", actionTitle: "Abrir Calendario") {
                calendar.openCalendarApp()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let next {
                    Button {
                        calendar.openCalendarApp()
                    } label: {
                        NextEventView(event: next, now: now)
                    }
                    .buttonStyle(.plain)
                    .help("Abrir Calendario")
                }
                if !rest.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(rest) { event in
                                EventRow(event: event, now: now)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct NextEventView: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CalendarColorBar(components: event.calendarColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? String(localized: "Sin título") : event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(EventCountdown.text(for: event.phase(at: now)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(EventFormat.when(event, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            CalendarColorBar(components: event.calendarColor)
            Text(EventFormat.when(event, now: now))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .layoutPriority(1)
            Text(event.title.isEmpty ? String(localized: "Sin título") : event.title)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarColorBar: View {
    let components: [Double]?

    var body: some View {
        let color = components.flatMap { $0.count == 3 ? Color(red: $0[0], green: $0[1], blue: $0[2]) : nil }
        Capsule()
            .fill(color ?? .white.opacity(0.4))
            .frame(width: 3)
            .frame(minHeight: 12)
            .accessibilityHidden(true)
    }
}

enum EventFormat {
    /// "10:30–11:00" para hoy; con el día delante para el resto.
    static func when(_ event: CalendarEvent, now: Date, calendar: Calendar = .current) -> String {
        let day: String? = if calendar.isDate(event.start, inSameDayAs: now) || event.start < now {
            nil
        } else if calendar.isDateInTomorrow(event.start) {
            String(localized: "mañana")
        } else {
            event.start.formatted(.dateTime.weekday(.abbreviated).day())
        }
        let time = event.isAllDay
            ? String(localized: "todo el día")
            : "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
        return [day, time].compactMap { $0 }.joined(separator: " · ")
    }
}
