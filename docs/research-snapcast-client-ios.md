# Research: Snapcast Client iOS (Snap.Net)

> App Store: https://apps.apple.com/it/app/snapcast-client/id1552559653
> Source code: https://github.com/stijnvdb88/Snap.Net

## Informazioni generali

| Campo | Dettaglio |
|-------|-----------|
| **Nome** | Snapcast Client |
| **Sviluppatore** | Stijn Van der Borght |
| **Prezzo** | $0.99 (€0.99) |
| **Versione attuale** | 0.26.0 |
| **Ultimo aggiornamento** | 19 settembre 2022 |
| **Disponibile dal** | Febbraio 2021 |
| **Dimensione** | 53.12 MB |
| **Compatibilità** | iOS 8.0+, macOS 11.0+ (Apple Silicon) |
| **Valutazione** | 2.83/5 (6 recensioni) |
| **Licenza sorgente** | GPL-3.0 |
| **Privacy** | Lo sviluppatore non raccoglie dati |
| **Family Sharing** | Sì, fino a 6 membri |

## Cos'è

Snapcast Client è un **port iOS di snapclient** sviluppato come parte del progetto Snap.Net. Non è un player standalone: richiede un Snapserver attivo nella rete locale. L'app trasforma un dispositivo iOS in un client Snapcast sincronizzato, permettendo di:

1. **Riprodurre audio** — il dispositivo iOS diventa un endpoint audio Snapcast
2. **Controllare altri client** — gestire volumi, gruppi e latenza di tutti i client connessi al server

## Funzionalità principali

### Riproduzione audio
- Il dispositivo iOS funziona come un vero snapclient
- Supporta il codec FLAC (default di Snapcast)
- Riproduzione in background (l'audio continua anche con l'app minimizzata)
- Integrazione con i controlli media di iOS (Control Center, lock screen)
- Funziona anche via VPN (cellulare → VPN → rete domestica) senza skip

### Controllo server
- Visualizzazione e gestione di tutti i client connessi al server
- Raggruppamento dei client (grouping)
- Assegnazione nomi ai gruppi
- Regolazione del volume per singolo client
- Regolazione della latenza per client
- Visualizzazione di tutti i dispositivi che si sono mai connessi al server

### Interfaccia
- Supporto Dark Mode nativo
- Temi e colori personalizzabili
- Interfaccia per gestione gruppi e client

## Architettura tecnica (Snap.Net)

Il progetto Snap.Net è composto da tre componenti:

### 1. Control Client
Interfaccia per gestire server e client Snapcast. Comunica via **JSON-RPC** sulla porta **1780** del Snapserver.

### 2. SnapClient Library
Port .NET del binario snapclient nativo. Permette di ricevere e riprodurre lo stream audio sincronizzato.

### 3. Broadcast Tool (solo Windows)
Permette di trasmettere l'audio del PC al Snapserver come sorgente.

### Stack tecnologico

| Componente | Tecnologia |
|------------|-----------|
| **Linguaggio** | C# (83.4% del codebase) |
| **Framework** | .NET / Xamarin (per iOS) |
| **Protocollo controllo** | JSON-RPC su TCP porta 1780 |
| **Protocollo audio** | TCP porta 1704 (stream FLAC) |
| **Codec supportato** | FLAC (default) |
| **Audio handling** | NAudio |
| **JSON-RPC** | StreamJsonRpc |
| **Codec FLAC** | Concentus |
| **Logging** | NLog |

### Piattaforme supportate da Snap.Net

| Piattaforma | Control Client | Player | Broadcast |
|-------------|---------------|--------|-----------|
| Windows | ✅ | ✅ | ✅ |
| iOS | ✅ | ✅ | ❌ |
| Android | ✅ | ✅ | ❌ |
| macOS | ❌ (planned) | ❌ | ❌ |
| Linux | ❌ (planned) | ❌ | ❌ |

## Stato del progetto

- **204 commit** nel repository
- **2 contributori** attivi
- **26 release** (ultima: v0.34.0.0, ottobre 2025)
- L'app iOS è ferma alla **v0.26.0** (settembre 2022) — quasi 3.5 anni senza aggiornamenti
- Il repository desktop (Windows) è più attivo

## Punti di forza

- Unico client iOS ufficiale per Snapcast disponibile su App Store
- Funziona sia come player che come controller
- Riproduzione in background funzionante
- Supporto VPN per uso remoto
- Nessuna raccolta dati (privacy-friendly)
- Codice open source (GPL-3.0)
- Prezzo accessibile ($0.99)

## Criticità e limitazioni

- **App non aggiornata** da settembre 2022 (v0.26.0 vs v0.34.0 desktop)
- **Valutazione bassa** (2.83/5) suggerisce problemi di stabilità o UX
- **Solo codec FLAC** — nessun supporto per PCM, Opus, Vorbis
- **Requisito minimo iOS 8.0** dichiarato ma probabilmente non testato su versioni così vecchie
- **Nessun supporto macOS nativo** (solo via Apple Silicon compatibility)
- Il progetto Snap.Net è primariamente focalizzato su Windows

## Rilevanza per SnapForge

### Opportunità
L'app Snapcast Client rappresenta un complemento naturale all'ecosistema SnapForge:
- Permette di usare iPhone/iPad come **endpoint audio** aggiuntivi
- Fornisce un **controller mobile** per gestire il sistema SnapForge da smartphone
- È già compatibile con Snapserver (che è al cuore di snapMULTI)

### Gap identificati
- L'app non è mantenuta attivamente → rischio di incompatibilità future
- SnapForge non ha attualmente un client mobile proprio
- SnapCTRL è solo desktop (PySide6/Qt6) — non c'è equivalente mobile
- Manca documentazione su come configurare l'app iOS con snapMULTI

### Possibili azioni
1. **Documentare** l'integrazione di Snapcast Client iOS con snapMULTI nel QUICKSTART o DEPLOYMENT-GUIDE
2. **Testare** la compatibilità con la versione di Snapserver usata in snapMULTI (santcasp fork)
3. **Valutare** se sviluppare un client mobile SnapForge nativo (Flutter/React Native) come alternativa
4. **Monitorare** lo stato di manutenzione di Snap.Net per eventuali fork

---

## Valutazione aggiornamento client iOS alla versione corrente di Snapcast

### Gap versioni: iOS v0.26.0 → Snapcast v0.34.0

L'app iOS è ferma alla v0.26.0 (settembre 2022). Il protocollo Snapcast è alla v0.34.0 (ottobre 2025). Tra queste versioni ci sono **8 major release** con cambiamenti significativi.

#### Cambiamenti rilevanti per il client (0.26.0 → 0.34.0)

| Versione | Cambiamento | Impatto sul client iOS |
|----------|------------|----------------------|
| **0.26.0** | Nuove API Metadata e Control per stream | L'app le supporta (ultima versione) |
| **0.28.0** | Fix rumore da letture half-sample, miglior risoluzione IP | Bug fix, non breaking |
| **0.29.0** | Supporto audio 24-bit e 32-bit su Android | iOS non ne beneficia |
| **0.30.0** | HTTPS/WSS, fix CVE-2023-36177, rimosse AddStream/RemoveStream RPC | **Potenziale impatto** se l'app usa quelle API |
| **0.31.0** | Stream.AddStream reintrodotto (sicuro) | Compatibile |
| **0.32.0** | Supporto WebSocket client, deprecati `--host`/`--port` CLI | **WebSocket** è una feature significativa |
| **0.33.0** | Supporto PipeWire, mDNS disabilitabile, rinominata sezione config TCP | Impatto limitato sul client |
| **0.34.0** | Package per Raspberry Pi OS Trixie, bug fix | Nessun impatto diretto |

#### Compatibilità protocollo

Il protocollo audio di base TCP (porta 1704) **non ha avuto breaking change** tra 0.26 e 0.34. Il client iOS v0.26.0 può ancora connettersi a un server 0.34.0 per la riproduzione audio base. Le incompatibilità sono a livello di:

- **API JSON-RPC**: nuovi metodi (Stream.AddStream sicuro, Stream.Control, Stream.SetProperty) non disponibili nel client vecchio
- **WebSocket**: il server ora supporta WSS, ma il client iOS usa solo TCP raw
- **Sample format**: il client iOS **crasha** con formati diversi da 48kHz/16bit (issue #52)

### Stato del maintainer

Il maintainer (Stijn Van der Borght) ha dichiarato nell'issue #51:

> *"I don't have the required hardware right now, the Mac device I was using for development is now deemed too old by Apple and can't be used to make publishable builds anymore."*

Questo è il **blocco principale**: non è un problema di volontà ma di hardware. Il maintainer non può più compilare e pubblicare build iOS.

### Bug aperti critici sull'app iOS

| Issue | Problema | Gravità |
|-------|---------|---------|
| **#52** | Crash con sample format diverso da 48kHz default | Alta |
| **#53** | App non si connette al server | Alta |
| **#51** | Richiesta aggiornamento binari (senza risposta) | Media |
| **#46** | Stuttering audio dopo ore di riproduzione | Media |
| **#43** | Serve riconnessione manuale cambiando WiFi | Bassa |
| **#38** | Problemi discovery dispositivi | Media |

### Alternative esistenti per iOS

| Progetto | Linguaggio | Stato | Sincronizzazione | App Store |
|----------|-----------|-------|------------------|-----------|
| **Snap.Net** (attuale) | C# / Xamarin | Abbandonato (iOS) | Sì | Sì ($0.99) |
| **SnapClientIOS** | Obj-C / C | WIP, molto incompleto | No (non implementata) | No |
| **Snapweb** | JavaScript (browser) | Attivo, parte di Snapcast | No (browser limitation) | N/A (web) |

Non esiste alcun client iOS nativo in **Swift/SwiftUI**.

### Valutazione delle opzioni

#### Opzione 1: Fork di Snap.Net e aggiornamento iOS
**Fattibilità: Bassa**

- Il codebase è C# / Xamarin — tecnologia in fase di dismissione (Xamarin è stato sostituito da .NET MAUI)
- Richiede un Mac con Xcode aggiornato per build iOS
- Il client è un port .NET del protocollo Snapcast scritto quando era alla v0.14 — gap enorme
- Licenza GPL-3.0 obbliga a mantenere lo stesso modello open source
- Lo stuttering audio suggerisce problemi fondamentali con il timing .NET su iOS

**Effort stimato**: Alto. Essenzialmente un refactoring completo del layer Xamarin → MAUI, più aggiornamento protocollo.

#### Opzione 2: Client iOS nativo in Swift
**Fattibilità: Media-Alta**

- Swift + AVAudioEngine offrono controllo preciso sul timing audio
- SwiftUI per UI moderna e manutenibile
- Il protocollo Snapcast è relativamente semplice (TCP binary per audio, JSON-RPC per controllo)
- Nessun client Swift esiste → sarebbe il primo nell'ecosistema
- Richiede Apple Developer Account ($99/anno) per pubblicazione App Store

**Componenti da implementare**:
1. Parser protocollo binario Snapcast (header + chunk FLAC/PCM/Opus)
2. Decodifica FLAC (libreria C esistente, bridgeable)
3. Clock sync NTP-like (algoritmo documentato nel sorgente Snapcast)
4. Client JSON-RPC per controllo (relativamente semplice)
5. Audio output via AVAudioEngine con buffer management
6. mDNS discovery via Bonjour (nativo su iOS)

**Effort stimato**: Medio-alto. 2-3 mesi per un MVP funzionale con sync.

#### Opzione 3: Client cross-platform Flutter/Kotlin Multiplatform
**Fattibilità: Media**

- Un unico codebase per iOS + Android
- Flutter ha buon supporto audio a basso livello via platform channels
- Kotlin Multiplatform è maturo per networking/logica, UI nativa per piattaforma
- Coprirebbe il gap anche su Android (dove Snap.Net è ugualmente datato)

**Effort stimato**: Medio-alto. Simile all'opzione 2 ma con beneficio Android.

#### Opzione 4: Progressive Web App (Snapweb migliorato)
**Fattibilità: Alta (ma con limitazioni)**

- Snapweb già esiste e funziona per il controllo
- Non supporta riproduzione audio in background su iOS (limitazione WebKit)
- Web Audio API non garantisce la precisione di sync necessaria
- Buona soluzione come **controller**, non come **player**

**Effort stimato**: Basso per il controllo, impossibile per playback sincronizzato.

### Raccomandazione

Per l'ecosistema SnapForge, la strategia consigliata è un **approccio a due fasi**:

**Fase 1 — Breve termine**: Documentare l'uso di Snapweb come controller mobile e l'app Snap.Net esistente (con le sue limitazioni note) come player iOS. Aggiungere una sezione al DEPLOYMENT-GUIDE.

**Fase 2 — Medio termine**: Valutare lo sviluppo di un client iOS nativo in Swift come componente del ecosistema SnapForge. Questo colmerebbe il gap più significativo dell'ecosistema (assenza di client mobile mantenuto) e darebbe a SnapForge un vantaggio competitivo unico rispetto a Snapcast vanilla.

La scelta tra Swift nativo (opzione 2) e cross-platform (opzione 3) dipende dalle risorse disponibili e dalla priorità del supporto Android.

---

## Analisi approfondita: come sviluppare un client iOS funzionante

### Il protocollo Snapcast in dettaglio

Il protocollo binario Snapcast (porta 1704) è relativamente semplice e ben documentato:

**Header base** (26 byte, little-endian):
```
type     (uint16) — tipo messaggio
id       (uint16) — identificativo richiesta
refersTo (uint16) — riferimento risposta
sent     (int32+int32) — timestamp invio (sec + usec)
received (int32+int32) — timestamp ricezione (sec + usec)
size     (uint32) — dimensione payload
```

**Tipi di messaggio**:

| ID | Nome | Direzione | Funzione |
|----|------|-----------|----------|
| 1 | Codec Header | S→C | Inizializzazione codec audio |
| 2 | Wire Chunk | S→C | Segmenti audio codificati |
| 3 | Server Settings | S→C | Volume, latenza, buffer |
| 4 | Time | C↔S | Sincronizzazione clock |
| 5 | Hello | C→S | Connessione iniziale client |
| 7 | Client Info | C→S | Aggiornamenti volume/mute |
| 8 | Error | S→C | Errori autenticazione |

**Handshake**:
1. Client apre socket TCP (porta 1704)
2. Client invia Hello (JSON: ClientName, HostName, OS, Arch, Version, MAC, SnapStreamProtocolVersion)
3. Server risponde con Server Settings (volume, muted, bufferMs, latency)
4. Server invia Codec Header (header FLAC/PCM/Opus/Vorbis)
5. Server inizia a inviare Wire Chunk (audio codificato)

**Algoritmo di sincronizzazione**:
Il client invia periodicamente messaggi Time. Il server risponde con timestamp. Il client calcola:
- `latency_c2s = t_server_recv - t_client_sent + t_network_latency`
- `latency_s2c = t_client_recv - t_server_sent + t_network_latency`
- `time_diff = (latency_c2s - latency_s2c) / 2`

Questo elimina la latenza di rete simmetrica e permette sync sub-millisecondo.

### Analisi delle 5 opzioni di sviluppo

#### Opzione A: Cross-compilare il client C++ Snapcast per iOS
**Fattibilità: Media — Approccio più diretto**

Snapcast ha già un backend CoreAudio funzionante (`client/player/coreaudio_player.cpp`) che usa `AudioQueueServices` — API disponibile sia su macOS che su iOS. Il vero ostacolo storico era compilare Boost per iOS.

**Stato attuale**:
- Snapcast usa solo header Boost (header-only libs) dalla v0.28+ → semplifica enormemente la compilazione
- Il progetto [boost-iosx](https://github.com/apotocki/boost-iosx) produce XCFramework Boost per iOS/tvOS/watchOS/visionOS/macOS
- Il `coreaudio_player.cpp` usa `AudioQueueNewOutput`, `AudioQueueAllocateBuffer`, `AudioQueueStart` — tutte API disponibili su iOS
- CI Snapcast compila già con Xcode 15.1-15.4

**Cosa servirebbe**:
1. Build Boost headers per iOS via boost-iosx (o semplicemente puntare agli header, dato che sono header-only)
2. CMake toolchain iOS (`ios.toolchain.cmake`) per cross-compilare snapclient
3. Adattamenti minimi al CoreAudio player (macOS → iOS: stesse AudioQueue API)
4. Wrapper Swift/ObjC per UI e lifecycle iOS
5. Framework per la distribuzione (XCFramework)

**Pro**: Protocollo completo e aggiornato, sync già implementato e testato, tutti i codec supportati (FLAC, PCM, Opus, Vorbis), manutenzione allineata con upstream.
**Contro**: Dipendenza C++ complessa, debugging cross-language, aggiornamenti Snapcast da integrare manualmente.

#### Opzione B: Client nativo Swift puro
**Fattibilità: Media-Alta — Più pulito ma più lavoro**

Reimplementare il protocollo Snapcast in Swift da zero.

**Stack proposto**:
- **Networking**: `NWConnection` (Network.framework) per TCP
- **Audio**: `AVAudioEngine` + `AVAudioPlayerNode` per playback
- **FLAC decode**: wrapper Swift attorno a libFLAC (C, facilmente bridgeable) oppure libreria [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) che supporta FLAC
- **mDNS**: `NWBrowser` (Network.framework) per Bonjour discovery — nativo iOS
- **JSON-RPC**: `URLSessionWebSocketTask` o TCP raw con `Codable`
- **UI**: SwiftUI
- **Sync**: `mach_absolute_time()` per timing alta precisione

**Componenti da implementare**:

| Componente | Complessità | Note |
|------------|------------|------|
| Parser header binario (26 byte) | Bassa | `Data` + `withUnsafeBytes` |
| Hello/handshake | Bassa | JSON encoding/decoding |
| Wire Chunk receiver | Media | Buffer management, backpressure |
| FLAC decoder | Bassa | Bridge a libFLAC C esistente |
| PCM passthrough | Bassa | Diretto a AVAudioPCMBuffer |
| Opus decoder | Media | Bridge a libopus C |
| Clock sync NTP-like | Alta | Core critico per funzionamento |
| Playout buffer + resampling | Alta | Compensazione drift clock |
| AVAudioEngine pipeline | Media | scheduleBuffer su PlayerNode |
| mDNS discovery | Bassa | NWBrowser nativo |
| JSON-RPC control client | Media | Gestione gruppi/volumi |
| Background audio | Bassa | AVAudioSession category config |
| UI SwiftUI | Media | Gruppi, volumi, now playing |

**La parte critica è il clock sync + playout buffer**. L'algoritmo di sync è documentato ma l'implementazione richiede:
- Calcolo preciso del tempo di playout per ogni chunk
- Compensazione del jitter di rete
- Resampling adattivo per correggere drift clock tra server e device iOS
- Buffer management per evitare underrun/overrun

**Latenza AVAudioEngine su iOS**: buffer da 64 sample a 48kHz = ~1.3ms. Sufficiente per sync Snapcast.

**Pro**: Codebase moderno e manutenibile, nessuna dipendenza C++ pesante, performance nativa iOS, facile distribuzione App Store.
**Contro**: Clock sync complesso da implementare correttamente, rischio di bug sottili nel timing.

#### Opzione C: Wrapper Swift attorno a snapclient C++ (ibrido)
**Fattibilità: Alta — Miglior compromesso**

Compilare il core C++ di snapclient come libreria statica, wrapparlo con un'interfaccia C, e costruire UI + lifecycle in Swift.

**Architettura**:
```
┌─────────────────────────────┐
│     SwiftUI Interface       │  ← Swift puro
├─────────────────────────────┤
│   Swift Control Layer       │  ← JSON-RPC, mDNS (Network.framework)
├─────────────────────────────┤
│   C Bridge Interface        │  ← header .h con funzioni C
├─────────────────────────────┤
│   snapclient C++ core       │  ← compilato come .a statica
│   (stream, decoder, sync,   │
│    coreaudio_player)         │
├─────────────────────────────┤
│   Boost headers + libFLAC   │  ← dipendenze C/C++
│   + libopus + libogg         │
└─────────────────────────────┘
```

**Vantaggi chiave**:
- Il clock sync e il playout buffer sono quelli ufficiali Snapcast — testati e funzionanti
- Il CoreAudio player esiste già e usa API compatibili iOS
- La UI è Swift nativa → App Store review friendly
- Aggiornamenti upstream: basta ricompilare il core C++
- Tutti i codec gratis (FLAC, PCM, Opus, Vorbis)

**Passi concreti**:
1. Creare CMake toolchain per iOS target
2. Compilare dipendenze come XCFramework: Boost (header-only), libFLAC, libopus, libogg
3. Compilare snapclient core (senza main) come libreria statica ARM64
4. Scrivere bridge C (`snapclient_bridge.h`) con: `init()`, `start(host, port)`, `stop()`, `set_volume()`, `get_status()`
5. Wrappare in Swift class `SnapClientEngine`
6. Costruire UI SwiftUI per controllo
7. Aggiungere JSON-RPC client Swift per gestione server
8. Aggiungere NWBrowser per mDNS discovery
9. Configurare AVAudioSession per background playback

#### Opzione D: Flutter cross-platform
**Fattibilità: Media — Complicata per audio low-latency**

**Problemi identificati**:
- Flutter non ha accesso nativo a CoreAudio per audio low-latency
- I plugin audio Flutter (`audioplayers`, `flutter_soloud`) non sono progettati per streaming sincronizzato
- Servirebbe comunque un platform channel verso codice nativo (C++/Swift) per il player → vanifica il vantaggio cross-platform
- Il clock sync richiede timing preciso che Dart VM non garantisce

**Pro**: Un codebase per iOS + Android.
**Contro**: La parte critica (audio sync) deve essere nativa comunque, complessità aggiunta senza beneficio reale.

#### Opzione E: Kotlin Multiplatform (KMP)
**Fattibilità: Media-Bassa**

- KMP per logica condivisa (protocollo, JSON-RPC) + UI nativa per piattaforma
- Stesso problema di Flutter: audio low-latency richiede codice nativo
- Ecosistema KMP per iOS ancora in maturazione
- Overhead di setup significativo per un progetto audio-focused

### Matrice comparativa finale

| Criterio | A: C++ cross-compile | B: Swift puro | C: Swift + C++ core | D: Flutter | E: KMP |
|----------|---------------------|---------------|---------------------|-----------|--------|
| **Qualità sync audio** | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★☆☆☆ | ★★☆☆☆ |
| **Manutenibilità** | ★★☆☆☆ | ★★★★★ | ★★★★☆ | ★★★☆☆ | ★★★☆☆ |
| **Effort MVP** | ★★★★☆ | ★★☆☆☆ | ★★★★☆ | ★★☆☆☆ | ★☆☆☆☆ |
| **Copertura codec** | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★☆☆☆ | ★★☆☆☆ |
| **UX nativa iOS** | ★★☆☆☆ | ★★★★★ | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| **Compatibilità upstream** | ★★★★★ | ★☆☆☆☆ | ★★★★★ | ★☆☆☆☆ | ★☆☆☆☆ |
| **Supporto Android** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **App Store approval** | ★★★☆☆ | ★★★★★ | ★★★★★ | ★★★★☆ | ★★★★☆ |

### Raccomandazione: Opzione C (Swift + C++ core)

**L'opzione C è la scelta migliore** per ottenere un client che funzioni bene, perché:

1. **La sincronizzazione audio è il problema più difficile** — reimplementarla da zero (opzione B) è rischioso. Il core C++ di Snapcast ha anni di bug fix e ottimizzazioni nell'algoritmo di sync e nel buffer management.

2. **Il CoreAudio player di Snapcast usa AudioQueueServices** — queste API funzionano identicamente su iOS e macOS. Non serve riscrivere il layer audio.

3. **Boost è ora header-only** per le dipendenze di Snapcast — il blocco storico che ha fermato SnapClientIOS non esiste più. Con [boost-iosx](https://github.com/apotocki/boost-iosx) si producono XCFramework in automatico.

4. **La UI Swift è fondamentale** per una buona UX iOS e per App Store review. Il vecchio Snap.Net usava Xamarin che produceva UI non-native.

5. **Aggiornamenti upstream sono banali** — quando Snapcast rilascia una nuova versione, si ricompila la libreria statica senza toccare il codice Swift.

### Piano di sviluppo proposto (Opzione C)

**Fase 1 — Build system e core C++ (fondamenta)**
- Setup CMake iOS toolchain
- Compilare Boost headers, libFLAC, libopus, libogg per iOS ARM64
- Compilare snapclient core come libreria statica (.a)
- Scrivere bridge C minimale: `init`, `start`, `stop`
- Test: connessione a Snapserver e riproduzione audio su simulatore/device

**Fase 2 — App iOS minimale (MVP)**
- Progetto Xcode con SwiftUI
- `SnapClientEngine` Swift class che wrappa il bridge C
- AVAudioSession configurato per background playback
- mDNS discovery via NWBrowser
- UI: lista server trovati, bottone play/stop, volume slider
- Test: riproduzione sincronizzata con altri client nella stessa rete

**Fase 3 — Controllo completo (feature parity)**
- Client JSON-RPC in Swift (via WebSocket o TCP)
- UI gestione gruppi e client
- Regolazione latenza per client
- Gestione nomi gruppi/client
- Dark mode, temi
- Controlli media iOS (Control Center, lock screen)
- Now Playing info con metadati

**Fase 4 — Stabilità e distribuzione**
- Test su diverse configurazioni (Wi-Fi, VPN, cellular)
- Gestione riconnessione automatica (cambio rete, sleep/wake)
- Crash reporting e logging
- TestFlight beta
- Pubblicazione App Store
