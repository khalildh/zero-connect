# Zero Connect — Design Document

> A delay-tolerant, transport-agnostic, encrypted messaging system where every phone is simultaneously a client, relay, mix node, and server. There is no other infrastructure. The network is the people.

---

## Version History

| Version | Date | Summary |
|---------|------|---------|
| 0.1.0 | 2026-03-10 | Initial design document. Architecture, transport stack, threat model, and roadmap. |
| 0.2.0 | 2026-03-10 | Fully distributed P2P architecture. No central server — every device is a server. DHT replaces server for message storage/routing. DHT-as-mixnet. Local DHT mutation replaces constant cover traffic transmission. Scuttlebutt-inspired append-only logs. Message fragmentation across nodes. Regulatory, governance, and sustainability considerations. Android-first reality for Kabala (Tecno/Infinix devices). Language/literacy requirements (Krio, Kuranko). |

---

## 1. Problem

3.7 billion people lack reliable internet access. Existing messaging apps fail completely without connectivity. The alternatives — Meshtastic, Briar, Bridgefy — each solve part of the problem but none assemble the full stack: consumer UX, offline-first delivery, transport agnosticism, and real encryption.

Bridgefy failed on security. Serval failed on distribution. FireChat failed on sustainability. Meshtastic requires extra hardware and technical knowledge. Signal requires internet.

Nothing works across the full connectivity spectrum — from zero infrastructure to full cellular — in a single coherent experience.

## 2. Core Insight

Delay tolerance and mixnet privacy are the same property. The random delays inherent in offline mesh delivery are exactly the mechanism that defeats traffic correlation by a global passive adversary. The architecture that makes messaging work without internet also makes it resistant to surveillance — not as a tradeoff, but as a structural bonus.

## 3. Target Users

**Primary — Kabala, Sierra Leone:**
People in a community with strong social bonds, high mobile penetration, expensive/unreliable data, and no alternative for offline coordination. Distribution through existing trust networks and family connections. Real relationships map directly onto the technical network. Dominant devices: Tecno Spark, Infinix Hot, Itel — $50-80 Android phones. Languages: Krio (lingua franca), Kuranko, Mandinka, English.

**Secondary — Burning Man / festival communities:**
Tech-savvy, motivated, willing to carry extra hardware (LoRa nodes). Dense, time-limited environment ideal for proving transport agnosticism. Revenue from this segment cross-subsidizes infrastructure costs for primary users.

**Tertiary — privacy/activist/humanitarian communities:**
Journalists, NGOs, disaster response. High sensitivity to metadata surveillance. Value the mixnet properties. Provide credibility and security audit attention.

## 4. Architecture Overview

### No Central Server

Every phone is simultaneously a client, a relay, a mix node, and a server. There is no central infrastructure. The network cannot be shut down without shutting down every device — the same property that makes BitTorrent essentially impossible to kill.

This means:
- Nothing to seize or subpoena
- No single point of failure
- No server costs or maintenance
- No company infrastructure to attack
- No target for adversaries
- The community owns the network

### Protocol Stack

```
┌─────────────────────────────────────────────────┐
│                   Application                    │
│       (Messages, Contacts, Groups, UI)           │
├─────────────────────────────────────────────────┤
│              Encryption Layer                    │
│    (Double ratchet, keypair identity, groups)     │
├─────────────────────────────────────────────────┤
│              Routing & Storage                   │
│  DHT (Kademlia) + Epidemic routing + Mixnet      │
├──────────┬──────────┬───────────┬───────────────┤
│  Loom    │Meshtastic│    SMS    │  Bluetooth    │
│ (Wi-Fi/  │  (LoRa   │ (Gateway  │  (Nearby      │
│  AWDL)   │ via BLE) │  bridge)  │  Connections) │
└──────────┴──────────┴───────────┴───────────────┘
```

### Transport Hierarchy (best to worst bandwidth)

| Priority | Transport | Range | Bandwidth | Hardware | Internet Required |
|----------|-----------|-------|-----------|----------|-------------------|
| 1 | Cellular/Internet | Global | High | Phone | Yes |
| 2 | Loom over Wi-Fi | ~100m (same network) | High | Phone | No |
| 3 | Loom over AWDL | ~30-100m (peer-to-peer) | Medium | Apple device | No |
| 4 | Bluetooth mesh | ~30m | Medium | Phone | No |
| 5 | SMS Gateway | Cellular range | Low | Phone | Partial |
| 6 | Meshtastic LoRa | 1-10km+ | Very low (~250 B/s) | LoRa node + Phone | No |
| 7 | Store & carry forward | Human movement | Varies | Phone | No |

The message router selects the best available transport automatically. Messages are opaque encrypted blobs — transports carry them without knowledge of content. If a higher-priority transport becomes available mid-delivery, the system upgrades transparently.

## 5. Distributed Storage — The DHT

Messages are stored and routed through a **Kademlia DHT** — the same algorithm used by BitTorrent and Ethereum, proven at internet scale for 20+ years.

### How Messages Get Delivered

**Locally (offline)** — Epidemic routing:
- Device receives a message and keeps a copy temporarily
- When two devices meet (Bluetooth, AWDL, LoRa), they compare what messages each holds
- Missing messages are exchanged automatically
- Messages eventually reach every nearby device
- Delete after delivery confirmation or expiry
- No routing algorithm needed — simple, robust, works completely offline

**Globally (when any node has internet)** — DHT:
- Messages are pushed into the DHT where recipients can find them
- Any device with internet becomes a bridge — its phone flushes the message into the DHT
- Recipient queries the DHT when they get connectivity
- No central server — the DHT is distributed across all internet-connected nodes

**The transition is seamless.** A message might travel via Bluetooth hop-by-hop through a village, get picked up by someone walking to the market who has cell signal, get flushed into the DHT, and arrive at the recipient's phone within minutes. Nobody orchestrated this — it emerged from the architecture.

### Message Fragmentation

Messages are split into fragments and distributed across the DHT:
- No single device holds a complete message
- Seizing one phone reveals nothing
- The message only reconstitutes when the recipient queries the DHT for all fragments
- Individual fragments are encrypted and meaningless without the recipient's private key
- Similar to how IPFS handles content-addressed storage

### Storage Economics

Every device contributes storage proportional to what it consumes. The DHT naturally distributes load across nodes. In Kabala, a message from Maria to her sister might be fragmented across twenty devices in the community, each holding an encrypted piece that means nothing alone. No single device becomes a bottleneck.

**Storage tiers:**
- Volunteer storage nodes — a Raspberry Pi, an old Android phone plugged in, a community device
- Reciprocal storage — you store for me, I store for you
- Probabilistic storage — every device stores fragments temporarily with random duration; with enough participants, at least one device still has it when the recipient comes online

### Precedent: Secure Scuttlebutt

The closest existing system. Fully P2P, works offline, syncs when devices meet, no central server. Used by sailing and off-grid communities. Study deeply before writing code.

Key Scuttlebutt concept we adopt: **append-only logs**. Each user has a personal log of messages, cryptographically signed. Other devices store copies of logs they're interested in. When two devices meet, they compare and sync missing entries. This is a CRDT (Conflict-free Replicated Data Type) — proven technology for distributed systems that sync without coordination.

Scuttlebutt's weaknesses we address: no transport hierarchy, no mixnet properties, no LoRa/SMS fallback, technical UX.

## 6. The DHT as Mixnet

### Every Node is a Mix Node

Each device in the network acts as a mix node by default:

1. Receives messages from multiple sources
2. Holds them for a random interval (exponential distribution)
3. Reorders the queue
4. Forwards through the best available transport

There is no distinguished mixnet infrastructure. No list of mix nodes to block or monitor. The network is the users — you can't block the mixnet without blocking every phone. This is a **fully distributed peer-to-peer mixnet**, considered theoretically stronger than centralized mixnet architectures (Tor, Nym).

### Kademlia Queries as Natural Onion Routing

DHT queries are routed through multiple intermediate nodes before reaching their destination. Each intermediate node only knows its neighbors, not the full path. This is structurally similar to onion routing. Adding random delays at each hop completes the mixnet property. **The DHT is the mixnet.** Same infrastructure, same traffic, same operations.

### Cover Traffic via Local DHT Mutation (Not Constant Transmission)

Traditional cover traffic constantly transmits fake messages — expensive on battery and bandwidth. We take a fundamentally different approach:

**The insight:** You don't need to generate fake traffic constantly. You just need the DHT state on your device to be constantly shifting so that when you do transmit, the snapshot looks different every time. An observer can't distinguish a real message transmission from a routine DHT update.

**While plugged in and charging (zero transmission cost):**
- Re-encrypt stored fragments with fresh ephemeral keys
- Rotate which fragments the device is responsible for in DHT keyspace
- Compute new Kademlia routing table entries
- Pre-compute encrypted message fragments ready to send
- Refresh expiry timestamps on stored entries

**None of this touches the radio.** All of it means the next sync looks completely fresh.

**When transmission happens (syncing with a neighbor):**
- The transmitted DHT state looks completely different from the last sync
- Even if no real messages were sent
- Real messages are indistinguishable from routine state updates

**The analogy:** A card dealer constantly shuffling the deck between hands. The shuffle happens silently on the table. When cards are dealt, the observer sees a fresh arrangement with no relationship to the previous hand. The shuffling cost is near-zero. The dealing reveals nothing.

**Battery-aware tuning:**
| Device State | Local Mutation | Transmission |
|-------------|---------------|--------------|
| Plugged in, charging | Maximum — constant reshuffling, re-encryption, pre-computation | Normal sync schedule |
| Good battery | Moderate reshuffling | Normal sync |
| Low battery | Minimal reshuffling | Sync only when necessary |
| Critical battery | None | Send/receive real messages only |

**For Kabala specifically:** People charge their phones when they can — overnight at home, at charging stations, at the market. Those charging moments become the network's privacy maintenance windows. The community's phones collectively reshape the DHT while charging, so daytime transmission reveals nothing about who is communicating.

### What a GPA Sees

A global passive adversary watching every transport simultaneously sees:
- Constant Bluetooth activity between nearby devices
- Constant DHT queries on the internet (when connected)
- Periodic LoRa transmissions across the mesh
- Every sync contains a fresh DHT state unrelated to the previous one
- No timing correlation possible — delays are random
- No social graph inferable — all traffic looks like DHT maintenance
- No way to distinguish real messages from state updates

This is stronger than traditional cover traffic, which can theoretically be statistically separated from real traffic. A constantly mutating DHT state produces **no signal at all**.

## 7. Encryption & Identity

### Design Principle
No blockchain. No phone numbers. Simple keypair cryptography with QR code exchange. The identity system must work entirely offline after initial key generation.

### Key Architecture

- **Identity key**: P-256 keypair generated on device at first launch
- **Key exchange**: In-person QR code scan (contains public key) — maps perfectly onto how trust is already established in communities like Kabala
- **Message encryption**: Double ratchet protocol (Signal protocol)
  - Forward secrecy: compromise of one key doesn't expose past/future messages
  - Every message uses a fresh derived key
  - Works entirely on-device with zero network calls
- **Key backup**: Encrypted keystore backed up to iCloud/Google Drive, or seed phrase
- **Group keys**: Group has its own keypair; group private key encrypted to each member's public key

### Cold Start Solution

Two people who have never been near each other and have no internet — how do they find each other? They meet in person and scan QR codes. This is how people in Kabala already establish trust — face to face. The technology maps onto the existing social practice. After that first exchange, the network handles everything.

### Device Compromise Mitigations

- **Message expiry** — old messages delete automatically
- **Key deletion after decryption** — once read, decryption key is destroyed
- **Forward secrecy** — old keys can't decrypt new messages
- **Panic wipe** — hidden gesture wipes all keys instantly

### What This Defeats

| Threat | Protected? | How |
|--------|-----------|-----|
| Content interception | Yes | End-to-end encryption |
| Casual surveillance | Yes | Offline transports never touch monitored infrastructure |
| Basic network monitoring | Yes | Mesh traffic is opaque encrypted blobs |
| Metadata/traffic analysis | Yes | DHT mutation + random delays + transport diversity |
| Phone seizure | Partially | Message expiry, key deletion, panic wipe |
| Message reconstruction from relay nodes | Yes | Fragmentation — no single device holds a complete message |
| Global passive adversary | Structurally resistant | Offline legs invisible; DHT mutation on online legs; no signal to correlate |

### What is NOT in v1
- Threshold encryption (Seal/Sui) — revisit after core product is proven
- On-chain identity — unnecessary complexity for the primary use case

## 8. Technology Stack

### v0.1 — iPhone Proof of Concept

| Component | Technology | Source |
|-----------|-----------|--------|
| Local networking | Loom (Network.framework, Bonjour, AWDL) | [EthanLipnik/Loom](https://github.com/EthanLipnik/Loom) |
| LoRa mesh | Meshtastic BLE protocol | Extracted from [meshtastic/Meshtastic-Apple](https://github.com/meshtastic/Meshtastic-Apple) |
| Protobuf | MeshtasticProtobufs SPM package | meshtastic/Meshtastic-Apple |
| Encryption | CryptoKit (P-256, HKDF, ChaCha20-Poly1305) | Apple platform |
| UI | SwiftUI | Apple platform |
| Persistence | SwiftData or Core Data | Apple platform |

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
    ↔ DHT address (Kademlia key)
    ↔ User-facing identity ("Sarah")
```

Pairing established when a user is visible on both networks simultaneously, or manually via QR code that contains all identity material.

### Android Reality (v0.5+)

Kabala runs on Android. The $50-80 devices that dominate Sierra Leone (Tecno, Infinix, Itel) have:
- Older Android versions with inconsistent Bluetooth implementations
- Aggressive battery optimization that kills background processes
- Limited RAM causing apps to be killed frequently
- Slower processors affecting cryptographic operations

Google's Nearby Connections API replaces Loom on Android. Same protocol, different platform transport. **First real test must be on a Tecno Spark or Infinix Hot** — not a flagship device.

## 9. Roadmap

### v0.1 — Proof of Concept (iPhone)
- [ ] Xcode project with Loom + MeshtasticProtobufs dependencies
- [ ] `MeshtasticTransport`: BLE scan, connect, send/receive protobufs
- [ ] `LoomTransport`: discover peers, open sessions, send/receive data
- [ ] Unified `Message` type that travels over either transport
- [ ] `MessageRouter` that picks the best available transport
- [ ] Basic SwiftUI: peer list, message thread, QR code exchange
- [ ] P-256 keypair generation and simple encrypted payloads
- [ ] Test between 2 iPhones with a Meshtastic node

### v0.2 — Distributed Storage & Encryption
- [ ] Kademlia DHT implementation (or integrate existing Swift DHT library)
- [ ] Append-only message logs (Scuttlebutt-inspired CRDT)
- [ ] Epidemic routing for local mesh delivery
- [ ] Message fragmentation across DHT nodes
- [ ] Double ratchet implementation (or integrate libsignal)
- [ ] Store-and-carry-forward: hold undelivered messages, relay on proximity
- [ ] Message persistence (SwiftData)
- [ ] Group messaging (shared group key)

### v0.3 — Mixnet Properties
- [ ] Random forwarding delays (configurable exponential distribution)
- [ ] Message reordering at each hop
- [ ] Local DHT mutation while charging (cover traffic without transmission)
- [ ] DHT state reshuffling — re-encryption, key rotation, fragment redistribution

### v0.4 — SMS Bridge
- [ ] SMS gateway integration (Twilio or similar)
- [ ] Encrypted message payloads over SMS
- [ ] Gateway phone concept: one device bridges SMS ↔ mesh for a community

### v0.5 — Android
- [ ] Android app using Google Nearby Connections API (replaces Loom)
- [ ] Shared encrypted message format across platforms
- [ ] Cross-platform testing (iPhone ↔ Android via DHT + Meshtastic)
- [ ] Testing on Tecno Spark / Infinix Hot devices
- [ ] Battery optimization for aggressive Android OEMs (Samsung, Xiaomi, Huawei)

### v0.6 — Kabala Field Research
- [ ] Visit Kabala — observe how people actually communicate today
- [ ] Identify the specific painful communication gap to solve first
- [ ] UX testing with community members
- [ ] Language localization (Krio, Kuranko)
- [ ] UI must be learnable by watching someone else use it for 60 seconds

### v1.0 — Kabala Pilot
- [ ] Field deployment in Kabala, Sierra Leone
- [ ] UX iteration based on real usage on real devices
- [ ] Community storage nodes deployed (old phones, Raspberry Pi)
- [ ] Message delivery reliability metrics
- [ ] Security audit by external reviewer

### Future Considerations (post v1.0)
- Threshold encryption (Seal/Sui) for trustless identity
- USSD bridge for feature phones
- Ultrasonic audio data transfer
- NFC tap-to-exchange message bundles
- Vehicle/movement-based relay optimization
- Burning Man deployment and cross-subsidization model
- IR blaster data transfer (budget Android phones)
- TV white space for extended range

## 10. Open Questions

1. **libsignal vs custom double ratchet** — libsignal is proven but heavy and C-based. A lightweight Swift implementation is possible but risky to get wrong. Needs security review either way.
2. **Loom identity ↔ app identity** — Loom uses P-256 in iCloud Keychain. Should we reuse Loom's identity as the app identity, or maintain separate keys?
3. **LoRa message size constraints** — Meshtastic payloads max ~237 bytes. Encrypted messages with double ratchet headers may exceed this. Fragmentation strategy needed.
4. **Background BLE on iOS** — CoreBluetooth background modes exist but are restricted. How reliable is passive message relay when the app isn't foregrounded?
5. **DHT bootstrap** — In a fully P2P system, how does a brand new device find its first DHT peers? Likely needs a small set of well-known bootstrap nodes (can be community-run).
6. **Spam without a central moderator** — rate limiting tied to identity, proof of work, web of trust for filtering. Study Scuttlebutt's approach.
7. **Message expiry policy** — How long do relay nodes hold fragments? Too short and messages don't arrive. Too long and storage fills up on cheap phones.

## 11. Pre-Build Checklist

### Security
- [ ] Find a security audit partner **before writing any cryptographic code** — reach out to Briar team, Signal Foundation, academic researchers (MIT, Stanford, UCL)
- [ ] Open source the core protocol and apps (after initial security review)

### Legal & Regulatory
- [ ] Consult a lawyer who understands technology and African telecommunications law
- [ ] Research Sierra Leone's laws around encrypted communication
- [ ] Understand licensing requirements for operating a communication network
- [ ] Assess regulatory implications of mixnet architecture designed to defeat surveillance

### Governance
- [ ] Consider a foundation model (Tor Project, Signal Foundation) rather than a company
- [ ] Plan for bus factor — if the founder is unavailable, the network must keep working
- [ ] Define: if the community's needs diverge from the vision, who wins? (The community.)

### Sustainability
- [ ] Burning Man cross-subsidization: ~70,000 attendees × reasonable fee = meaningful revenue
- [ ] Explore: outdoor recreation, disaster preparedness, maritime communication as paying markets
- [ ] Grant funding: GSMA Mobile for Development, Mozilla Foundation, Shuttleworth Foundation, USAID, Gates Foundation
- [ ] Marginal cost per user is near zero (no servers) — but development needs funding

### Partnerships
- [ ] Meshtastic community — hardware expertise, existing Burning Man deployments
- [ ] GSMA Mobile for Development — funding, telecom relationships
- [ ] Mozilla Foundation — open source privacy technology credibility
- [ ] Local organizations in Kabala — NGOs and civil society for distribution and trust
- [ ] Academic partners — UCL, MIT, Stanford groups working on adjacent problems

### Operational Security
- [ ] Development infrastructure is a target if the tool is used by activists
- [ ] Communications with users in sensitive contexts must be secure
- [ ] Personal threat model for the developer

## 12. Principles

1. **Every phone is a server.** No central infrastructure. The network is the people.
2. **Offline is the default, not the exception.** Online is just a faster pipe.
3. **The user never thinks about transport.** Messages just arrive.
4. **Security is structural, not behavioral.** Privacy emerges from the design, not from users making good choices.
5. **Start with real people.** Build for Kabala first, generalize second.
6. **Simplest thing that works.** No blockchain until we need blockchain. No LoRa until Bluetooth isn't enough.
7. **The community owns the network.** No company can shut it down, change the terms, monetize the data, or hand it to governments.
8. **Learnable in 60 seconds.** If someone can't learn the app by watching another person use it, the UX has failed.
