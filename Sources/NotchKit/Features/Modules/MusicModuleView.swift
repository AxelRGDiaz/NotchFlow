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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    music.openPlayer()
                } label: {
                    artwork
                }
                .buttonStyle(.plain)
                .help("Abrir \(track.player.displayName)")
                .accessibilityLabel("Abrir \(track.player.displayName)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Text(track.player.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if track.isPlaying {
                // Único reloj periódico de la app: solo existe con el panel
                // abierto y la música sonando.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    PlaybackProgress(track: track, date: context.date)
                }
            } else {
                PlaybackProgress(track: track, date: track.positionDate)
            }

            HStack(spacing: 14) {
                PanelIconButton(systemImage: "backward.fill", label: "Anterior") { music.perform(.previous) }
                PanelIconButton(
                    systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                    label: track.isPlaying ? "Pausar" : "Reproducir",
                    size: 18
                ) {
                    music.perform(.playPause)
                }
                PanelIconButton(systemImage: "forward.fill", label: "Siguiente") { music.perform(.next) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let image = music.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(shape)
        } else {
            shape
                .fill(.white.opacity(0.1))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }
}

private struct PlaybackProgress: View {
    let track: NowPlaying
    let date: Date

    var body: some View {
        let position = track.position(at: date)
        VStack(spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * (track.progress(at: date) ?? 0))
                }
            }
            .frame(height: 3)

            HStack {
                Text(Self.time(position))
                Spacer()
                if let duration = track.duration {
                    Text(Self.time(duration))
                }
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso")
        .accessibilityValue(Self.time(position))
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let (hours, minutes, rest) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
