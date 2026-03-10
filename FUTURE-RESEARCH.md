# Zero Connect — Future Research

> Ideas, architectures, and privacy mechanisms that are worth exploring after the core product is proven. None of this is needed for v1. All of it requires validation, formal analysis, or both.

This document captures research directions from the design process. These are hypotheses and possibilities — not commitments or claims.

---

## 1. Fully Distributed P2P Architecture

### Every Phone as a Server

The long-term vision: no central infrastructure at all. Every phone is simultaneously a client, relay, and server. The network cannot be shut down without shutting down every device.

This means:
- Nothing to seize or subpoena
- No single point of failure
- No server costs
- The community owns the network

**Precedent:** BitTorrent has operated this way for 20+ years and has proven essentially impossible to shut down.

**Why it's not in v1:** Store-and-forward between directly connected peers is much simpler and solves the immediate problem. Full P2P with distributed storage adds significant complexity (DHT bootstrap, spam, storage management on cheap phones) without clear benefit for the primary use case.

### Kademlia DHT for Message Storage

Messages could be stored and routed through a Kademlia DHT — the same algorithm used by BitTorrent and Ethereum.

- Messages pushed into the DHT where recipients can find them
- Any device with internet becomes a bridge — flushes local messages into the DHT
- Recipient queries the DHT when they get connectivity
- No central server needed

**Open questions:**
- DHT bootstrap: how does a new device find its first peers? Likely needs community-run bootstrap nodes, which partially reintroduces infrastructure.
- Storage on $50 phones: DHT participation requires storing other people's data. Storage is limited.
- Spam/sybil: free identity creation + no central authority = attractive target.

### Secure Scuttlebutt as a Model

The closest existing system to what we're building. Fully P2P, works offline, syncs when devices meet, no central server. Used by sailing and off-grid communities.

Key concept: **append-only logs**. Each user has a personal log of messages, cryptographically signed. Other devices store copies of logs they're interested in. When two devices meet, they compare and sync missing entries. This is a CRDT (Conflict-free Replicated Data Type).

Scuttlebutt's weaknesses: no transport hierarchy, no LoRa/SMS fallback, technical UX, cold start/bootstrap struggles.

**Recommendation:** Study Scuttlebutt deeply, especially its replication model, before implementing any DHT layer.

---

## 2. Privacy & Metadata Resistance

### The Observation

Delay-tolerant delivery can improve privacy as well as reliability. When messages move opportunistically across time, transports, and relays, timing and path information become less direct than in always-online client-server systems.

This does not automatically provide mixnet-grade anonymity, but it may materially reduce some forms of traffic analysis if designed carefully. **This requires formal analysis and empirical testing — it is a hypothesis, not a proven property.**

### Mixnet Properties

Each device could act as a mix node:

1. Receive messages from multiple sources
2. Hold them for a random interval (exponential distribution)
3. Reorder the queue
4. Forward through the best available transport

In a fully distributed system, there would be no distinguished mixnet infrastructure — no list of mix nodes to block or monitor.

**Important caveats:**
- Kademlia routing is not onion routing. Intermediate DHT nodes learn structural information.
- "The DHT is the mixnet" is an appealing claim but has not been formally established.
- Random delay in an intermittently connected mesh gives some metadata protection, but the degree of protection against a sophisticated adversary is unknown without formal analysis.
- Nearby observations, bridge behavior, and endpoint compromise remain important risks regardless.

### Cover Traffic via Local DHT Mutation

**Hypothesis:** Instead of constantly transmitting fake messages (expensive on battery/bandwidth), devices could continuously reshuffle their local DHT state while charging:

- Re-encrypt stored fragments with fresh ephemeral keys
- Rotate DHT keyspace responsibilities
- Compute new routing table entries
- Pre-compute encrypted fragments

None of this requires radio transmission. When the device does sync with a neighbor, the transmitted state looks completely different from the last sync — even if no real messages were sent.

**The analogy:** A card dealer shuffling between hands. The shuffle is silent. When cards are dealt, the arrangement has no relationship to the previous hand.

**Battery-aware tuning:**

| Device State | Local Mutation | Transmission |
|-------------|---------------|--------------|
| Plugged in, charging | Maximum reshuffling | Normal sync schedule |
| Good battery | Moderate | Normal sync |
| Low battery | Minimal | Sync only when necessary |
| Critical battery | None | Real messages only |

**Status:** Interesting idea. Not validated. Needs simulation and adversary modeling to determine if it materially helps against realistic radio-level observers, and whether the battery/storage cost is acceptable on low-end Android.

### Message Fragmentation Across Nodes

Messages could be split into fragments distributed across the DHT:
- No single device holds a complete message
- Seizing one phone reveals nothing
- Only the recipient can reassemble fragments

**Why it's deferred:**
- Significantly complicates delivery reliability
- Inflates metadata and coordination cost
- Makes small-payload transports (LoRa, ~237 bytes) much harder
- Adds failure modes before we know if users need it
- Relay compromise is often less important than endpoint compromise

**Recommendation:** Use whole encrypted message objects in v1. Revisit fragmentation only if field evidence shows relay compromise or storage seizure is a real threat.

### Threat Model Summary (Research Targets)

| Threat | Current Status | Research Goal |
|--------|---------------|---------------|
| Content interception | Strong (E2E encryption) | Maintain |
| Casual surveillance | Strong (local transport) | Maintain |
| Metadata analysis | Partial (reduced by local transport) | Quantify through formal analysis |
| Traffic correlation | Unknown | Model against specific adversary capabilities |
| Social graph inference | Unknown | Evaluate what nearby observation reveals |
| Global passive adversary | Unproven | Requires academic collaboration and formal proofs |

---

## 3. Extended Transports

### SMS Gateway Bridge
- One device in a community bridges SMS ↔ mesh
- Encrypted payloads over SMS
- Twilio or similar gateway service
- Cost: fractions of a cent per message at volume
- **Concern:** SMS changes the trust and threat model significantly (SS7 vulnerabilities, carrier interception)

### USSD Bridge for Feature Phones
- USSD (`*#123#` type codes) works on any GSM phone, no smartphone required
- Some African developers have built banking and messaging on USSD
- Could extend the network to people who can't afford smartphones
- Nearly instant, works in extremely weak signal conditions

### NFC Tap-to-Exchange
- Two phones tap to exchange message bundles
- Instant, offline, no radio configuration needed
- Already in every modern phone
- Could be used for both contact exchange and message relay

### Ultrasonic Audio
- Phones use speakers/microphones to pass small data packets
- Inaudible to humans, works across a room
- Companies like Chirp have built SDKs for this
- Requires zero hardware beyond what's already in every phone

### IR Blaster
- Many budget Android phones (Xiaomi, Blackview) have IR blasters
- Originally for TV remotes but could carry data
- Hundreds of millions of phones have this and nobody uses it for networking

### TV White Space
- Unused broadcast TV frequencies
- Longer range than LoRa in some conditions
- Microsoft has piloted this in rural Africa specifically

### Vehicle/Movement Relay Optimization
- Predictable daily routes (market days, school runs, water collection) could be modeled
- Vehicles (taxis, trucks) moving between villages become automatic message carriers
- Could dramatically reduce delivery latency with zero infrastructure

---

## 4. Advanced Encryption

### Double Ratchet Protocol
- Used by Signal for a decade, open source, well understood
- Forward secrecy: compromise of one key doesn't expose past/future messages
- **Complexity in delay-tolerant context:** ratchets get tricky with long offline gaps, duplicate delivery, out-of-order messages, and tiny LoRa payloads. Needs careful design.

### Group Messaging
- Group has its own keypair
- Group private key encrypted to each member's public key
- Adding someone: encrypt group key to their public key
- Removing someone: rotate the group key and redistribute
- Can work mostly offline; key distribution travels over the mesh

### Threshold Encryption (Seal/Sui)
- Mysten Labs' Seal: decentralized threshold encryption on Sui blockchain
- No single party controls access to encrypted data
- Could provide trustless identity without a central server
- **Why deferred:** adds blockchain dependency, requires occasional internet for key management, adds complexity that primary users don't need. Revisit if trustless identity verification becomes a requirement.

### Device Compromise Mitigations
- **Message expiry** — old messages delete automatically
- **Key deletion after decryption** — once read, decryption key is destroyed
- **Forward secrecy** — old keys can't decrypt new messages
- **Panic wipe** — hidden gesture wipes all keys instantly

---

## 5. Governance & Sustainability

### Governance Models
- Consider a foundation model (Tor Project, Signal Foundation) rather than a company
- Plan for bus factor — if the founder is unavailable, the network must keep working
- Open source the protocol and apps
- If the community's needs diverge from the vision, the community wins

### Sustainability
- **Burning Man cross-subsidization:** ~70,000 attendees × reasonable fee = meaningful annual revenue
- **Paying markets:** outdoor recreation, disaster preparedness, maritime communication
- **Grant funding:** GSMA Mobile for Development, Mozilla Foundation, Shuttleworth Foundation, USAID, Gates Foundation
- **Marginal cost per user is near zero** (no servers) — but development needs funding

### Legal & Regulatory
- Sierra Leone and many African countries have vague, selectively enforced laws around encrypted communication
- Operating a communication network may require licensing
- Mixnet architecture specifically may attract regulatory attention
- Need a lawyer who understands both technology and African telecommunications law

### Operational Security
- Development infrastructure becomes a target if the tool is used by activists
- Communications with users in sensitive contexts must be secure
- Personal threat model for the developer

### Partnerships (Future)
- GSMA Mobile for Development — funding, telecom relationships
- Mozilla Foundation — open source privacy technology credibility
- Academic partners (UCL, MIT, Stanford) — security review, formal analysis, research collaboration
- Shuttleworth Foundation — fellowship funding for open source social impact projects
