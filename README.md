# MyVoice

Low-latency karaoke / voice-monitoring native iOS application.

## Architecture

```
MyVoice owns the full audio graph:

  AVAudioInputNode (mic)
        │
        ▼
   micMixerNode ← GainProcessor
        │
        ▼
   reverbNode (AVAudioUnitReverb)
        │
        ▼
   eqNode (AVAudioUnitEQ — 3 band)
        │
        ▼
   mainMixerNode ◄── musicMixerNode ◄── playerNode (AVAudioPlayerNode)
        │
        ▼
   outputNode
        │
        ▼
   Speaker / Headphones
```

## Features (MVP)

| Feature | Status |
|---|---|
| Microphone monitoring | ✅ |
| Background audio | ✅ |
| Local music playback | ✅ |
| Mic + music mix | ✅ |
| Volume controls (mic / music / master) | ✅ |
| Optional noise cancellation mode | ✅ |
| EQ (3-band) | ✅ |
| Reverb | ✅ |
| Audio route handling | ✅ |
| Interruption recovery | ✅ |
| Mixed output recording (.m4a) | ✅ |
| Debug diagnostics panel | ✅ |

## Requirements

- iOS 17+
- Xcode 15+
- Physical iPhone (audio cannot be fully tested on Simulator)
- Microphone permission
- Headphones recommended for low-latency monitoring (avoids speaker feedback)

## Setup

1. Open `MyVoice.xcodeproj` in Xcode
2. Select your team in **Signing & Capabilities**
3. Connect iPhone
4. Build and run

The `UIBackgroundModes: audio` capability and `NSMicrophoneUsageDescription` are already configured in `Info.plist`.

## Key Files

| File | Purpose |
|---|---|
| `Audio/AudioEngineManager.swift` | Central audio graph, start/stop, volume, recording |
| `Audio/AudioSessionManager.swift` | AVAudioSession config, permission |
| `Audio/AudioRouteManager.swift` | Route change + interruption handling |
| `Audio/AudioRecorder.swift` | Mixed output → .m4a |
| `DSP/EQProcessor.swift` | 3-band parametric EQ |
| `DSP/ReverbProcessor.swift` | Room reverb |
| `App/AppState.swift` | Top-level @EnvironmentObject |
| `Features/Home/HomeView.swift` | Main UI screen |

## Latency Targets

| Rating | Latency |
|---|---|
| Excellent | < 20 ms |
| Target | < 30 ms |
| Acceptable | < 50 ms |
| Poor | > 80 ms |

IO buffer is configured to ~2.9 ms (128 samples @ 44.1 kHz). Actual end-to-end latency depends on hardware route.

## Background Audio

The engine continues running when the screen is locked or the user switches to another app. The **ACTIVE** button activates it; **STOP** fully releases the microphone and audio session.

> ⚠️ Use headphones for vocal monitoring to avoid acoustic feedback when using the built-in speaker.
>
> Noise cancellation is available as an optional monitoring mode in Settings. It uses Apple voice processing to reduce room noise and speaker bleed, but it may color vocals compared with the standard path.
