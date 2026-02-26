# Week 3 – NFC-Based Driver Identification

## Objectives
- Implement NFC tag reading for session start
- Implement NFC tag writing for vehicle setup
- Build first-launch onboarding (driver profile creation)
- Build vehicle registration UI
- Wire NFC output into the session state machine

---

## 1. NFC Read/Write Architecture

`NFCService` handles both modes using `NFCNDEFReaderSession`:

| Mode | `invalidateAfterFirstRead` | Delegate method called |
|------|--------------------------|------------------------|
| Reading (session start) | `true` | `didDetectNDEFs` |
| Writing (vehicle setup) | `false` | `didDetectTags` |

### Read Flow
```
Driver taps phone to vehicle sticker
        │
        ▼
NFCService.startReading()
        │  NFCNDEFReaderSession scans tag
        │  didDetectNDEFs → extractVehicleTagURI()
        ▼
SessionManager.nfcService(_:didReadVehicleTagURI:)
        │  Fetches Vehicle by nfcTagID
        │  Fetches local DriverProfile
        │  Creates DrivingSession
        ▼
State → .active
```

### Write Flow (one-time vehicle setup)
```
User taps "Save & Program NFC Tag" in AddVehicleView
        │
        ▼
Vehicle saved to SwiftData with new UUID
        │
        ▼
NFCService.writeVehicleTag(vehicleID:completion:)
        │  Session begins with invalidateAfterFirstRead: false
        │  User holds phone to blank sticker
        │  didDetectTags → connect → writeNDEF
        │  Payload: NFCNDEFPayload.wellKnownTypeURIPayload(url: "fairfuel://vehicle/<UUID>")
        ▼
completion(.success) → UI shows confirmation
```

---

## 2. New Files

| File | Purpose |
|------|---------|
| `Views/OnboardingView.swift` | First-launch name entry; creates `DriverProfile` |
| `Views/AddVehicleView.swift` | Vehicle registration + NFC tag write |

## 3. Updated Files

| File | Change |
|------|--------|
| `Services/NFCService.swift` | Added write mode with `didDetectTags`; uses `wellKnownTypeURIPayload` |
| `Services/SessionManager.swift` | Owns `NFCService`; exposes `scanToStartSession()` and `writeVehicleTag()`; `NSObject` subclass for delegate conformance |
| `App/FairFuelApp.swift` | Creates `ModelContainer` + `SessionManager` in `init()`; injects via `environmentObject` |
| `Views/ContentView.swift` | `RootView` checks for `DriverProfile`; shows `OnboardingView` or tabs |
| `Views/HomeView.swift` | Full session state UI: idle, starting, active (live timer + distance), stopping, ended |
| `Views/DriversView.swift` | Vehicles list with swipe-to-delete; Add Vehicle button |

---

## 4. Session State UI (HomeView)

| State | Display |
|-------|---------|
| `.idle` | Car icon + "Tap Vehicle Tag to Start" button |
| `.starting` | Spinner + "Starting session…" |
| `.active` | Green car + live distance + elapsed timer + vehicle name + "End Session" button |
| `.stopping` | Active view + "Ending in 10 seconds…" orange label |
| `.ended` | Green checkmark + "Session saved." (auto-returns to idle) |

---

## 5. Required Xcode Setup (manual, one-time)

Before the app will build and run on a device, add these in Xcode:

### Signing & Capabilities
1. **+ Capability → Near Field Communication Tag Reading**
2. **+ Capability → Background Modes** → check:
   - Location updates
   - Uses Bluetooth LE accessories

### Info.plist Keys
| Key | Value |
|-----|-------|
| `NFCReaderUsageDescription` | FairFuel uses NFC to identify your vehicle |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | FairFuel tracks your trip while you drive |
| `NSLocationWhenInUseUsageDescription` | FairFuel tracks your trip while you drive |
| `NSBluetoothAlwaysUsageDescription` | FairFuel uses Bluetooth to detect when you leave the vehicle |

---

## 6. Next Steps (Week 4)
- Tune BLE beacon detection thresholds
- Test beacon absence timeout in real vehicle environment
- Add iBeacon UUID configuration UI
