# MyVoice — Native iOS Audio App

## 1. Project Overview

**Name:** MyVoice

**Platform:** Native iOS

**Language:** Swift

**UI:** SwiftUI

**Audio:** AVFoundation / AVFAudio

**Minimum target:** iOS 17+

**Primary concept:**

MyVoice is a low-latency karaoke/voice-monitoring application that can:

1. Capture microphone input.
2. Run while the app is in the background.
3. Play audio while recording microphone input.
4. Mix microphone audio with audio played by MyVoice.
5. Output the mixed result through the current audio route.
6. Start/stop the audio engine using an `Active` button.

The application should perform all audio processing locally on the device.

---

# 2. Critical iOS Platform Constraint

## 2.1 The desired architecture

The initial concept is:

```text
                    ┌──────────────────┐
                    │ External Music   │
                    │ Spotify / Music  │
                    │ YouTube / Safari │
                    └────────┬─────────┘
                             │
                             │ System audio
                             ▼
┌─────────────┐       ┌───────────────┐
│ Microphone  │──────►│ MyVoice Mixer │──────► Speaker / Headphones
└─────────────┘       └───────────────┘
```

The problematic part is:

```text
External Music
      │
      ▼
MyVoice receives raw PCM
```

A normal iOS application cannot generally access another application's raw audio output stream.

`AVAudioSession` supports simultaneous recording and playback and can configure mixing with other audio sessions, but that does not expose another application's PCM stream to MyVoice. ([Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord?changes=_5&utm_source=chatgpt.com))

Therefore, this architecture should **not** be the core assumption of the implementation.

---

# 3. Recommended Architecture

The first production architecture should instead be:

```text
                 MyVoice
                    │
       ┌────────────┴────────────┐
       │                         │
       ▼                         ▼
 Microphone                 Music Player
       │                         │
       │ PCM                     │ PCM
       ▼                         ▼
       └──────────► Mixer ◄──────┘
                       │
                       ▼
                Master Output
                       │
                       ▼
             Speaker / Headphones
```

In other words:

> **MyVoice should own the music playback source.**

For example:

```text
Song / Karaoke Track
        │
        ▼
AVAudioPlayerNode
        │
        ├──────────────┐
        │              │
        ▼              ▼
Music Mixer      Microphone Input
                       │
                       ▼
                 Voice Mixer
                       │
                       ▼
                  Main Mixer
                       │
                       ▼
                 Output Node
```

This gives MyVoice complete control over:

- microphone
- music
- volume
- microphone gain
- music volume
- latency
- effects
- pitch
- EQ
- reverb
- monitoring
- recording
- final mix

---

# 4. Audio Architecture

## 4.1 Core technologies

Use:

- `AVAudioSession`
- `AVAudioEngine`
- `AVAudioInputNode`
- `AVAudioPlayerNode`
- `AVAudioMixerNode`
- `AVAudioUnitEQ`
- `AVAudioUnitReverb`
- `AVAudioFile`
- Core Audio where lower-level control is required

Do NOT use `AVAudioRecorder` as the core audio pipeline.

`AVAudioRecorder` is suitable for simple recording, while Apple recommends `AVAudioEngine` for advanced recording and signal processing. ([Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiorecorder?changes=latest_maj_4_2&language=objc&utm_source=chatgpt.com))

---

# 5. Audio Graph

Recommended initial graph:

```text
                         ┌─────────────────────┐
                         │   AVAudioFile       │
                         │ Karaoke / Music     │
                         └──────────┬──────────┘
                                    │
                                    ▼
                          ┌──────────────────┐
                          │ AVAudioPlayerNode│
                          └────────┬─────────┘
                                   │
                                   ▼
                          ┌──────────────────┐
                          │ Music Mixer      │
                          └────────┬─────────┘
                                   │
                                   │
                                   ▼
Microphone                      ┌──────────────┐
    │                           │ Main Mixer   │
    ▼                           └──────┬───────┘
AVAudioInputNode                      │
    │                                 │
    ▼                                 │
Mic Mixer ────────────────────────────┘
                                      │
                                      ▼
                               Output Node
                                      │
                                      ▼
                               Audio Hardware
```

`AVAudioEngine` provides the input and output nodes required for this graph. ([Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode?changes=__1&language=objc&utm_source=chatgpt.com))

---

# 6. AVAudioSession

Use:

```swift
AVAudioSession.sharedInstance()
```

Configure:

```swift
try session.setCategory(
    .playAndRecord,
    mode: .default,
    options: [
        .mixWithOthers,
        .allowBluetooth,
        .allowBluetoothA2DP
    ]
)
```

Then:

```swift
try session.setActive(true)
```

`playAndRecord` is specifically designed for simultaneous input and output. It can also continue operating when the screen is locked when the appropriate background audio configuration is enabled. ([Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord?changes=_5&utm_source=chatgpt.com))

---

# 7. Background Execution

MyVoice needs:

```text
Signing & Capabilities
    └── Background Modes
            └── Audio, AirPlay, and Picture in Picture
```

Equivalent:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

iOS normally suspends applications in the background. Audio is one of the supported background execution modes. ([Apple Developer](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes?utm_source=chatgpt.com))

Important:

The app should only declare background audio because it is genuinely performing continuous audio work.

The user flow should therefore be:

```text
Open MyVoice
      │
      ▼
Tap ACTIVE
      │
      ▼
Request microphone permission
      │
      ▼
Configure AVAudioSession
      │
      ▼
Start AVAudioEngine
      │
      ▼
User locks screen / changes app
      │
      ▼
MyVoice continues audio processing
```

---

# 8. Microphone Permission

Required:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>
MyVoice needs microphone access to capture your voice while singing.
</string>
```

Request:

```swift
AVAudioApplication.requestRecordPermission()
```

The engine should not start until permission is granted.

---

# 9. Low-Latency Strategy

Latency is one of the most important requirements.

Target:

```text
Microphone
   │
   ▼
Input buffer
   │
   ▼
DSP
   │
   ▼
Mixer
   │
   ▼
Output
```

Target end-to-end latency:

```text
< 20 ms   = excellent
20–40 ms  = acceptable
40–80 ms  = noticeable
> 80 ms   = poor for karaoke monitoring
```

The exact achievable latency depends heavily on the audio route and hardware.

---

# 10. Audio Buffer Configuration

Do not assume the default buffer is optimal.

Experiment with:

```swift
try session.setPreferredIOBufferDuration(0.0029)
```

approximately:

```text
128 samples @ 44.1 kHz ≈ 2.9 ms
```

or:

```text
128 samples @ 48 kHz ≈ 2.67 ms
```

Potential configurations:

```text
64 samples
128 samples
256 samples
```

Start with:

```text
128 samples
```

and benchmark.

Do not blindly use the smallest buffer.

Smaller buffer:

```text
+ lower latency
- higher CPU
- greater risk of glitches
```

---

# 11. Sample Rate

Prefer the hardware sample rate.

Typical iPhone audio:

```text
44.1 kHz
48 kHz
```

Do not unnecessarily resample:

```text
48k → 44.1k → 48k
```

Prefer:

```text
Hardware
   │
   ▼
Native sample rate
   │
   ▼
AVAudioEngine
```

---

# 12. Audio Processing Thread

The realtime audio callback is extremely sensitive.

DO NOT perform:

```text
Network requests
File I/O
Database queries
Memory allocation
JSON parsing
Logging
Locks
Heavy Swift object creation
```

inside the realtime audio path.

Bad:

```swift
inputNode.installTap { buffer, time in
    database.save(buffer)
}
```

Better:

```text
Realtime Audio Thread
        │
        ▼
Preallocated Ring Buffer
        │
        ▼
Background Processing Queue
        │
        ▼
File / Analytics / UI
```

---

# 13. Voice Processing

MVP should support:

```text
Mic
 ├── Volume
 ├── Gain
 ├── EQ
 ├── Reverb
 └── Monitoring
```

Potential future processing:

```text
Noise suppression
Auto gain
Compressor
Limiter
Pitch correction
Vocal effects
Echo cancellation
```

Avoid enabling aggressive voice-processing initially because karaoke requires relatively natural microphone monitoring.

---

# 14. Echo / Feedback Problem

This is a major physical audio problem.

If:

```text
Speaker
   │
   ▼
Microphone
   │
   ▼
MyVoice
   │
   ▼
Speaker
```

then feedback can occur.

Therefore:

## Preferred

Use:

```text
AirPods
Wired headphones
USB audio interface
```

for vocal monitoring.

## Speaker mode

If speaker output is required:

- reduce microphone gain
- use acoustic echo cancellation where appropriate
- apply feedback protection
- avoid excessive monitoring volume

The product UI should clearly indicate:

> Headphones recommended for low-latency vocal monitoring.

---

# 15. Music Playback

MVP should support music owned by MyVoice.

Possible sources:

```text
Local audio file
Files app
Imported MP3
M4A
WAV
CAF
```

Future:

```text
Apple Music integration
MusicKit
Cloud music
Karaoke catalog
```

However, MusicKit does not mean MyVoice gets arbitrary raw PCM from Apple Music for custom realtime mixing.

The architecture should therefore not depend on extracting protected audio from another music application.

---

# 16. External Music Apps

Desired:

```text
Spotify
Apple Music
YouTube
TikTok
Safari
       │
       ▼
MyVoice
```

should be considered **unsupported as a raw-audio input architecture**.

The feasible behavior is instead:

```text
External Music App
        │
        │
        ▼
System Audio Output
        │
        ├──────────────► Headphones / Speaker
        │
        ▼
       User
```

while MyVoice independently records/processes microphone input.

MyVoice can potentially configure its audio session to coexist/mix with other audio, but it does not receive the external app's PCM samples. Apple's audio session documentation explicitly describes `mixWithOthers` as mixing behavior between audio sessions, not exposing another app's audio buffer. ([Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord?changes=_5&utm_source=chatgpt.com))

---

# 17. Alternative: ScreenCaptureKit

Modern iOS provides ScreenCaptureKit capabilities for screen/audio capture. Apple documents high-performance capture of screen content and audio. ([Apple Developer](https://developer.apple.com/documentation/screencapturekit?changes=_5__8&utm_source=chatgpt.com))

This should be treated as an **experimental research path**, not the foundation of MyVoice.

Prototype:

```text
ScreenCaptureKit
        │
        ▼
Captured audio
        │
        ▼
MyVoice processing
```

Questions that must be validated experimentally:

- Which external audio is exposed?
- Can the desired music applications be captured?
- Can capture continue under the required background conditions?
- What latency is introduced?
- What permissions/UI are required?
- Does it satisfy App Store policy?
- Can captured audio be routed into realtime playback safely?

Do not build the production architecture around this until a real-device prototype proves it.

---

# 18. MVP Scope

## MVP-1

Build the smallest possible audio engine:

```text
Microphone
    │
    ▼
AVAudioEngine
    │
    ▼
Output
```

Requirements:

- microphone permission
- Active/Inactive
- background execution
- lock screen test
- headphones
- speaker
- audio route changes
- interruption handling

---

# 19. MVP-2

Add local music:

```text
Local Song
    │
    ▼
PlayerNode
    │
    ▼
Music Mixer
    │
    ├──────────────┐
    │              │
Mic ───────────────┤
                   ▼
               Main Mixer
                   │
                   ▼
                 Output
```

Controls:

```text
Music Volume
Mic Volume
Master Volume
Play
Pause
Stop
Seek
```

---

# 20. MVP-3

Add recording:

```text
Mic + Music
     │
     ▼
Main Mixer
     │
     ├──────────► Output
     │
     ▼
 Recording File
```

Output:

```text
.m4a
```

or:

```text
.wav
```

For development, WAV/PCM is useful for debugging latency and DSP.

For user storage, AAC/M4A is more practical.

---

# 21. Application Architecture

Recommended project:

```text
MyVoice/
│
├── App/
│   ├── MyVoiceApp.swift
│   └── AppState.swift
│
├── Audio/
│   ├── AudioEngine.swift
│   ├── AudioSessionManager.swift
│   ├── AudioRouteManager.swift
│   ├── AudioMixer.swift
│   ├── MicrophoneInput.swift
│   ├── MusicPlayer.swift
│   ├── AudioRecorder.swift
│   └── AudioDiagnostics.swift
│
├── DSP/
│   ├── GainProcessor.swift
│   ├── EQProcessor.swift
│   ├── Compressor.swift
│   ├── Limiter.swift
│   └── ReverbProcessor.swift
│
├── Features/
│   ├── Home/
│   ├── Player/
│   ├── Recording/
│   └── Settings/
│
├── UI/
│   ├── Components/
│   └── Theme/
│
└── Tests/
    ├── AudioEngineTests/
    ├── AudioSessionTests/
    └── DSPTests/
```

---

# 22. AudioEngine Responsibilities

`AudioEngine.swift` should own:

```swift
final class AudioEngineManager {

    func configure()

    func start() throws

    func stop()

    func pause()

    func resume()

    func setMicrophoneVolume(_ value: Float)

    func setMusicVolume(_ value: Float)

    func setMasterVolume(_ value: Float)

    func handleRouteChange()

    func handleInterruption()

    func handleMediaServicesReset()
}
```

The UI should never directly manipulate `AVAudioEngine`.

---

# 23. State Machine

Use an explicit state machine:

```text
                    ┌─────────────┐
                    │    IDLE     │
                    └──────┬──────┘
                           │ Active
                           ▼
                    ┌─────────────┐
                    │ STARTING    │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   ACTIVE    │
                    └──────┬──────┘
                           │ Stop
                           ▼
                    ┌─────────────┐
                    │   STOPPING  │
                    └──────┬──────┘
                           │
                           ▼
                         IDLE
```

Error:

```text
ACTIVE
   │
   ▼
INTERRUPTED
   │
   ├── resume
   │
   ▼
ACTIVE
```

---

# 24. Audio Route Handling

Must support:

```text
iPhone Speaker
Built-in Receiver
Wired Headphones
Bluetooth
AirPods
USB Audio
CarPlay
```

Listen for:

```swift
AVAudioSession.routeChangeNotification
```

and:

```swift
AVAudioSession.interruptionNotification
```

Also handle:

```text
mediaServicesWereLost
mediaServicesWereReset
```

---

# 25. UI Concept

Home screen:

```text
┌──────────────────────────────┐
│           MyVoice            │
│                              │
│        🎤                    │
│                              │
│       INACTIVE               │
│                              │
│       [ ACTIVE ]             │
│                              │
│ ──────────────────────────── │
│                              │
│ Mic Volume        ●──────    │
│ Music Volume      ─────●     │
│                              │
│ 🎵 No song selected          │
│                              │
│ [ Select Music ]             │
│                              │
└──────────────────────────────┘
```

When active:

```text
┌──────────────────────────────┐
│           MyVoice            │
│                              │
│          ● ACTIVE            │
│                              │
│      🎤 Monitoring           │
│                              │
│ Mic        ███████░░         │
│ Music      █████░░░░         │
│                              │
│      00:02:31                │
│                              │
│       [ STOP ]               │
└──────────────────────────────┘
```

---

# 26. UX Rule

The user should always understand:

```text
ACTIVE
```

means:

```text
Microphone is being accessed
Audio engine is running
Background audio may continue
Battery consumption is increased
```

When inactive:

```text
Audio engine stopped
Microphone released
Audio session deactivated
```

---

# 27. Battery Optimization

Do not continuously run the audio engine when inactive.

Inactive:

```text
AVAudioEngine.stop()
AVAudioSession.setActive(false)
```

Active:

```text
AVAudioSession.setActive(true)
AVAudioEngine.start()
```

Avoid unnecessary:

```text
CPU DSP
UI updates
metering at 60 FPS
audio analysis
file writes
```

Metering can be updated around:

```text
10–20 FPS
```

instead of 60 FPS.

---

# 28. Diagnostics

Build an internal debug panel.

Display:

```text
Audio Session
-------------
Category
Mode
Sample Rate
IO Buffer Duration
Input Route
Output Route
Input Channels
Output Channels
Engine Running
CPU Load
```

Example:

```text
Sample Rate:       48000 Hz
Buffer:            128 frames
Latency:           ~2.67 ms
Input:             Built-in Mic
Output:            AirPods
Engine:            Running
```

This will be extremely useful when diagnosing real-device audio problems.

---

# 29. Testing Strategy

Audio applications must be tested on physical devices.

Simulator is not sufficient.

Test matrix:

| Test | Required |
|---|---:|
| iPhone Speaker | Yes |
| Wired Headphones | Yes |
| AirPods | Yes |
| Bluetooth speaker | Yes |
| Screen locked | Yes |
| Background | Yes |
| Incoming phone call | Yes |
| Siri | Yes |
| Alarm | Yes |
| Notification | Yes |
| Other music app | Yes |
| Microphone interruption | Yes |
| Bluetooth connect/disconnect | Yes |
| Route change | Yes |
| Low battery | Yes |

---

# 30. Latency Benchmark

Create a test mode:

```text
Microphone
    │
    ▼
Impulse / Click
    │
    ▼
Engine
    │
    ▼
Output
```

Measure:

```text
Input timestamp
        ↓
Processing
        ↓
Output timestamp
```

Record:

```text
average latency
p50
p95
p99
maximum
audio glitches
```

Target:

```text
p95 < 30 ms
```

for the initial prototype.

---

# 31. Performance Targets

MVP:

```text
Audio glitches:      0
Crash rate:          0
Engine restart:      reliable
Background audio:    reliable
Route switching:     reliable
CPU:                 as low as possible
Memory:              stable
```

Latency:

```text
Excellent: <20 ms
Target:    <30 ms
Acceptable: <50 ms
Poor:       >80 ms
```

---

# 32. Development Phases

## Phase 1 — Audio Proof of Concept

Duration:

```text
1–2 days
```

Implement:

```text
AVAudioSession
AVAudioEngine
Microphone
Output
Active / Stop
```

Goal:

> Speak into microphone and hear yourself with minimal latency.

---

## Phase 2 — Background Audio

Duration:

```text
1 day
```

Implement:

```text
UIBackgroundModes = audio
screen lock
background transition
audio interruptions
route changes
```

Goal:

> Start MyVoice → lock iPhone → microphone monitoring continues.

---

## Phase 3 — Music Mixer

Duration:

```text
2–3 days
```

Implement:

```text
AVAudioPlayerNode
Music Mixer
Mic Mixer
Main Mixer
Volume controls
```

Goal:

> Hear music + microphone simultaneously.

---

## Phase 4 — Recording

Duration:

```text
1–2 days
```

Implement:

```text
Mixed output recording
M4A
WAV debug mode
```

Goal:

> Record the final karaoke performance.

---

## Phase 5 — DSP

Duration:

```text
3–5 days
```

Implement:

```text
EQ
Compressor
Limiter
Reverb
Noise reduction
```

Only optimize DSP after the basic audio pipeline is stable.

---

## Phase 6 — External Audio Research

Duration:

```text
Research / prototype
```

Investigate:

```text
ScreenCaptureKit
ReplayKit
MusicKit
Audio Session mixing
```

Goal:

> Determine whether external application audio can satisfy the exact MyVoice product requirement.

Do not block MVP on this.

---

# 33. Important Product Decision

There are two possible products.

## Product A — Controlled Karaoke Player

```text
MyVoice
 ├── Music
 ├── Microphone
 ├── Mixer
 ├── Effects
 └── Recording
```

This is technically straightforward and gives MyVoice full control over latency and mixing.

**Recommended.**

---

## Product B — Universal System Audio Karaoke

```text
Spotify
Apple Music
YouTube
TikTok
Safari
     │
     ▼
MyVoice
     │
     ▼
Microphone + external audio
     │
     ▼
Mixed output
```

This is fundamentally constrained by iOS application isolation and audio APIs.

It should be treated as an R&D problem rather than assuming it is implementable with `AVAudioEngine`.

---

# 34. Offline / Local Requirement

MyVoice should not require a backend for the core functionality.

Architecture:

```text
                 iPhone
┌────────────────────────────────────┐
│                                    │
│ SwiftUI                            │
│      │                             │
│      ▼                             │
│ Audio Engine                       │
│      │                             │
│      ├── Microphone                │
│      ├── Music                     │
│      ├── DSP                       │
│      └── Recording                 │
│                                    │
│ Local Files / SwiftData             │
│                                    │
└────────────────────────────────────┘
```

Internet should be optional.

---

# 35. "No App Store Installation" Requirement

There are two different meanings.

## Development / Personal Device

It is possible to install and run a native iOS app directly on a development device using Xcode and Apple signing/development provisioning.

This is appropriate for:

```text
Personal testing
Development
Internal prototypes
Audio experiments
```

## General distribution

If the intention is:

> Send an `.ipa` to any iPhone and install it without App Store / TestFlight / Apple signing.

That is not a normal supported iOS deployment model.

Therefore the development plan should use:

```text
Xcode
+
Apple Developer signing
+
Physical iPhone
```

for the prototype.

---

# 36. Recommended Technology Stack

```text
Language
    Swift

UI
    SwiftUI

Audio
    AVFAudio
    AVFoundation
    Core Audio where required

Architecture
    MVVM + Service Layer

Persistence
    SwiftData

Concurrency
    Swift Concurrency

Testing
    XCTest

Minimum
    iOS 17+

IDE
    Xcode

Backend
    None for MVP
```

---

# 37. Initial Repository

```text
MyVoice/
├── MyVoice.xcodeproj
├── MyVoice/
│   ├── App/
│   ├── Audio/
│   ├── DSP/
│   ├── Features/
│   ├── UI/
│   └── Resources/
│
├── MyVoiceTests/
│
├── MyVoiceUITests/
│
├── README.md
└── MYVOICE_PLAN.md
```

---

# 38. First Milestone

The first milestone should NOT be building the entire UI.

Build this:

```text
┌──────────────────────────────────┐
│                                  │
│            MyVoice               │
│                                  │
│            [ ACTIVE ]             │
│                                  │
│            [ STOP ]               │
│                                  │
│         Mic Level: ██████         │
│                                  │
└──────────────────────────────────┘
```

Under the hood:

```text
UIButton
    │
    ▼
AudioSessionManager
    │
    ▼
AVAudioEngine
    │
    ▼
InputNode
    │
    ▼
Mixer
    │
    ▼
OutputNode
```

Acceptance criteria:

```text
[ ] Microphone permission works
[ ] ACTIVE starts audio
[ ] STOP releases audio
[ ] Voice can be monitored
[ ] Latency is measured
[ ] Screen lock works
[ ] Background works
[ ] AirPods work
[ ] Speaker works
[ ] Audio route changes work
[ ] Incoming call interruption is handled
[ ] No audio glitches under normal conditions
```

Only after this passes should the music player and recording features be implemented.

---

# 39. Final Architecture Decision

### Recommended

```text
                  MyVoice
                     │
        ┌────────────┴────────────┐
        │                         │
   Microphone                  Music
        │                         │
        ▼                         ▼
   Mic Processing          Music Player
        │                         │
        └───────────┬─────────────┘
                    ▼
                 Mixer
                    │
             ┌──────┴──────┐
             │             │
             ▼             ▼
          Output        Recorder
             │
             ▼
       Speaker / Headphones
```

### Avoid making this assumption

```text
Spotify / Apple Music / YouTube
             │
             ▼
       Raw PCM → MyVoice
```

That is the key technical constraint that should shape the entire project.

---

# 40. Success Criteria

MyVoice MVP is considered successful when:

1. User taps `ACTIVE`.
2. Microphone starts immediately.
3. User can hear their voice with low latency.
4. Local karaoke music can play simultaneously.
5. Microphone + music can be mixed.
6. Volume can be controlled independently.
7. The engine continues when the app moves to the background.
8. Screen lock does not stop the audio session.
9. Headphones provide usable low-latency monitoring.
10. The mixed audio can be recorded locally.
11. The app does not require a server.
12. The app can be installed directly on a development iPhone through Xcode.
13. Audio interruptions and route changes recover reliably.

---

# 41. Immediate Next Step

The first implementation task should be:

```text
Create MyVoice Xcode project
        ↓
Configure microphone permission
        ↓
Configure Background Audio
        ↓
Implement AudioSessionManager
        ↓
Implement AudioEngineManager
        ↓
Implement microphone → output monitoring
        ↓
Measure real-device latency
        ↓
Test AirPods + Speaker + Screen Lock
```

Do **not** start with the UI or music catalog.

The highest-risk component is the realtime audio engine. Prove that first.
