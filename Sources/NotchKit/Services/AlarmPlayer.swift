import AppKit
@preconcurrency import AVFoundation

/// Alarma del temporizador: ráfagas de cuatro pitidos que se repiten, para que
/// no se confunda con el sonido de una notificación. Se genera aquí mismo
/// (sin archivos de audio) y se detiene sola tras `maxDuration`.
@MainActor
final class AlarmPlayer {
    private var engine: AVAudioEngine?
    private var stopTask: Task<Void, Never>?

    var isPlaying: Bool { engine != nil }

    func play(maxDuration: TimeInterval) {
        stop()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = Self.pattern(format: format) else { return }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            Log.app.error("No se pudo reproducir la alarma: \(error.localizedDescription, privacy: .public)")
            NSSound(named: "Sosumi")?.play()
            return
        }
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        self.engine = engine
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(maxDuration))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        engine?.stop()
        engine = nil
    }

    /// Un ciclo: cuatro pitidos cortos alternando dos notas y una pausa.
    private static func pattern(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let beep = 0.11, gap = 0.06, rest = 0.55
        let notes: [Double] = [1318.5, 1046.5, 1318.5, 1046.5]   // Mi6 y Do6
        let cycle = Double(notes.count) * (beep + gap) + rest
        let frames = AVAudioFrameCount(cycle * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { samples[i] = 0 }

        let beepFrames = Int(beep * rate)
        let fade = Int(0.005 * rate)   // evita chasquidos al empezar y acabar
        for (index, frequency) in notes.enumerated() {
            let start = Int(Double(index) * (beep + gap) * rate)
            for n in 0..<beepFrames {
                let t = Double(n) / rate
                let envelope = min(Double(n) / Double(fade), Double(beepFrames - n) / Double(fade), 1)
                // Seno con algo de tercer armónico: más timbre de despertador.
                let wave = sin(2 * .pi * frequency * t) + 0.3 * sin(2 * .pi * 3 * frequency * t)
                samples[start + n] = Float(0.32 * envelope * wave)
            }
        }
        return buffer
    }
}
