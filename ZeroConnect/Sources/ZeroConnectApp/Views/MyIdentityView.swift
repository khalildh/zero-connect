import CoreImage.CIFilterBuiltins
import SwiftUI
import ZeroConnectCore

struct MyIdentityView: View {
    @EnvironmentObject var appState: AppState
    @State private var qrString: String?
    @State private var publicKeyHex: String?
    @State private var deviceName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // QR Code
                    if let qrString {
                        qrCodeImage(for: qrString)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 4)
                    } else {
                        ProgressView()
                            .frame(width: 240, height: 240)
                    }

                    Text("Show this to add you as a contact")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    // Public key
                    if let hex = publicKeyHex {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Public Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(hex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Transport status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transports")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TransportStatusRow(
                            icon: "wifi",
                            name: "Loom (Wi-Fi / AWDL)",
                            status: "Active",
                            color: .green
                        )
                        TransportStatusRow(
                            icon: "wave.3.right",
                            name: "Meshtastic (LoRa)",
                            status: appState.nearbyPeers.contains(where: { $0.transport == .meshtastic })
                                ? "Connected" : "Scanning...",
                            color: appState.nearbyPeers.contains(where: { $0.transport == .meshtastic })
                                ? .green : .orange
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("My Identity")
            .task {
                do {
                    qrString = try await appState.myQRString()
                    publicKeyHex = try await appState.identity.publicKeyHex()
                } catch {
                    print("[MyIdentityView] Failed to generate identity: \(error)")
                }
            }
        }
    }

    private func qrCodeImage(for string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return Image(systemName: "qrcode")
        }

        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #else
        return Image(nsImage: NSImage(cgImage: cgImage, size: .init(width: 240, height: 240)))
        #endif
    }
}

struct TransportStatusRow: View {
    let icon: String
    let name: String
    let status: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(color)
            Text(name)
                .font(.body)
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}
