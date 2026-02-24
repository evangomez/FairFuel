# Week 2 – System Architecture and Design

## 1. System Overview

FairFuel is a local-first iOS application. All data is stored on-device using SwiftData. No backend server is required for V1. The system has four major sensing components and two logical processing layers.

```
┌──────────────────────────────────────────────────────────────────┐
│                         iOS Device                               │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │ NFC Service │  │  BLE Service │  │   Location Service     │  │
│  │  (CoreNFC)  │  │(CoreBluetooth│  │   (CoreLocation)       │  │
│  │             │  │ /CoreLocation│  │                         │  │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬────────────┘  │
│         │                │                       │               │
│         └────────────────┴───────────────────────┘               │
│                               │                                  │
│                    ┌──────────▼──────────┐                       │
│                    │   SessionManager    │                       │
│                    │  (State Machine)    │                       │
│                    └──────────┬──────────┘                       │
│                               │                                  │
│                    ┌──────────▼──────────┐                       │
│                    │  FuelEstimator      │                       │
│                    │  (Cost Allocator)   │                       │
│                    └──────────┬──────────┘                       │
│                               │                                  │
│                    ┌──────────▼──────────┐                       │
│                    │  SwiftData Store    │                       │
│                    │  (Local Persistence)│                       │
│                    └─────────────────────┘                       │
│                               │                                  │
│                    ┌──────────▼──────────┐                       │
│                    │      SwiftUI        │                       │
│                    │  (Presentation)     │                       │
│                    └─────────────────────┘                       │
└──────────────────────────────────────────────────────────────────┘

External Hardware:
  [NFC Sticker] ──── inside vehicle (fixed position)
  [BLE Beacon]  ──── inside vehicle (powered)
```

---

## 2. Component Descriptions

### 2.1 NFCService
- **Responsibility:** Initiate an NFC reader session, parse the NDEF payload, and extract the vehicle UUID.
- **Trigger:** Called by the user tapping their phone to the vehicle's NFC tag, or by a background NFC wakeup from the OS.
- **Output:** `vehicleID: UUID` passed to `SessionManager`. Driver identity is not in the tag — it comes from the local profile on the scanning device.
- **Key API:** `NFCNDEFReaderSession`, `NFCNDEFMessage`, background NFC via URL scheme.

### 2.2 BLEService
- **Responsibility:** Continuously scan for the vehicle's BLE beacon during an active session. Report presence/absence to `SessionManager`.
- **Signal:** Emits `beaconPresent: Bool` updates based on RSSI and advertisement timeout.
- **Key API:** `CLLocationManager.startRangingBeacons(satisfying:)` (iBeacon) or `CBCentralManager`.
- **Threshold:** Beacon considered absent after 90 consecutive seconds without advertisement or RSSI ≤ –90 dBm.

### 2.3 LocationService
- **Responsibility:** Collect GPS data during an active session. Buffer `CLLocation` updates into `TripPoint` records. Detect vehicle immobility.
- **Output:** Streams `TripPoint` objects (timestamp, coordinate, speed, horizontalAccuracy) to `SessionManager`.
- **Immobility detection:** Vehicle is "stopped" when speed < 1 m/s for ≥ 180 seconds.
- **Key API:** `CLLocationManager`, `activityType = .automotiveNavigation`, `desiredAccuracy = kCLLocationAccuracyBest`.

### 2.4 SessionManager
- **Responsibility:** Owns the session state machine. Coordinates signals from all three services. Persists sessions via SwiftData.
- **Central orchestrator** — no component communicates directly with another.

### 2.5 FuelEstimator
- **Responsibility:** Given a completed `DrivingSession`, estimate fuel consumption using the model in Week 6. For weeks 1–5, this is a placeholder returning distance-only estimates.
- **Input:** `DrivingSession` (distance km, idleSeconds, aggressiveEvents)
- **Output:** `estimatedFuelLiters: Double`

### 2.6 SwiftData Store
- **Responsibility:** Persist `DriverProfile`, `Vehicle`, `DrivingSession`, `TripPoint`, and `FuelEntry` models using SwiftData (iOS 17+) or Core Data (iOS 16 fallback).
- All queries are performed on the main actor via `@Query` in SwiftUI views or through an async fetch method.

---

## 3. Data Models

```swift
// The local driver profile stored on this phone (one per device)
@Model class DriverProfile {
    var id: UUID
    var name: String
    var createdAt: Date
    var sessions: [DrivingSession]
    // No nfcTagID — the phone IS the identity. Tags encode vehicles, not drivers.
}

// A vehicle registered in the app, identified by its NFC tag
@Model class Vehicle {
    var id: UUID
    var name: String                         // e.g. "Honda Civic"
    var nfcTagID: String                     // URI from tag: "fairfuel://vehicle/<UUID>"
    var fuelEfficiencyLitersPer100Km: Double // used by FuelEstimator
    var sessions: [DrivingSession]
}

// One driving trip from session-start to session-end
@Model class DrivingSession {
    var id: UUID
    var driver: DriverProfile
    var vehicle: Vehicle
    var startTime: Date
    var endTime: Date?          // nil while session is active
    var distanceKm: Double
    var idleSeconds: Double
    var aggressiveAccelEvents: Int
    var hardBrakeEvents: Int
    var estimatedFuelLiters: Double
    var points: [TripPoint]
}

// A single GPS sample during a session
@Model class TripPoint {
    var session: DrivingSession
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speedMps: Double        // meters per second
    var horizontalAccuracy: Double
}

// A refueling event; triggers cost recalculation
@Model class FuelEntry {
    var id: UUID
    var date: Date
    var liters: Double
    var totalCost: Double
    var odometer: Double?       // optional manual odometer reading
}
```

---

## 4. Data Flow

### Session Start Flow
```
Driver taps phone to vehicle NFC tag
        │
        ▼
NFCService parses NDEF payload
        │  vehicleID: UUID
        ▼
SessionManager.startSession(vehicleID:)
        │  looks up Vehicle by nfcTagID in SwiftData
        │  looks up local DriverProfile (only one exists per phone)
        │  creates DrivingSession (driver: localProfile, vehicle: vehicle, endTime: nil)
        │  starts BLEService.startMonitoring()
        │  starts LocationService.startTracking()
        ▼
Session state → .active
```

### Active Session Data Flow
```
LocationService streams TripPoints
        │
        ▼
SessionManager.onLocationUpdate(point:)
        │  appends TripPoint to session
        │  updates distanceKm (haversine)
        │  checks for idle (speed < 1 m/s)
        │  checks for aggressive acceleration (Δspeed > 2.2 m/s per update)
        ▼
SwiftData (auto-saved by SwiftData context)
```

### Session End Flow
```
BLEService: beacon absent ≥ 90s
        AND
LocationService: speed < 1 m/s ≥ 180s
        │
        ▼
SessionManager.endSession()
        │  sets DrivingSession.endTime = now
        │  calls FuelEstimator.estimate(session)
        │  saves estimatedFuelLiters
        │  stops LocationService
        │  stops BLEService
        ▼
Session state → .ended
        │
        ▼
UI shows session summary
```

---

## 5. Session Lifecycle State Machine

```
                     ┌──────────────┐
                     │    IDLE      │  (no active session)
                     └──────┬───────┘
                            │  NFC scan → valid vehicleID
                            ▼
                     ┌──────────────┐
                     │   STARTING   │  (resolving vehicle + local profile, spinning up services)
                     └──────┬───────┘
                            │  services ready (< 3s)
                            ▼
                     ┌──────────────┐
                     │    ACTIVE    │  (GPS + BLE running, accumulating data)
                     └──────┬───────┘
                            │
               ┌────────────┼─────────────────┐
               │            │                 │
    beacon lost             │          user force-ends
    ≥ 90s AND         NFC scan with          (manual override)
    stopped ≥ 3min    same tag, different phone       │
               │            │                 │
               ▼            ▼                 │
        ┌────────────┐  ┌──────────────┐      │
        │  STOPPING  │  │  SWITCHING   │      │
        │ (cooldown) │  │  (end old,   │      │
        └─────┬──────┘  │  start new)  │      │
              │         └──────┬───────┘      │
              │                │              │
              ▼                ▼              ▼
         ┌──────────────────────────────────────┐
         │                ENDED                 │
         │  (session finalized, fuel estimated) │
         └──────────────────────────────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │     IDLE     │
                     └──────────────┘
```

**State Descriptions:**

| State | Description |
|---|---|
| IDLE | No session in progress. App is passive. Location and BLE off. |
| STARTING | NFC scan received. Vehicle resolved from tag ID. Local driver profile loaded. Services initializing. |
| ACTIVE | Session in progress. GPS collecting TripPoints. BLE monitoring beacon. |
| STOPPING | Both termination conditions met. 10-second countdown before finalizing (allows re-entry). |
| SWITCHING | Not applicable in single-phone model. Each phone manages its own session independently. |
| ENDED | Session record finalized. Fuel estimated. UI notification sent. Returns to IDLE. |

**STOPPING Cooldown Rationale:** A 10-second delay before finalizing a session prevents accidental termination (e.g., driver briefly steps out at a gas station while still fueling). If the BLE beacon reappears within the cooldown, the state returns to ACTIVE.

---

## 6. Storage Strategy

**SwiftData (iOS 17+)** is the primary persistence layer.
- `@Model` macro generates the schema automatically.
- `ModelContainer` is initialized at app launch.
- `@Query` in SwiftUI views provides reactive data.
- SwiftData's history tracking can support future sync features.

**Fallback:** For iOS 16 support, Core Data with equivalent entities.

**No cloud sync in V1.** A future V2 could add CloudKit sync via `ModelConfiguration(cloudKitDatabase: .automatic)` with one line change.

---

## 7. Privacy Design

| Principle | Implementation |
|---|---|
| Minimal data collection | GPS only runs during ACTIVE session state. |
| No background idle tracking | `LocationService.stopTracking()` called immediately on session end. |
| On-device only | No data leaves the device in V1. |
| User control | Driver can manually end a session at any time. Sessions are visible and deletable. |
| Permission transparency | App shows clear purpose strings in Info.plist for location, NFC, and Bluetooth. |

---

## 8. Next Steps (Week 3)

- Implement `NFCService` with `NFCNDEFReaderSession` and vehicle URI scheme parsing.
- Implement first-launch driver profile creation UI (name entry, stored locally).
- Implement vehicle setup UI with NFC tag writing (`fairfuel://vehicle/<UUID>`).
- Wire NFC scan output into `SessionManager.startSession(vehicleID:)`.
- Write unit tests for NFC payload parsing.
