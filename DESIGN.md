# Zero Connect — Design Document

> A delay-tolerant, transport-agnostic, encrypted messaging system that works without internet infrastructure.

---

## Version History

| Version | Date | Summary |
|---------|------|---------|
| 0.1.0 | 2026-03-10 | Initial design document. Architecture, transport stack, threat model, and roadmap. |

---

## 1. Problem

3.7 billion people lack reliable internet access. Existing messaging apps fail completely without connectivity. The alternatives — Meshtastic, Briar, Bridgefy — each solve part of the problem but none assemble the full stack: consumer UX, offline-first delivery, transport agnosticism, and real encryption.

Bridgefy failed on security. Serval failed on distribution. FireChat failed on sustainability. Meshtastic requires extra hardware and technical knowledge. Signal requires internet.

Nothing works across the full connectivity spectrum — from zero infrastructure to full cellular — in a single coherent experience.

## 2. Core Insight

Delay tolerance and mixnet privacy are the same property. The random delays inherent in offline mesh delivery are exactly the mechanism that defeats traffic correlation by a global passive adversary. The architecture that makes messaging work without internet also makes it resistant to surveillance — not as a tradeoff, but as a structural bonus.

## 3. Target Users

**Primary — Kabala, Sierra Leone:**
People in a community with strong social bonds, high mobile penetration, expensive/unreliable data, and no alternative for offline coordination. Distribution through existing trust networks. Real relationships map directly onto the technical network.

**Secondary — Burning Man / festival communities:**
Tech-savvy, motivated, willing to carry extra hardware (LoRa nodes). Dense, time-limited environment ideal for proving transport agnosticism. Revenue from this segment cross-subsidizes infrastructure costs for primary users.

**Tertiary — privacy/activist/humanitarian communities:**
Journalists, NGOs, disaster response. High sensitivity to metadata surveillance. Value the mixnet properties. Provide credibility and security audit attention.

## 4. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Application                    │
│          (Messages, Contacts, Groups)            │
├─────────────────────────────────────────────────┤
│                 Message Router                   │
│    (Selects best available transport per msg)    │
├─────────────────────────────────────────────────┤
│                 Mixnet Layer                     │
│  (Random delays, reordering, cover traffic)      │
├──────────┬──────────┬───────────┬───────────────┤
│  Loom    │Meshtastic│    SMS    │   Server      │
│ (Wi-Fi/  │  (LoRa   │ (Gateway  │  (Dumb        │
│  AWDL)   │ via BLE) │  bridge)  │   buffer)     │
└──────────┴──────────┴───────────┴───────────────┘
```

### Transport Hierarchy (best to worst bandwidth)

| Priority | Transport | Range | Bandwidth | Hardware | Internet Required |
|----------|-----------|-------|-----------|----------|-------------------|
| 1 | Cellular/Internet | Global | High | Phone | Yes |
| 2 | Loom over Wi-Fi | ~100m (same network) | High | Phone | No |
| 3 | Loom over AWDL | ~30-100m (peer-to-peer) | Medium | Apple device | No |
| 4 | SMS Gateway | Cellular range | Low | Phone | Partial |
| 5 | Meshtastic LoRa | 1-10km+ | Very low (~250 B/s) | LoRa node + Phone | No |
| 6 | Store & carry forward | Human movement | Varies | Phone | No |

The message router selects the best available transport automatically. Messages are opaque encrypted blobs — transports carry them without knowledge of content. If a higher-priority transport becomes available mid-delivery, the system upgrades transparently.

### Every Node is a Mix Node

Each device in the network — phone, server, LoRa relay — acts as a mix node by default:

1. Receives messages from multiple sources
2. Holds them for a random interval (exponential distribution)
3. Reorders the queue
4. Forwards through the best available transport
5. Generates cover traffic to fill silence

This is a **fully distributed peer-to-peer mixnet**. There is no distinguished infrastructure to identify or block. The network is the users.

## 5. Encryption & Identity

### Design Principle
No blockchain. No phone numbers. Simple keypair cryptography with QR code exchange. The identity system must work entirely offline after initial key generation.

### Key Architecture

- **Identity key**: P-256 keypair generated on device at first launch
- **Key exchange**: In-person QR code scan (contains public key)
- **Message encryption**: Double ratchet protocol (Signal protocol)
  - Forward secrecy: compromise of one key doesn't expose past/future messages
  - Every message uses a fresh derived key
  - Works entirely on-device with zero network calls
- **Key backup**: Encrypted keystore backed up to iCloud/Google Drive, or seed phrase
- **Group keys**: Group has its own keypair; group private key encrypted to each member's public key

### What This Defeats

| Threat | Protected? | How |
|--------|-----------|-----|
| Content interception | Yes | End-to-end encryption |
| Casual surveillance | Yes | Offline transports never touch monitored infrastructure |
| Basic network monitoring | Yes | Mesh traffic is opaque encrypted blobs |
| Metadata/traffic analysis | Partially | Mixnet delays + cover traffic + transport diversity |
| Phone seizure | Partially | Message expiry, key deletion, panic wipe |
| Global passive adversary | Structurally resistant | Offline legs invisible; timing obfuscation on online legs |

### What is NOT in v1
- Threshold encryption (Seal/Sui) — revisit after core product is proven
- On-chain identity — unnecessary complexity for the primary use case
- Sponsored blockchain transactions — not needed without blockchain

## 6. Server Architecture

The server is a **dumb encrypted message buffer**. It:

- Stores opaque encrypted blobs it cannot read
- Holds messages until the recipient (or a nearby relay) collects them
- Acts as a mix node (random delays, reordering) on the online leg
- Is extremely lightweight — text messages are hundreds of bytes
- Can be federated — communities run their own instances
- Has no special privileges — compromise reveals nothing

The server exists to collapse delivery times. Without it, a message must physically travel hop-by-hop. With it, a message only needs to reach any node with internet, and the server handles the rest.

## 7. Technology Stack (v0.1 — iPhone)

### Dependencies

| Component | Technology | Source |
|-----------|-----------|--------|
| Local networking | Loom (Network.framework, Bonjour, AWDL) | [EthanLipnik/Loom](https://github.com/EthanLipnik/Loom) |
| LoRa mesh | Meshtastic BLE protocol | Extracted from [meshtastic/Meshtastic-Apple](https://github.com/meshtastic/Meshtastic-Apple) |
| Protobuf | MeshtasticProtobufs SPM package | meshtastic/Meshtastic-Apple |
| Encryption | CryptoKit (P-256, HKDF, ChaCha20-Poly1305) | Apple platform |
| UI | SwiftUI | Apple platform |
| Persistence | SwiftData or Core Data | Apple platform |
| Server | Lightweight message buffer (Vapor, or Cloudflare Worker) | Custom |

### Meshtastic BLE Integration

No standalone Swift SDK exists. We build a lean `MeshtasticTransport` that:

- Scans for Meshtastic service `6BA1B218-15A8-461F-9FA8-5DCAE273EAFD`
- Discovers 4 characteristics: TORADIO (write), FROMRADIO (read), FROMNUM (notify), LOGRADIO (logs)
- Sends `ToRadio` protobuf messages, receives `FromRadio` responses
- Wraps CoreBluetooth in async/await actors (following patterns from Meshtastic-Apple)
- Handles connection lifecycle, reconnection, and RSSI tracking

### Loom Integration

Loom provides the local/nearby transport as a Swift Package:

- `LoomNode` for advertising and connecting
- `LoomAuthenticatedSession` for multiplexed encrypted streams
- `LoomDiscovery` for Bonjour peer discovery
- `LoomIdentityManager` for P-256 keys (can share with our identity layer)
- Peer-to-peer via `includePeerToPeer = true` (AWDL, no router)
- iOS 17.4+, Swift 6.2

### Peer Identity Map

Links identities across transports:

```
LoomPeer (P-256 public key, device ID)
    ↔ Meshtastic Node (!hex node ID)
    ↔ User-facing identity ("Sarah")
```

Pairing established when a user is visible on both networks simultaneously, or manually via QR code that contains all identity material.

## 8. Roadmap

### v0.1 — Proof of Concept (iPhone)
- [ ] Xcode project with Loom + MeshtasticProtobufs dependencies
- [ ] `MeshtasticTransport`: BLE scan, connect, send/receive protobufs
- [ ] `LoomTransport`: discover peers, open sessions, send/receive data
- [ ] Unified `Message` type that travels over either transport
- [ ] `MessageRouter` that picks the best available transport
- [ ] Basic SwiftUI: peer list, message thread, QR code exchange
- [ ] P-256 keypair generation and simple encrypted payloads
- [ ] Test between 2 iPhones with a Meshtastic node

### v0.2 — Encryption & Relay
- [ ] Double ratchet implementation (or integrate libsignal)
- [ ] Lightweight relay server (encrypted message buffer)
- [ ] Store-and-carry-forward: hold undelivered messages, relay on proximity
- [ ] Message persistence (SwiftData)
- [ ] Group messaging (shared group key)

### v0.3 — Mixnet Properties
- [ ] Random forwarding delays (configurable exponential distribution)
- [ ] Message reordering at each hop
- [ ] Cover traffic generation (tunable frequency, battery-aware)
- [ ] Timing obfuscation on server leg

### v0.4 — SMS Bridge
- [ ] SMS gateway integration (Twilio or similar)
- [ ] Encrypted message payloads over SMS
- [ ] Gateway phone concept: one device bridges SMS ↔ mesh for a community

### v0.5 — Android
- [ ] Android app using Google Nearby Connections API (replaces Loom)
- [ ] Shared encrypted message format across platforms
- [ ] Cross-platform testing (iPhone ↔ Android via server + Meshtastic)

### v1.0 — Kabala Pilot
- [ ] Field testing in Kabala, Sierra Leone
- [ ] UX iteration based on real usage
- [ ] Community gateway nodes deployed
- [ ] Message delivery reliability metrics
- [ ] Security audit by external reviewer

### Future Considerations (post v1.0)
- Threshold encryption (Seal/Sui) for trustless identity
- USSD bridge for feature phones
- Ultrasonic audio data transfer
- NFC tap-to-exchange message bundles
- Vehicle/movement-based relay optimization
- Burning Man deployment and cross-subsidization model

## 9. Open Questions

1. **libsignal vs custom double ratchet** — libsignal is proven but heavy and C-based. A lightweight Swift implementation is possible but risky to get wrong. Needs security review either way.
2. **Loom identity ↔ app identity** — Loom uses P-256 in iCloud Keychain. Should we reuse Loom's identity as the app identity, or maintain separate keys?
3. **LoRa message size constraints** — Meshtastic payloads max ~237 bytes. Encrypted messages with double ratchet headers may exceed this. Fragmentation strategy needed.
4. **Background BLE on iOS** — CoreBluetooth background modes exist but are restricted. How reliable is passive message relay when the app isn't foregrounded?
5. **Cover traffic battery impact** — needs real-world measurement. Tuning parameters should be user-configurable.
6. **Server hosting model** — self-hosted Vapor, Cloudflare Workers, or federated community instances?

## 10. Principles

1. **Offline is the default, not the exception.** Online is just a faster pipe.
2. **The user never thinks about transport.** Messages just arrive.
3. **Security is structural, not behavioral.** Privacy emerges from the design, not from users making good choices.
4. **Start with real people.** Build for Kabala first, generalize second.
5. **Simplest thing that works.** No blockchain until we need blockchain. No LoRa until Bluetooth isn't enough. No mixnet until the messages are flowing.
