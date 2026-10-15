import AVFoundation
import SwiftUI

struct CameraModuleView: View {
    let camera: CameraService

    var body: some View {
        ModuleCard(module: .camera) {
            switch camera.status {
            case .available, .needsPermission, .idle:
                if camera.isOn {
                    CameraPreview(layer: camera.previewLayer)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            PanelIconButton(systemImage: "video.slash.fill", label: "Apagar la cámara", size: 11) {
                                camera.turnOff()
                            }
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                        }
                        .accessibilityLabel("Vista de la cámara")
                        .frame(maxWidth: .infinity)
                } else {
                    ModuleMessage(
                        text: "Mírate antes de una videollamada. La cámara se apaga sola al cerrar el panel.",
                        actionTitle: "Encender"
                    ) {
                        camera.turnOn()
                    }
                }
            case .denied:
                ModuleMessage(
                    text: "El acceso a la cámara está denegado. Actívalo en Ajustes del Sistema > Privacidad y seguridad > Cámara.",
                    actionTitle: "Abrir Ajustes"
                ) {
                    SystemSettings.cameraPrivacy.open()
                }
            case .failed(let message), .unsupported(let message):
                ModuleMessage(text: LocalizedStringKey(message))
            }
        }
    }
}

/// Muestra la capa de vista previa del servicio. No la crea ni la conecta a
/// la sesión: eso ocurre una sola vez en `CameraService`.
private struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(previewLayer: layer)
    }

    func updateNSView(_ view: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            wantsLayer = true
            // Una capa solo tiene un padre: añadirla aquí la saca de una vista anterior.
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
