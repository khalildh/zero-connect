import AVFoundation
import SwiftUI
import ZeroConnectCore

struct ScannerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var addedContact: Contact?

    var body: some View {
        NavigationStack {
            ZStack {
                #if os(iOS)
                QRScannerRepresentable { code in
                    handleScannedCode(code)
                }
                .ignoresSafeArea()
                #else
                Text("Camera scanning is only available on iOS")
                    .foregroundStyle(.secondary)
                #endif

                VStack {
                    Spacer()

                    if let contact = addedContact {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)
                            Text("Added \(contact.displayName)")
                                .font(.headline)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding()
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    } else {
                        Text("Point camera at a QR code")
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        guard scannedCode == nil else { return } // Prevent double scans
        scannedCode = code

        do {
            try appState.addContact(from: code)
            let qrIdentity = try QRCodeIdentity.decode(from: code)
            addedContact = qrIdentity.toContact()

            // Auto-dismiss after a brief delay
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { dismiss() }
            }
        } catch {
            errorMessage = "Invalid QR code"
            scannedCode = nil // Allow retry
        }
    }
}

// MARK: - Camera QR Scanner (iOS only)

#if os(iOS)
struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }

        captureSession.stopRunning()
        onCodeScanned?(value)
    }
}
#endif
