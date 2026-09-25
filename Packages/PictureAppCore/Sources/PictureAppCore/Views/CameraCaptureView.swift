import SwiftUI

#if os(iOS)
import UIKit

/// Kamerafångst på iOS - `UIImagePickerController` är fortfarande den enda
/// vägen till kamera-UI från SwiftUI (ingen ren SwiftUI-kamera-API finns än).
struct CameraCaptureView: View {
    let onCapture: (PlatformImage) -> Void
    let onCancel: () -> Void

    var body: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            CameraRepresentable(onCapture: onCapture, onCancel: onCancel)
                .ignoresSafeArea()
        } else {
            VStack(spacing: 16) {
                Text("Ingen kamera hittades på den här enheten.")
                    .multilineTextAlignment(.center)
                Button("Stäng") { onCancel() }
            }
            .padding(24)
        }
    }
}

private struct CameraRepresentable: UIViewControllerRepresentable {
    let onCapture: (PlatformImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (PlatformImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (PlatformImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image.normalizedOrientation())
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

#elseif os(macOS)
import AVFoundation
import AppKit

/// Kamerafångst på Mac via AVFoundation - det finns ingen färdig
/// "ta en bild"-panel i AppKit motsvarande UIImagePickerController, så en
/// minimal egen fånga-en-stillbild-vy byggs här: en förhandsvisning plus en
/// avtryckarknapp.
struct CameraCaptureView: View {
    let onCapture: (PlatformImage) -> Void
    let onCancel: () -> Void

    @StateObject private var model = MacCameraModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Ta en bild")
                .font(.headline)

            ZStack {
                Color.black
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    CameraPreviewRepresentable(session: model.session)
                }
            }
            .frame(width: 480, height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Avbryt", role: .cancel) {
                    model.stop()
                    onCancel()
                }
                Spacer()
                Button {
                    model.capturePhoto { image in
                        model.stop()
                        if let image {
                            onCapture(image)
                        }
                    }
                } label: {
                    Label("Ta bild", systemImage: "camera.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.errorMessage != nil)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 440)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class MacCameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    @Published var errorMessage: String?
    private var captureCompletion: ((PlatformImage?) -> Void)?

    func start() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                errorMessage = "PictureApp saknar behörighet att använda kameran. Godkänn i Systeminställningar > Sekretess och säkerhet > Kamera."
                return
            }
            configureSessionIfNeeded()
            guard errorMessage == nil else { return }
            let session = session
            Task.detached(priority: .userInitiated) {
                session.startRunning()
            }
        }
    }

    func stop() {
        session.stopRunning()
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            errorMessage = "Hittade ingen kamera."
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            errorMessage = "Kunde inte konfigurera kameran."
            return
        }
        session.addOutput(photoOutput)
    }

    func capturePhoto(completion: @escaping (PlatformImage?) -> Void) {
        captureCompletion = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension MacCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { PlatformImage.normalizedOrientation(from: $0) }
        Task { @MainActor in
            self.captureCompletion?(image)
            self.captureCompletion = nil
        }
    }
}

/// Värdvy för `AVCaptureVideoPreviewLayer` - AppKit har ingen SwiftUI-native
/// motsvarighet, så ett tunt `NSViewRepresentable`-lager krävs.
private struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
            previewLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
#endif
