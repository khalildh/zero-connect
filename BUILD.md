# Building Zero Connect

## Quick Start (macOS)

```bash
cd ZeroConnect
swift build       # Build everything
swift test        # Run all tests (30 tests, 8 suites)
```

## Running on iPhone

The app uses SwiftUI and requires iOS 17+. To deploy to a device:

1. **Open in Xcode**: Open `ZeroConnect/Package.swift` in Xcode
2. **Select the ZeroConnectApp scheme** from the scheme picker
3. **Set the destination** to your iPhone or simulator
4. **Configure signing**: In the project navigator, select the package and configure your development team
5. **Run** (Cmd+R)

### Required Permissions

The app needs these iOS permissions (configured in Info.plist):

- **Camera**: QR code scanning for adding contacts
- **Local Network**: Bonjour/mDNS discovery for Loom transport
- **Bluetooth**: Connecting to Meshtastic LoRa nodes

### For Physical Device Testing

You'll need:
- Apple Developer account (free tier works for personal device testing)
- iPhone running iOS 17+
- For Meshtastic: A Meshtastic-compatible LoRa device (e.g., T-Beam, RAK4631)

## Project Structure

```
ZeroConnect/
├── Package.swift                    # SPM manifest
├── Sources/
│   ├── ZeroConnectCore/             # Core library (no UI dependencies)
│   │   ├── Crypto/
│   │   │   ├── IdentityManager.swift    # P-256 keypair in Keychain
│   │   │   ├── MessageCrypto.swift      # ECDH + ChaChaPoly encryption
│   │   │   └── QRCodeIdentity.swift     # QR code contact exchange
│   │   ├── Messages/
│   │   │   ├── Message.swift            # Encrypted message envelope
│   │   │   └── Contact.swift            # Contact model
│   │   ├── Transport/
│   │   │   ├── TransportProtocol.swift  # Transport abstraction
│   │   │   ├── LoomTransport.swift      # Wi-Fi/AWDL via Loom
│   │   │   ├── MeshtasticTransport.swift # LoRa via BLE
│   │   │   ├── ServerTransport.swift    # Server message buffer (stub)
│   │   │   ├── MessageRouter.swift      # Priority-based routing
│   │   │   ├── MessageQueue.swift       # Store-and-forward queue
│   │   │   └── RelayStore.swift         # Mesh relay for other devices
│   │   └── Storage/
│   │       └── MessageStore.swift       # JSON file persistence
│   └── ZeroConnectApp/              # SwiftUI iOS app
│       ├── ZeroConnectApp.swift
│       ├── Info.plist
│       ├── ViewModels/
│       │   └── AppState.swift
│       └── Views/
│           ├── ContentView.swift
│           ├── ContactListView.swift
│           ├── ConversationView.swift
│           ├── NearbyPeersView.swift
│           ├── MyIdentityView.swift
│           ├── ScannerView.swift
│           └── SettingsView.swift
└── Tests/
    └── ZeroConnectCoreTests/
        ├── CryptoTests.swift
        ├── IdentityTests.swift
        ├── StorageTests.swift
        ├── TransportTests.swift
        └── RelayTests.swift
```

## Architecture

See [DESIGN.md](DESIGN.md) for the full system design.

### Transport Priority

Messages are routed through the best available transport:

1. **Server** (priority 3) — Internet-based message buffer (Stage 2)
2. **Loom** (priority 2) — Local Wi-Fi or Apple AWDL peer-to-peer
3. **Meshtastic** (priority 1) — LoRa mesh via Bluetooth-connected nodes

### Encryption

All messages are end-to-end encrypted:
- P-256 ECDH key agreement
- HKDF key derivation (salt: "ZeroConnect-v1")
- ChaChaPoly AEAD encryption
- Keys stored in iOS Keychain

### Relay / Store-and-Carry-Forward

When a message can't reach its recipient:
1. It enters the **MessageQueue** for retry
2. If another device receives it, it goes in the **RelayStore**
3. When peers appear during discovery, relay messages are forwarded
4. Messages expire after 7 days or 50 retry attempts
