@preconcurrency import AVFoundation
import Observation

/// Espejo de la cámara. Nunca se enciende sola: el usuario la activa desde el
/// panel y se apaga al cerrarlo, de modo que la luz verde solo está encendida
/// mientras se ve la imagen.
@MainActor
@Observable
final class CameraService: ServiceLifecycle {
    private(set) var status: ServiceStatus = .idle
    private(set) var isOn = false

    /// La sesión se configura y arranca en su propia cola: `startRunning`
    /// bloquea y no debe ejecutarse en el hilo principal.
    @ObservationIgnored let session = AVCaptureSession()
    /// Una sola capa para toda la vida de la app, conectada a la sesión al
    /// configurarla y antes de arrancarla. Conectarla desde el hilo principal
    /// mientras `startRunning` corre en su cola modifica las conexiones de la
    /// sesión a la vez que esta las recorre, y AVFoundation aborta la app.
    @ObservationIgnored let previewLayer = AVCaptureVideoPreviewLayer()
    @ObservationIgnored private let queue = DispatchQueue(label: "NotchFlow.camera")
    @ObservationIgnored private var isConfigured = false

    func start() {
        refreshStatus()
    }

    func stop() {
        turnOff()
        status = .idle
    }

    func turnOn() {
        guard !isOn else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            Task { [weak self] in
                _ = await AVCaptureDevice.requestAccess(for: .video)
                self?.refreshStatus()
                if self?.status == .available { self?.run() }
            }
        default:
            status = .denied(.camera)
        }
    }

    func turnOff() {
        guard isOn else { return }
        isOn = false
        let session = SessionBox(session)
        queue.async { session.value.stopRunning() }
    }

    private func refreshStatus() {
        status = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .available
        case .notDetermined: .needsPermission(.camera)
        default: .denied(.camera)
        }
    }

    private func run() {
        status = .available
        if !isConfigured {
            guard configure() else { return }
        }
        isOn = true
        let session = SessionBox(session)
        queue.async { session.value.startRunning() }
    }

    private func configure() -> Bool {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            status = .unsupported(reason: String(localized: "No se encontró ninguna cámara."))
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .medium
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.session = session
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                // En espejo, como en FaceTime.
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            isConfigured = true
            return true
        } catch {
            Log.camera.error("No se pudo abrir la cámara: \(error.localizedDescription, privacy: .public)")
            status = .failed(message: String(localized: "No se pudo abrir la cámara."))
            return false
        }
    }

    private struct SessionBox: @unchecked Sendable {
        let value: AVCaptureSession
        init(_ value: AVCaptureSession) { self.value = value }
    }
}
