import SwiftUI

struct RemindersModuleView: View {
    @Bindable var reminders: RemindersService

    var body: some View {
        ModuleCard(module: .reminders) {
            switch reminders.status {
            case .available:
                list
            case .needsPermission:
                ModuleMessage(
                    text: "Para ver y añadir tareas hace falta acceso a Recordatorios. Se sincronizan con tu iPhone por iCloud.",
                    actionTitle: "Permitir acceso"
                ) {
                    reminders.requestAccess()
                }
            case .denied:
                ModuleMessage(
                    text: "El acceso a Recordatorios está denegado. Actívalo en Ajustes del Sistema > Privacidad y seguridad > Recordatorios.",
                    actionTitle: "Abrir Ajustes"
                ) {
                    SystemSettings.remindersPrivacy.open()
                }
            case .failed(let message), .unsupported(let message):
                ModuleMessage(text: LocalizedStringKey(message))
            case .idle:
                EmptyView()
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Nueva tarea", text: $reminders.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { reminders.addDraft() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if reminders.items.isEmpty {
                Text("No tienes tareas pendientes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reminders.items) { item in
                            row(item)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                reminders.complete(item)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Completar")
            .accessibilityLabel("Completar \(item.title)")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                if let due = item.dueDate {
                    Text(due, format: .relative(presentation: .named))
                        .font(.system(size: 10))
                        .foregroundStyle(due < .now ? .red.opacity(0.85) : .white.opacity(0.5))
                }
            }
        }
        .contextMenu {
            Button("Abrir Recordatorios") { reminders.openRemindersApp() }
        }
    }
}
