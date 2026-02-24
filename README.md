# FairFuel

A multi-driver gas usage tracking system using NFC and Bluetooth Low Energy.

## Project Summary

FairFuel is a vehicle-agnostic iOS app that fairly attributes fuel costs among multiple drivers of a shared vehicle. Drivers identify themselves by scanning an NFC tag inside the car. A BLE beacon detects when a driver has left. GPS data during the trip estimates relative fuel consumption based on distance, idle time, and driving behavior.

## Weekly Build Plan

| Week | Focus | Status |
|------|-------|--------|
| 1 | Requirements & Research | ✅ Complete |
| 2 | Architecture & Design | ✅ Complete |
| 3 | NFC Driver Identification | Pending |
| 4 | BLE Proximity Detection | Pending |
| 5 | Trip Tracking & GPS | Pending |
| 6 | Fuel Estimation Model | Pending |
| 7 | Cost Allocation & UI | Pending |
| 8 | Testing & Final Report | Pending |

## Project Structure

```
FairFuel/
├── docs/
│   ├── week1-research-and-requirements.md
│   └── week2-architecture-and-design.md
└── FairFuelApp/
    ├── App/
    │   └── FairFuelApp.swift          # App entry point, SwiftData container
    ├── Models/
    │   ├── Driver.swift               # @Model: driver profile + NFC tag ID
    │   ├── DrivingSession.swift       # @Model: trip record per driver
    │   ├── TripPoint.swift            # @Model: GPS sample during session
    │   └── FuelEntry.swift            # @Model: refueling event
    ├── Services/
    │   ├── NFCService.swift           # Core NFC tag reading + payload parsing
    │   ├── BLEService.swift           # iBeacon ranging for proximity detection
    │   ├── LocationService.swift      # GPS tracking + immobility detection
    │   ├── SessionManager.swift       # State machine orchestrating all services
    │   └── FuelEstimator.swift        # Fuel consumption estimation (placeholder)
    └── Views/
        ├── ContentView.swift          # TabView shell
        ├── HomeView.swift             # Active session screen (Week 7)
        ├── DriversView.swift          # Driver list (Week 3)
        └── FuelView.swift             # Fuel entries (Week 7)
```

## Setup (Xcode)

1. Create a new Xcode project: **iOS App**, Swift, SwiftUI.
2. Set deployment target to **iOS 17.0**.
3. Add all `.swift` files from `FairFuelApp/` to the project target.
4. Add required entitlements in the `.entitlements` file:
   - `com.apple.developer.nfc.readersession.formats` → `["NDEF"]`
5. Add required `Info.plist` keys:
   - `NFCReaderUsageDescription` — why NFC is used
   - `NSLocationAlwaysAndWhenInUseUsageDescription` — why location is always needed
   - `NSLocationWhenInUseUsageDescription`
   - `NSBluetoothAlwaysUsageDescription`
6. Enable background modes: **Location updates**, **Uses Bluetooth LE accessories**.
7. Build and run on a physical iPhone (NFC and BLE do not work in the simulator).

## Hardware Requirements

- **NFC tags**: NTAG213 or NTAG215 stickers (~$0.50 each). One per driver.
  - Write the payload `fairfuel://driver/<UUID>` using an NFC writing app or the app's built-in writer (Week 3).
- **BLE beacon**: Any iBeacon-compatible beacon (Estimote, Kontakt.io, or a custom ESP32/nRF52 device).
  - Configure with UUID `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0` (or update `BLEService.beaconUUID`).
  - Mount inside the vehicle and power via USB or battery.
