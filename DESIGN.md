# Zero Connect — Design Document

> An offline-first, encrypted messaging app that lets people send messages without internet or phone credits. Messages move between nearby phones and arrive when they can.

---

## Version History

| Version | Date | Summary |
|---------|------|---------|
| 0.1.0 | 2026-03-10 | Initial design document. |
| 0.2.0 | 2026-03-10 | Fully distributed P2P architecture with DHT, mixnet properties, message fragmentation. |
| 0.3.0 | 2026-03-10 | Refocused on core product: offline messaging that works. Moved privacy research, DHT, mixnet, and fragmentation to FUTURE-RESEARCH.md. Tightened roadmap. Android elevated to Stage 2. |
| 0.3.1 | 2026-03-10 | Restored core architectural commitment: no central server. Every phone is a server. Clarified what "internet when available" means (phone-to-phone, not phone-to-server). Added serverless architecture section. |
| 0.4.0 | 2026-03-10 | Replaced serverless commitment with lightweight server (dumb encrypted message buffer). Server dramatically simplifies delivery when someone has internet. Phones still relay locally without it. Fully serverless architecture moved to FUTURE-RESEARCH.md. |

---

## 1. Problem

People in Kabala, Sierra Leone can't reliably message each other. Internet is expensive, unreliable, or absent. Phone credits cost money. When the network is down — which is often — communication stops entirely.

Existing tools don't solve this:
- **WhatsApp/Signal** — require internet. Useless without data.
- **SMS** — costs money per message. No encryption.
- **Meshtastic** — requires extra hardware and technical knowledge.
- **Briar** — technically capable but ugly, complex, Android-only, and unknown.
- **Bridgefy/FireChat** — dead or broken.

The gap: a simple messaging app that works without internet, without phone credits, on the cheap phones people already have.

## 2. Core Insight

Messages don't need the internet to travel between phones. Bluetooth, Wi-Fi Direct, and LoRa radio can move data between nearby devices with no infrastructure at all. If a message can't reach its destination directly, it can wait — stored on the sender's phone or on relay devices — and arrive later when a path opens up.

The user doesn't need to know how the message got there. They just need to know it arrived.

## 3. The Server

A lightweight server acts as a **dumb encrypted message buffer** — a mailbox, not a platform.

### What it does
- Stores opaque encrypted blobs it **cannot read**
- Holds messages until the recipient's device picks them up
- Acts as a relay when sender and recipient aren't near each other and no relay phones are available

### What it doesn't do
- Read, decrypt, or inspect any message content
- Know anything about users beyond ephemeral connection metadata
- Make decisions about routing or delivery
- Store anything permanently — messages expire

### Why a server (for now)
Without a server, a message between two people who are never physically near each other depends entirely on relay phones walking between them. In Kabala, that might work — people move predictably, the social graph is dense. But it's fragile and slow. A server collapses delivery time dramatically: any phone with even brief internet access flushes its queued messages to the server, and the recipient picks them up whenever they next get connectivity.

The server is the **giant shortcut**. Instead of routing messages toward a specific destination through the mesh, you just route them toward any internet connection. Getting to the nearest internet connection is a much easier problem.

### Properties
- **Extremely lightweight** — text messages are hundreds of bytes. A single cheap cloud instance or even a Raspberry Pi could handle thousands of users.
- **Trustless** — the server sees only encrypted blobs. Seizing it reveals nothing readable.
- **Replaceable** — the protocol doesn't depend on _this_ server. Anyone can run one. Communities can run their own.
- **Optional for local delivery** — messages between nearby phones travel directly via Bluetooth/Wi-Fi/LoRa without ever touching the server.

### Long-term vision
The server is a pragmatic starting point, not the end state. As the network grows, fully distributed alternatives (DHT, peer-to-peer relay) may replace or supplement it. See [FUTURE-RESEARCH.md](FUTURE-RESEARCH.md).

## 4. Target Users

**Primary — Kabala, Sierra Leone:**
Family and community members who want to message each other without paying for data or phone credits. Strong social bonds mean trust is already established — people know each other. Dominant devices: Tecno Spark, Infinix Hot, Itel — $50-80 Android phones. Languages: Krio (lingua franca), Kuranko, Mandinka, English.

**Secondary — Burning Man / festival communities:**
Tech-savvy, motivated. Dense environment with no cell service. Willing to carry LoRa hardware. Good testing ground and potential revenue source.

**Tertiary — privacy/activist/humanitarian communities:**
Journalists, NGOs, disaster response. Different value proposition (metadata resistance) addressed in [FUTURE-RESEARCH.md](FUTURE-RESEARCH.md).

## 5. How It Works

### The Simple Version

1. Two people meet and scan each other's QR codes (adds each other as contacts)
2. One sends a message
3. If the other person's phone is nearby (Bluetooth/Wi-Fi range), the message arrives immediately
4. If not, the message waits on the sender's phone
5. When someone who knows both people passes near the sender, their phone silently picks up the message
6. When that person later passes near the recipient, their phone delivers it
7. If anyone in the chain gets internet, their phone flushes the message to the server — the recipient picks it up whenever they next get connectivity

Messages are encrypted end-to-end. Relay phones carry opaque blobs they can't read.

### Architecture

```
┌─────────────────────────────────────────────────┐
│                   Application                    │
│         (Messages, Contacts, UI)                 │
├─────────────────────────────────────────────────┤
│              Encryption Layer                    │
│         (End-to-end encrypted payloads)          │
├─────────────────────────────────────────────────┤
│            Sync & Store-Forward                  │
│  (Append-only logs, anti-entropy replication)    │
├──────────┬──────────┬───────────────────────────┤
│  Loom    │Meshtastic│  Server                    │
│ (Wi-Fi/  │  (LoRa   │  (Dumb encrypted buffer,   │
│  AWDL)   │ via BLE) │  when internet available)  │
└──────────┴──────────┴───────────────────────────┘
```

Local transports (Loom, Meshtastic) work phone-to-phone with no server. The server is only involved when a phone has internet and wants to flush or fetch messages.

### Transports

| Transport | Range | Bandwidth | Hardware | Internet Required |
|-----------|-------|-----------|----------|-------------------|
| Server (message buffer) | Global | High | Phone | Yes |
| Loom over Wi-Fi | ~100m (same network) | High | Phone | No |
| Loom over AWDL | ~30-100m (peer-to-peer) | Medium | Apple device | No |
| Meshtastic LoRa | 1-10km+ | Very low (~250 B/s) | LoRa node + Phone | No |
| Store & carry forward | Human movement | Varies | Phone | No |

The app selects the best available transport automatically. The user never thinks about it.

### Message Delivery & Sync

Inspired by [Secure Scuttlebutt](https://scuttlebutt.nz/):

- Each user has an **append-only log** of their messages, cryptographically signed
- When two devices meet, they compare logs and exchange missing entries (anti-entropy sync)
- No complex routing needed — devices simply share what they have when they're nearby
- Messages are deduplicated by ID so multiple delivery paths don't create duplicates
- Messages expire after a configurable period to manage storage on cheap phones

### Delivery States

Users need to understand what happened to their message:

| State | Meaning |
|-------|---------|
| Queued | Message is on your phone, waiting for a path |
| Carried | A relay device has picked it up |
| Delivered | Recipient's device has received it |
| Read | Recipient has opened it |

These states update as information flows back through the network. In offline conditions, "Queued" may persist for hours — the UI must make this feel normal, not broken.

## 6. Encryption & Identity

### Design Principle
No phone numbers. No accounts. Simple keypair cryptography with QR code exchange.

### How It Works

- **Identity**: Device generates a keypair on first launch. This is your identity — no signup, no server.
- **Adding contacts**: Scan someone's QR code in person. The QR contains their public key. This maps onto how trust already works in communities like Kabala — face to face.
- **Message encryption**: Each message is encrypted to the recipient's public key. Relay devices carry opaque blobs they cannot read.
- **Key backup**: Encrypted keystore backed up to iCloud/Google Drive, or written-down seed phrase.

### Security Properties

| Threat | Status | Notes |
|--------|--------|-------|
| Content interception | Strong | End-to-end encryption; relay nodes can't read messages |
| Casual surveillance | Strong | Most traffic stays local and never touches the internet |
| Phone theft/seizure | Partial | Message expiry helps; endpoint compromise is always hard |
| Metadata analysis | Partial | Reduced by local transport; not formally proven. See [FUTURE-RESEARCH.md](FUTURE-RESEARCH.md) |

**Use a mature, reviewed encryption library.** Do not ship custom cryptographic implementations without external review.

## 7. Technology Stack

### Stage 1 — iPhone Proof of Concept

| Component | Technology | Source |
|-----------|-----------|--------|
| Local networking | Loom (Network.framework, Bonjour, AWDL) | [EthanLipnik/Loom](https://github.com/EthanLipnik/Loom) |
| LoRa mesh | Meshtastic BLE protocol | Extracted from [meshtastic/Meshtastic-Apple](https://github.com/meshtastic/Meshtastic-Apple) |
| Protobuf | MeshtasticProtobufs SPM package | meshtastic/Meshtastic-Apple |
| Encryption | CryptoKit (P-256, HKDF, ChaCha20-Poly1305) | Apple platform |
| UI | SwiftUI | Apple platform |
| Persistence | SwiftData | Apple platform |
| Server | Lightweight message buffer (Vapor, Hummingbird, or Cloudflare Worker) | Custom |

### Meshtastic BLE Integration

No standalone Swift SDK exists. We build a lean `MeshtasticTransport`:

- Scans for Meshtastic service `6BA1B218-15A8-461F-9FA8-5DCAE273EAFD`
- Discovers 4 characteristics: TORADIO (write), FROMRADIO (read), FROMNUM (notify), LOGRADIO (logs)
- Sends `ToRadio` protobuf messages, receives `FromRadio` responses
- Wraps CoreBluetooth in async/await actors
- Handles connection lifecycle, reconnection, and RSSI tracking

### Loom Integration

Loom provides the local/nearby transport as a Swift Package:

- `LoomNode` for advertising and connecting
- `LoomAuthenticatedSession` for multiplexed encrypted streams
- `LoomDiscovery` for Bonjour peer discovery
- Peer-to-peer via `includePeerToPeer = true` (AWDL, no router)
- iOS 17.4+, Swift 6.2

### Peer Identity Map

```
LoomPeer (P-256 public key, device ID)
    ↔ Meshtastic Node (!hex node ID)
    ↔ User-facing identity ("Sarah")
```

Pairing established when a user is visible on both networks simultaneously, or via QR code containing all identity material.

### Stage 2 — Android

This is where the primary users are. Kabala runs on Android.

The $50-80 devices that dominate Sierra Leone (Tecno, Infinix, Itel) have:
- Older Android versions with inconsistent Bluetooth implementations
- Aggressive battery optimization that kills background processes (especially Samsung, Xiaomi, Huawei OEM layers)
- Limited RAM — apps get killed frequently
- Slower processors affecting crypto operations

Google's Nearby Connections API replaces Loom on Android. Same protocol, different platform transport.

**The first real field test must be on a Tecno Spark or Infinix Hot — not a flagship device.** If it works on those, everything else is easy.

Key Android-specific challenges:
- Background Bluetooth/Wi-Fi Direct reliability across OEM variants
- Battery impact must be near-zero or users will uninstall
- App size and storage footprint on devices with 16-32GB total storage
- Thermals — sustained background crypto on low-end chipsets

## 8. Roadmap

### Stage 1 — Nearby Encrypted Messaging (iPhone PoC)

Prove that two phones can exchange encrypted messages without internet.

- [ ] Xcode project with Loom + MeshtasticProtobufs dependencies
- [ ] `MeshtasticTransport`: BLE scan, connect, send/receive protobufs
- [ ] `LoomTransport`: discover peers, open sessions, send/receive data
- [ ] Unified `Message` type that travels over either transport
- [ ] `MessageRouter` that picks the best available transport
- [ ] On-device keypair generation
- [ ] QR code contact exchange
- [ ] Basic encrypted message send/receive
- [ ] Basic SwiftUI: contact list, message thread
- [ ] Test between 2 iPhones + a Meshtastic node

**Success criteria:** Two iPhones can exchange encrypted messages over Loom (nearby Wi-Fi/AWDL) and over Meshtastic (LoRa via BLE), with automatic transport selection.

### Stage 2 — Server, Store-Forward & Android

Add the server for reliable delivery over internet. Make messages survive disconnection. Get onto the phones people actually use.

- [ ] Lightweight server: receive encrypted blobs, hold until recipient fetches, expire after TTL
- [ ] Phone → server flush: when internet is available, push queued messages to server
- [ ] Server → phone fetch: when internet is available, pull pending messages from server
- [ ] Append-only message logs with local persistence
- [ ] Anti-entropy sync — devices exchange missing messages on reconnect (local)
- [ ] Store-and-carry-forward: relay devices hold and pass messages (offline)
- [ ] Clear delivery state UI (queued → carried → delivered → read)
- [ ] Message expiry and storage management
- [ ] Android app using Google Nearby Connections API
- [ ] Testing on Tecno Spark / Infinix Hot
- [ ] Battery optimization for aggressive Android OEMs

**Success criteria:** A message sent when the recipient is out of range arrives later — via server (if internet), relay phone, or reconnection — on a cheap Android phone, with acceptable battery impact.

### Stage 3 — Kabala Field Testing

Test with real people in the real environment.

- [ ] Visit Kabala — observe how people actually communicate today
- [ ] Identify the specific painful communication gap to solve first
- [ ] Deploy to a small group (target: 30-50 people in one neighborhood)
- [ ] UX testing with community members
- [ ] Language localization (Krio, Kuranko)
- [ ] Measure: delivery latency, battery impact, message loss rate, user comprehension
- [ ] Iterate based on what breaks and what people actually need

**Success criteria:** People in Kabala use it to communicate something they couldn't communicate before, and keep using it.

### Future Stages

See [FUTURE-RESEARCH.md](FUTURE-RESEARCH.md) for:
- Distributed storage (DHT / Kademlia)
- Privacy and metadata resistance (mixnet properties, cover traffic)
- Message fragmentation
- SMS gateway bridge
- USSD bridge for feature phones
- Extended transports (NFC, ultrasonic, IR, TV white space)
- Burning Man deployment
- Formal security analysis

## 9. Distribution & Adoption

This is the hardest problem. Every technical predecessor — Briar, Serval, FireChat, Bridgefy — failed primarily on distribution, not technology.

### The Cold Start Problem

The app is useless with one user. It's barely useful with ten. It only becomes valuable when enough people in the same physical area have it. That's a brutal chicken-and-egg problem.

### Why Kabala is Different

- **Existing trust network**: The founder is from Kabala. Family connections provide the initial seed.
- **Dense social graph**: People know each other. Word of mouth is the primary distribution channel and it works fast in tight communities.
- **Clear pain point**: Can't message when data is down or credits run out. This is a daily frustration, not a theoretical problem.
- **No competition**: Nobody in Kabala is using Briar or Meshtastic. The alternative is nothing.

### Distribution Strategy

1. **Seed through family**: Get the app on 5-10 phones within the founder's family network
2. **Expand through use**: Each person who receives a message from the app becomes a potential user
3. **Target a specific workflow**: Not "general messaging" but one high-frequency task (e.g., market-day coordination, family check-ins when network is down)
4. **Community champions**: Identify 2-3 trusted, tech-comfortable people who can help others install and learn
5. **QR exchange as social ritual**: Adding someone is a physical, in-person act — this is distribution and onboarding in one gesture

### The Everyday Use Question

The app must be useful even when internet is working. If people only open it during outages, they'll forget about it between outages and uninstall. The app needs a reason to be the default messaging choice — or at least a frequent secondary one — so it's already installed and running when infrastructure fails.

## 10. Open Questions

1. **Encryption library choice** — Use a mature, reviewed library. Do not write custom crypto. Evaluate libsignal (proven, heavy, C-based) vs lighter alternatives.
2. **Loom identity ↔ app identity** — Loom uses P-256 in iCloud Keychain. Reuse Loom's identity as the app identity, or maintain separate keys?
3. **LoRa message size** — Meshtastic payloads max ~237 bytes. Encrypted messages may exceed this. Need a fragmentation-at-transport-level strategy.
4. **Background operation on iOS** — CoreBluetooth background modes are restricted. How reliable is passive relay when the app isn't foregrounded?
5. **Background operation on Android** — OEM battery optimization may be the dominant technical challenge. Needs real testing on target devices.
6. **What's the killer first workflow?** — "Messaging" is too broad. What specific communication task do we solve first for Kabala? Needs field research.
7. **Relay incentives** — Why would someone's phone carry messages for others? Battery cost is real. Reciprocity ("you relay for me, I relay for you") may be enough in a tight community, but needs validation.

## 11. Pre-Build Checklist

### Security
- [ ] Identify a security-knowledgeable advisor before writing encryption code
- [ ] Plan to open source the core protocol and apps

### Research
- [ ] Talk to people in Kabala about their actual communication pain points (before building)
- [ ] Study Secure Scuttlebutt's replication model and failure modes
- [ ] Study Briar's Bluetooth mesh implementation and what works/breaks

### Devices
- [ ] Procure target Android phones (Tecno Spark, Infinix Hot, Itel) for testing
- [ ] Document background Bluetooth/Wi-Fi behavior on each device

### Partnerships
- [ ] Meshtastic community — hardware expertise, existing deployments
- [ ] Local organizations in Kabala — distribution and trust
- [ ] Academic partners — security review, potential research collaboration

### Sustainability
- [ ] Grant funding: GSMA Mobile for Development, Mozilla Foundation, Shuttleworth Foundation
- [ ] Burning Man / festival market as revenue source for cross-subsidization
- [ ] Explore: outdoor recreation, disaster preparedness, maritime as paying markets

## 12. Principles

1. **The server is a mailbox, not a platform.** It holds encrypted blobs it can't read. Local delivery works without it.
2. **Offline is the default, not the exception.** Online is just a faster pipe.
3. **The user never thinks about transport.** Messages just arrive.
4. **Start with real people.** Build for Kabala first, generalize second.
5. **Simplest thing that works.** Add complexity only when the simple version isn't enough.
6. **Learnable in 60 seconds.** If someone can't learn the app by watching another person use it, the UX has failed.
7. **Security should come from defaults and architecture, not from expert user behavior.**
8. **The first version is not a censorship-proof anonymity network.** It is a reliable offline-first encrypted messenger for people with intermittent connectivity and real-world devices.
