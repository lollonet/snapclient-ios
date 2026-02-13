# WBS: Riscrittura Client Audio Snapcast in Swift Puro

> **Obiettivo**: Eliminare la dipendenza GPL3 dal core C++ di Snapcast, reimplementando il client audio in Swift puro per permettere la vendita su App Store.

---

## 1. ARCHITETTURA TARGET

```
┌─────────────────────────────────────────────────────────────────┐
│                        SnapClient App                           │
│                         (SwiftUI)                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ PlayerView      │  │ GroupsView      │  │ SettingsView    │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │           │
│           └────────────────────┼────────────────────┘           │
│                                │                                │
├────────────────────────────────┼────────────────────────────────┤
│                     SnapClientEngine                            │
│              (Orchestrator - già esistente)                     │
├────────────────────────────────┼────────────────────────────────┤
│                                │                                │
│  ┌─────────────────────────────┼─────────────────────────────┐  │
│  │                   NUOVO: Audio Core                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │  │
│  │  │ StreamClient │  │  ClockSync   │  │ AudioPlayer  │    │  │
│  │  │  (TCP 1704)  │  │  (NTP-like)  │  │(AVAudioEngine│    │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │  │
│  │         │                 │                 │             │  │
│  │  ┌──────┴─────────────────┴─────────────────┴──────┐     │  │
│  │  │              PlayoutBuffer                       │     │  │
│  │  │        (Jitter buffer + resampling)             │     │  │
│  │  └──────────────────────┬──────────────────────────┘     │  │
│  │                         │                                 │  │
│  │  ┌──────────────────────┴──────────────────────────┐     │  │
│  │  │              AudioDecoder                        │     │  │
│  │  │         (FLAC / PCM / Opus)                     │     │  │
│  │  └─────────────────────────────────────────────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐                      │
│  │ SnapcastRPC     │  │ ServerDiscovery │  ← GIÀ SWIFT PURO   │
│  │ Client (1780)   │  │ (mDNS/Bonjour)  │                      │
│  └─────────────────┘  └─────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. WBS - WORK BREAKDOWN STRUCTURE

### Livello 0: Progetto
```
1.0 SNAPCLIENT-IOS SWIFT AUDIO CORE
```

### Livello 1: Work Packages principali

| WP | Nome | Descrizione |
|----|------|-------------|
| 1.1 | Protocol Layer | Implementazione protocollo binario Snapcast |
| 1.2 | Clock Synchronization | Sistema di sincronizzazione temporale |
| 1.3 | Audio Decoding | Decoder per codec supportati |
| 1.4 | Playout System | Buffer management e audio output |
| 1.5 | Engine Integration | Integrazione con SnapClientEngine esistente |
| 1.6 | Testing & Validation | Test e validazione sync |
| 1.7 | Cleanup & Release | Rimozione codice GPL, preparazione release |

---

## 3. WBS DETTAGLIATA

### 1.1 PROTOCOL LAYER

#### 1.1.1 Message Types
Definizione strutture dati per i messaggi del protocollo.

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.1.1.1 | Definire `SnapMessage` base struct | Documentazione protocollo | `SnapMessage.swift` |
| 1.1.1.2 | Implementare `BaseHeader` (26 byte) | Spec protocollo | Struct con parsing |
| 1.1.1.3 | Implementare `HelloMessage` (type 5) | Spec + JSON schema | Encoder/Decoder |
| 1.1.1.4 | Implementare `ServerSettingsMessage` (type 3) | Spec | Decoder |
| 1.1.1.5 | Implementare `CodecHeaderMessage` (type 1) | Spec | Decoder |
| 1.1.1.6 | Implementare `WireChunkMessage` (type 2) | Spec | Decoder |
| 1.1.1.7 | Implementare `TimeMessage` (type 4) | Spec | Encoder/Decoder |

**Struttura header (26 byte, little-endian):**
```
Offset  Size  Field
0       2     type (uint16)
2       2     id (uint16)
4       2     refersTo (uint16)
6       4     sent.sec (int32)
10      4     sent.usec (int32)
14      4     received.sec (int32)
18      4     received.usec (int32)
22      4     size (uint32)
```

#### 1.1.2 Stream Client
Client TCP per connessione al server (porta 1704).

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.1.2.1 | Creare `SnapStreamClient` class | - | Classe base |
| 1.1.2.2 | Implementare connessione TCP via `NWConnection` | Host, Port | Connection |
| 1.1.2.3 | Implementare send Hello on connect | ClientInfo | Hello message |
| 1.1.2.4 | Implementare receive loop | Connection | Message stream |
| 1.1.2.5 | Implementare message parsing | Raw data | Typed messages |
| 1.1.2.6 | Implementare reconnection logic | - | Auto-reconnect |
| 1.1.2.7 | Gestire errori di connessione | Errors | State updates |

#### 1.1.3 Message Serialization

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.1.3.1 | Helper per lettura little-endian da `Data` | Data | Int/UInt values |
| 1.1.3.2 | Helper per scrittura little-endian a `Data` | Values | Data |
| 1.1.3.3 | Unit test serialization round-trip | - | Tests |

---

### 1.2 CLOCK SYNCHRONIZATION

#### 1.2.1 Time Provider
Sistema per ottenere tempo ad alta precisione.

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.2.1.1 | Wrapper per `mach_absolute_time()` | - | `TimeProvider.swift` |
| 1.2.1.2 | Conversione a microsecondi | mach_time | Microseconds |
| 1.2.1.3 | Conversione a `timeval` (sec + usec) | Microseconds | Timeval |
| 1.2.1.4 | Benchmark precisione | - | Validation |

#### 1.2.2 Clock Sync Algorithm
Implementazione algoritmo NTP-like di Snapcast.

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.2.2.1 | Creare `ClockSync` class | - | Classe base |
| 1.2.2.2 | Implementare invio Time request | TimeProvider | Time message |
| 1.2.2.3 | Implementare ricezione Time response | Response | Latency values |
| 1.2.2.4 | Calcolare `time_diff` server-client | Timestamps | Offset |
| 1.2.2.5 | Implementare media mobile (smoothing) | Raw offsets | Smoothed offset |
| 1.2.2.6 | Gestire outlier filtering | Samples | Filtered samples |
| 1.2.2.7 | Implementare sync interval (ogni ~1 sec) | - | Timer |

**Algoritmo di sync:**
```
t1 = client_send_time
t2 = server_recv_time  (dal response)
t3 = server_send_time  (dal response)
t4 = client_recv_time

latency = ((t4 - t1) - (t3 - t2)) / 2
time_diff = ((t2 - t1) + (t3 - t4)) / 2
```

#### 1.2.3 Drift Compensation

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.2.3.1 | Rilevare drift clock | Time series | Drift rate |
| 1.2.3.2 | Calcolare resampling ratio | Drift | Ratio |
| 1.2.3.3 | Applicare correzione graduale | Ratio | Adjusted playback |

---

### 1.3 AUDIO DECODING

#### 1.3.1 Codec Abstraction

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.3.1.1 | Definire `AudioDecoder` protocol | - | Protocol |
| 1.3.1.2 | Definire `AudioFormat` struct | Codec header | Format info |
| 1.3.1.3 | Definire `DecodedAudio` struct | - | PCM samples |

```swift
protocol AudioDecoder {
    func initialize(codecHeader: Data) throws
    func decode(chunk: Data) throws -> DecodedAudio
    var format: AudioFormat { get }
}

struct AudioFormat {
    let sampleRate: Int      // e.g. 48000
    let channels: Int        // e.g. 2
    let bitsPerSample: Int   // e.g. 16
}

struct DecodedAudio {
    let samples: [Float]     // Interleaved PCM
    let timestamp: UInt64    // Playout timestamp (usec)
}
```

#### 1.3.2 PCM Decoder (Passthrough)

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.3.2.1 | Implementare `PCMDecoder` | - | Class |
| 1.3.2.2 | Parsing header PCM | Codec header | Format |
| 1.3.2.3 | Conversione Int16 → Float | Raw PCM | Float samples |
| 1.3.2.4 | Conversione Int24 → Float | Raw PCM | Float samples |
| 1.3.2.5 | Conversione Int32 → Float | Raw PCM | Float samples |

#### 1.3.3 FLAC Decoder

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.3.3.1 | Integrare libFLAC (BSD license) | - | XCFramework |
| 1.3.3.2 | Creare bridge C per libFLAC | - | `flac_bridge.h` |
| 1.3.3.3 | Implementare `FLACDecoder` Swift wrapper | Bridge | Class |
| 1.3.3.4 | Inizializzare decoder con stream info | Codec header | Decoder state |
| 1.3.3.5 | Decodificare frame FLAC | Encoded data | PCM samples |
| 1.3.3.6 | Gestire errori decoding | Errors | Recovery |

#### 1.3.4 Opus Decoder (Opzionale)

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.3.4.1 | Integrare libopus (BSD license) | - | XCFramework |
| 1.3.4.2 | Creare bridge C per libopus | - | `opus_bridge.h` |
| 1.3.4.3 | Implementare `OpusDecoder` Swift wrapper | Bridge | Class |
| 1.3.4.4 | Decodificare frame Opus | Encoded data | PCM samples |

#### 1.3.5 Decoder Factory

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.3.5.1 | Implementare `DecoderFactory` | Codec name | Decoder instance |
| 1.3.5.2 | Auto-detect codec da header | Codec header | Codec type |

---

### 1.4 PLAYOUT SYSTEM

#### 1.4.1 Jitter Buffer

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.4.1.1 | Creare `JitterBuffer` class | Buffer size | Class |
| 1.4.1.2 | Implementare insert (by timestamp) | DecodedAudio | - |
| 1.4.1.3 | Implementare retrieve (by playout time) | Current time | Audio chunk |
| 1.4.1.4 | Gestire buffer underrun (silenzio) | - | Zero samples |
| 1.4.1.5 | Gestire buffer overrun (drop old) | - | Trimmed buffer |
| 1.4.1.6 | Calcolare statistiche buffer | - | Fill level, latency |

**Parametri buffer:**
```
DEFAULT_BUFFER_MS = 1000  // Buffer totale
TARGET_LATENCY_MS = 200   // Latenza target
MIN_LATENCY_MS = 100      // Minimo prima di underrun
```

#### 1.4.2 Resampler

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.4.2.1 | Implementare resampler lineare semplice | Samples, ratio | Resampled |
| 1.4.2.2 | Implementare resampler Sinc (qualità) | Samples, ratio | Resampled |
| 1.4.2.3 | Gestire ratio variabile (drift) | Drift rate | Adjusted ratio |

#### 1.4.3 AVAudioEngine Pipeline

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.4.3.1 | Creare `AudioPlayer` class | - | Class |
| 1.4.3.2 | Setup AVAudioEngine | - | Engine |
| 1.4.3.3 | Setup AVAudioPlayerNode | - | Player node |
| 1.4.3.4 | Configurare AVAudioFormat | AudioFormat | AVFormat |
| 1.4.3.5 | Implementare scheduleBuffer loop | JitterBuffer | Playback |
| 1.4.3.6 | Calcolare playout time preciso | Clock sync | Schedule time |
| 1.4.3.7 | Gestire buffer callback | - | Refill trigger |

**Pipeline AVAudioEngine:**
```
[JitterBuffer] → [AVAudioPlayerNode] → [AVAudioEngine mainMixerNode] → [Output]
```

#### 1.4.4 Audio Session Management

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.4.4.1 | Configurare AVAudioSession category | - | .playback |
| 1.4.4.2 | Configurare mode | - | .default |
| 1.4.4.3 | Configurare options | - | .mixWithOthers |
| 1.4.4.4 | Gestire interruzioni (chiamate) | Notification | Pause/Resume |
| 1.4.4.5 | Gestire route changes (cuffie) | Notification | Adapt |
| 1.4.4.6 | Abilitare background audio | Info.plist | Background mode |

---

### 1.5 ENGINE INTEGRATION

#### 1.5.1 Refactor SnapClientEngine

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.5.1.1 | Rimuovere dipendenza da C bridge | - | Swift-only |
| 1.5.1.2 | Creare `SnapAudioCore` class | - | New core |
| 1.5.1.3 | Integrare SnapStreamClient | - | Connection |
| 1.5.1.4 | Integrare ClockSync | - | Sync |
| 1.5.1.5 | Integrare AudioDecoder | - | Decoding |
| 1.5.1.6 | Integrare AudioPlayer | - | Playback |
| 1.5.1.7 | Wire up callbacks e state | - | State machine |

#### 1.5.2 State Machine

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.5.2.1 | Definire stati (disconnected, connecting, syncing, playing) | - | Enum |
| 1.5.2.2 | Definire transizioni valide | - | State machine |
| 1.5.2.3 | Implementare transitions | Events | State changes |

```
[Disconnected] ──connect──> [Connecting] ──hello_ack──> [Syncing]
                                │                          │
                                │                          │ sync_ok
                                │                          ↓
                           [Error] <───────────────── [Playing]
                                │                          │
                                └──────── retry ───────────┘
```

#### 1.5.3 Settings Sync

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.5.3.1 | Applicare volume da server | ServerSettings | Volume |
| 1.5.3.2 | Applicare mute da server | ServerSettings | Mute |
| 1.5.3.3 | Applicare latency da server | ServerSettings | Latency offset |
| 1.5.3.4 | Inviare volume changes al server | User action | ClientInfo msg |

---

### 1.6 TESTING & VALIDATION

#### 1.6.1 Unit Tests

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.6.1.1 | Test message parsing | Sample data | Assertions |
| 1.6.1.2 | Test message serialization | Structs | Byte validation |
| 1.6.1.3 | Test clock sync math | Mock timestamps | Offset validation |
| 1.6.1.4 | Test jitter buffer | Mock audio | Order validation |
| 1.6.1.5 | Test decoder (PCM) | Raw PCM | Float validation |
| 1.6.1.6 | Test decoder (FLAC) | FLAC frames | PCM validation |

#### 1.6.2 Integration Tests

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.6.2.1 | Test connessione a server reale | Snapserver | Connection |
| 1.6.2.2 | Test ricezione audio | Stream | Audio chunks |
| 1.6.2.3 | Test playback end-to-end | Server | Sound output |

#### 1.6.3 Sync Validation

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.6.3.1 | Setup multi-client test | 2+ devices | Test env |
| 1.6.3.2 | Misurare offset tra client | Audio recording | Offset ms |
| 1.6.3.3 | Validare sync < 5ms | Measurements | Pass/Fail |
| 1.6.3.4 | Test stabilità su 1h | Long run | Drift report |

---

### 1.7 CLEANUP & RELEASE

#### 1.7.1 Remove C++ Dependencies

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.7.1.1 | Rimuovere `SnapClientCore/` directory | - | Deleted |
| 1.7.1.2 | Rimuovere `snapclient_bridge.h` | - | Deleted |
| 1.7.1.3 | Rimuovere CMakeLists.txt | - | Deleted |
| 1.7.1.4 | Rimuovere script di build C++ | - | Deleted |
| 1.7.1.5 | Aggiornare project.yml | - | Swift-only |
| 1.7.1.6 | Rimuovere riferimenti GPL da docs | - | Updated |

#### 1.7.2 License Update

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.7.2.1 | Verificare licenze dipendenze | libFLAC, libopus | Compatibility |
| 1.7.2.2 | Aggiornare LICENSE file | - | MIT + notices |
| 1.7.2.3 | Aggiungere THIRD_PARTY_LICENSES | - | Attribution |
| 1.7.2.4 | Aggiornare README | - | New architecture |

#### 1.7.3 App Store Preparation

| Task | Descrizione | Input | Output |
|------|-------------|-------|--------|
| 1.7.3.1 | Verificare compliance App Store | Guidelines | Checklist |
| 1.7.3.2 | Preparare privacy manifest | - | PrivacyInfo.xcprivacy |
| 1.7.3.3 | Preparare screenshots | App | Assets |
| 1.7.3.4 | Scrivere App Store description | - | Metadata |
| 1.7.3.5 | TestFlight beta | - | Beta build |

---

## 4. DIPENDENZE TRA WORK PACKAGES

```
1.1 Protocol Layer ─────────────────────────────────────────┐
         │                                                   │
         ↓                                                   │
1.2 Clock Sync ──────────────────────────┐                  │
         │                               │                  │
         ↓                               ↓                  ↓
1.3 Audio Decoding ──────────────> 1.4 Playout System ─────>│
                                         │                  │
                                         ↓                  │
                                  1.5 Engine Integration <──┘
                                         │
                                         ↓
                                  1.6 Testing
                                         │
                                         ↓
                                  1.7 Cleanup & Release
```

---

## 5. DELIVERABLES PER WORK PACKAGE

| WP | Deliverable | File/Artifact |
|----|-------------|---------------|
| 1.1 | Protocol implementation | `SnapClient/Audio/Protocol/*.swift` |
| 1.2 | Clock sync system | `SnapClient/Audio/Sync/*.swift` |
| 1.3 | Audio decoders | `SnapClient/Audio/Codec/*.swift` |
| 1.4 | Playout system | `SnapClient/Audio/Player/*.swift` |
| 1.5 | Integrated engine | `SnapClient/Engine/SnapAudioCore.swift` |
| 1.6 | Test suite | `SnapClientTests/Audio/*.swift` |
| 1.7 | Release-ready app | App Store build |

---

## 6. STRUTTURA DIRECTORY PROPOSTA

```
SnapClient/
├── App/
│   └── SnapClientApp.swift
├── Audio/                          ← NUOVO
│   ├── Protocol/
│   │   ├── SnapMessage.swift
│   │   ├── MessageTypes.swift
│   │   └── SnapStreamClient.swift
│   ├── Sync/
│   │   ├── TimeProvider.swift
│   │   └── ClockSync.swift
│   ├── Codec/
│   │   ├── AudioDecoder.swift
│   │   ├── PCMDecoder.swift
│   │   ├── FLACDecoder.swift
│   │   └── OpusDecoder.swift
│   ├── Player/
│   │   ├── JitterBuffer.swift
│   │   ├── Resampler.swift
│   │   └── AudioPlayer.swift
│   └── SnapAudioCore.swift
├── Control/
│   └── SnapcastRPCClient.swift     ← ESISTENTE
├── Discovery/
│   └── ServerDiscovery.swift       ← ESISTENTE
├── Engine/
│   └── SnapClientEngine.swift      ← REFACTORED
└── Views/
    └── ...                         ← ESISTENTE

Libs/                               ← NUOVO (BSD licensed)
├── libFLAC.xcframework
└── libopus.xcframework
```

---

## 7. RISCHI E MITIGAZIONI

| Rischio | Probabilità | Impatto | Mitigazione |
|---------|-------------|---------|-------------|
| Clock sync non preciso | Media | Alto | Test estensivi, confronto con client C++ |
| Glitch audio | Media | Alto | Buffer sizing, resampler quality |
| Performance insufficiente | Bassa | Medio | Profiling, ottimizzazione hot path |
| libFLAC integration issues | Bassa | Medio | Fallback a PCM-only inizialmente |
| App Store rejection | Bassa | Alto | Seguire guidelines, no private API |

---

## 8. PRIORITÀ IMPLEMENTAZIONE

### Fase 1: MVP (Audio funzionante)
1. 1.1.1 - Message Types
2. 1.1.2 - Stream Client
3. 1.3.2 - PCM Decoder (più semplice)
4. 1.4.3 - AVAudioEngine Pipeline
5. 1.2.1 - Time Provider
6. 1.2.2 - Clock Sync (base)

### Fase 2: Qualità audio
1. 1.3.3 - FLAC Decoder
2. 1.4.1 - Jitter Buffer
3. 1.4.2 - Resampler
4. 1.2.3 - Drift Compensation

### Fase 3: Production ready
1. 1.5 - Engine Integration
2. 1.6 - Testing completo
3. 1.7 - Cleanup e release

---

## 9. NOTE TECNICHE

### Clock Sync - Dettagli implementativi

Il server invia `WireChunk` con timestamp di quando l'audio dovrebbe essere riprodotto:
```
chunk.timestamp = server_time + buffer_ms
```

Il client deve:
1. Calcolare `time_diff` tra clock server e client
2. Convertire `chunk.timestamp` in tempo locale: `local_playout_time = chunk.timestamp - time_diff`
3. Schedulare il buffer in AVAudioEngine per quel tempo preciso

### AVAudioEngine scheduling

```swift
// Calcola il tempo di playout
let playoutHostTime = mach_absolute_time() + deltaTicks
let playoutTime = AVAudioTime(hostTime: playoutHostTime)

// Schedula il buffer
playerNode.scheduleBuffer(buffer, at: playoutTime, options: [])
```

### Latenza tipiche
- Network latency: 1-5ms (LAN)
- Jitter buffer: 20-50ms
- AVAudioEngine buffer: 5-20ms
- **Totale: ~50-100ms** (accettabile per sync multi-room)
