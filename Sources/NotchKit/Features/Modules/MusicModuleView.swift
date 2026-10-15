import SwiftUI

struct MusicModuleView: View {
    let music: MusicService

    var body: some View {
        ModuleCard(module: .music) {
            switch music.status {
            case .available:
                if let track = music.nowPlaying {
                    player(track)
                } else {
                    ModuleMessage(text: "No se está reproduciendo nada.", actionTitle: "Abrir Música") {
                        music.openPlayer()
                    }
                }
            case .needsPermission:
                ModuleMessage(
                    text: "Para mostrar y controlar lo que suena hace falta tu permiso para comunicarse con \(playerName).",
                    actionTitle: "Permitir"
                ) {
                    music.requestPermission()
                }
            case .denied:
                ModuleMessage(
                    text: "El permiso para controlar \(playerName) está denegado. Actívalo en Ajustes del Sistema > Privacidad y seguridad > Automatización.",
                    actionTitle: "Abrir Ajustes"
                ) {
                    SystemSettings.automationPrivacy.open()
                }
            case .failed(let message):
                ModuleMessage(text: LocalizedStringKey(message), actionTitle: "Reintentar") {
                    music.refresh()
                }
            case .unsupported(let reason):
                ModuleMessage(text: LocalizedStringKey(reason))
            case .idle:
                ModuleMessage(text: "No se está reproduciendo nada.", actionTitle: "Abrir Música") {
                    music.openPlayer()
                }
            }
        }
    }

    private var playerName: String {
        music.activePlayer?.displayName ?? music.defaultPlayer.displayName
    }

    private func player(_ track: NowPlaying) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Button {
                music.openPlayer()
            } label: {
                artwork
            }
            .buttonStyle(.plain)
            .help("Abrir \(track.player.displayName)")
            .accessibilityLabel("Abrir \(track.player.displayName)")

            VStack(alignment: .leading, spacing: 3) {
                Text(track.player.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(track.title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)
                if let subtitle = Self.subtitle(track) {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if track.isPlaying {
                    // Único reloj periódico de la app: solo existe con el panel
                    // abierto y la música sonando.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        PlaybackProgress(track: track, date: context.date) { music.perform(.seek(to: $0)) }
                    }
                } else {
                    PlaybackProgress(track: track, date: track.positionDate) { music.perform(.seek(to: $0)) }
                }

                HStack(spacing: 26) {
                    PanelIconButton(systemImage: "backward.fill", label: "Anterior", size: 15) { music.perform(.previous) }
                    Button {
                        music.perform(.playPause)
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(track.isPlaying ? "Pausar" : "Reproducir")
                    .accessibilityLabel(track.isPlaying ? "Pausar" : "Reproducir")
                    PanelIconButton(systemImage: "forward.fill", label: "Siguiente", size: 15) { music.perform(.next) }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private static func subtitle(_ track: NowPlaying) -> String? {
        let parts = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Cuadrada y tan alta como el módulo.
    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            if let image = music.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                shape
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .frame(maxWidth: 190, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }
}

/// Barra de progreso. Si se conoce la duración, se arrastra o se toca para
/// saltar a otra posición; la orden se envía al soltar.
private struct PlaybackProgress: View {
    let track: NowPlaying
    let date: Date
    let onSeek: (TimeInterval) -> Void
    /// Fracción bajo el dedo mientras se arrastra.
    @GestureState private var dragFraction: Double?

    var body: some View {
        let duration = track.duration
        let fraction = dragFraction ?? track.progress(at: date) ?? 0
        let position = dragFraction.flatMap { f in duration.map { f * $0 } } ?? track.position(at: date)
        VStack(spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                        .frame(height: dragFraction == nil ? 5 : 7)
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * fraction, height: dragFraction == nil ? 5 : 7)
                    if duration != nil {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: proxy.size.width * fraction - 6)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(seekGesture(width: proxy.size.width, duration: duration))
                .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
            }
            .frame(height: 14)

            HStack {
                Text(Self.time(position))
                Spacer()
                if let duration {
                    Text("-" + Self.time(duration - position))
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso")
        .accessibilityValue(Self.time(position))
        .accessibilityAdjustableAction { direction in
            guard let duration else { return }
            let step: TimeInterval = direction == .increment ? 10 : -10
            onSeek(min(max(track.position(at: .now) + step, 0), duration))
        }
    }

    private func seekGesture(width: CGFloat, duration: TimeInterval?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragFraction) { value, state, _ in
                guard duration != nil, width > 0 else { return }
                state = Self.fraction(value.location.x, width: width)
            }
            .onEnded { value in
                guard let duration, width > 0 else { return }
                onSeek(Self.fraction(value.location.x, width: width) * duration)
            }
    }

    private static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        min(max(x / width, 0), 1)
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let (hours, minutes, rest) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
