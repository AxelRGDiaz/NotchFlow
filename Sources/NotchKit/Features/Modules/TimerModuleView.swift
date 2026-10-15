import SwiftUI

struct TimerModuleView: View {
    let timer: TimerService

    var body: some View {
        ModuleCard(module: .timer) {
            HStack(spacing: 26) {
                if timer.timer.isRunning {
                    // Reloj solo con el panel abierto y el temporizador en marcha.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        dial(now: context.date)
                    }
                } else {
                    dial(now: .now)
                }
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dial(now: Date) -> some View {
        let state = timer.timer.state
        let finished = if case .finished = state { true } else { false }
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: 1 - timer.timer.progress(at: now))
                .stroke(finished ? Color.orange : Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer.timer.progress(at: now))
            VStack(spacing: 2) {
                Text(finished ? String(localized: "¡Listo!") : CountdownTimer.format(timer.timer.remaining(at: now)))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text(Self.caption(state))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        let running = timer.timer.isRunning
        let editable = !running && !Self.isPaused(timer.timer.state)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 3), spacing: 6) {
                ForEach(TimerService.presets, id: \.self) { minutes in
                    let selected = Int((timer.timer.duration / 60).rounded()) == minutes
                    Button {
                        timer.setMinutes(minutes)
                    } label: {
                        Text("\(minutes) min")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 58, height: 30)
                            .foregroundStyle(selected && editable ? Color.black : Color.white)
                            .background(selected && editable ? Color.white : Color.white.opacity(0.1), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!editable)
                }
            }
            .opacity(editable ? 1 : 0.45)

            HStack(spacing: 14) {
                PanelIconButton(systemImage: "minus", label: "Un minuto menos", size: 13) { timer.adjust(byMinutes: -1) }
                    .disabled(!editable)
                PanelIconButton(systemImage: "plus", label: "Un minuto más", size: 13) { timer.adjust(byMinutes: 1) }
                    .disabled(!editable)
                Spacer(minLength: 8)
                PanelIconButton(systemImage: "arrow.counterclockwise", label: "Reiniciar", size: 14) { timer.reset() }
                Button {
                    timer.toggle()
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(running ? "Pausar" : "Empezar")
                .accessibilityLabel(running ? "Pausar" : "Empezar")
            }
        }
        .frame(width: 186)
    }

    private static func isPaused(_ state: CountdownTimer.State) -> Bool {
        if case .paused = state { return true }
        return false
    }

    private static func caption(_ state: CountdownTimer.State) -> String {
        switch state {
        case .idle: String(localized: "listo para empezar")
        case .running(let end): String(localized: "termina a las \(end.formatted(date: .omitted, time: .shortened))")
        case .paused: String(localized: "en pausa")
        case .finished: String(localized: "tiempo cumplido")
        }
    }
}
