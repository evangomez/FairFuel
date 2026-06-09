# FairFuel

An iOS app that fairly splits fuel costs among drivers who share a vehicle, using BLE beacon auto-detection and GPS trip tracking.

## What It Does

FairFuel solves the "who drove how much?" problem for families and housemates sharing a car. A small iBeacon-compatible hardware beacon mounted inside the vehicle triggers trip tracking automatically — no buttons to tap. GPS records distance, idle time, and driving behavior. When someone fills up the tank, the app splits the cost proportionally based on each driver's estimated fuel consumption.

- **Automatic trip start/end**: phone detects the in-car beacon via BLE; no manual interaction required
- **GPS tracking**: distance, idle time, aggressive acceleration, hard braking
- **Fuel cost splitting**: proportional by estimated consumption since the last fill-up
- **Group sync**: household members share a group code; costs are split across all drivers

## Architecture

```
FairFuelApp/
├── App/
│   └── FairFuelApp.swift          # App entry, SwiftData container with file protection
├── Models/
│   ├── Driver.swift               # @Model: local driver profile (one per device)
│   ├── Vehicle.swift              # @Model: vehicle + beacon UUID + fuel efficiency
│   ├── DrivingSession.swift       # @Model: trip record with summary metrics
│   ├── TripPoint.swift            # @Model: GPS sample (purged after session finalizes)
│   └── FuelEntry.swift            # @Model: fill-up event (liters, cost, odometer)
├── Services/
│   ├── BLEService.swift           # iBeacon region monitoring and ranging
│   ├── LocationService.swift      # GPS tracking with accuracy filtering
│   ├── SessionManager.swift       # State machine: idle→pending→active→stopping→ended
│   ├── FuelEstimator.swift        # Fuel consumption model (distance + idle + events)
│   ├── KeychainService.swift      # Keychain save/load/delete (ready for backend auth)
│   ├── CloudKitService.swift      # Supabase REST client for group sync
│   ├── GroupManager.swift         # Group code creation/join
│   ├── NotificationService.swift  # Local notifications + background refresh
│   ├── OfflineQueue.swift         # Retry queue for failed sync requests
│   ├── Units.swift                # Unit conversions (km↔mi, L↔gal, MPG↔L/100km)
│   ├── Double+Units.swift         # Double extension: distanceDisplay, fuelDisplay
│   └── VehicleDatabase.swift      # EPA MPG lookup table (~1000 models)
└── Views/
    ├── HomeView.swift             # Active session screen with debug simulation menu
    ├── DriversView.swift          # Profile + vehicle management
    ├── FuelView.swift             # Fill-up history + current tank cost estimate
    ├── AddFuelEntryView.swift     # Log a fill-up (gallons, cost, odometer)
    ├── AddVehicleView.swift       # Add vehicle with make/model/year/MPG lookup
    ├── EditVehicleView.swift      # Edit vehicle settings
    ├── TripHistoryView.swift      # Trip log with metrics
    ├── CostSplitView.swift        # Per-driver cost breakdown for a fill-up
    ├── AddManualTripView.swift    # Manual trip entry without beacon
    ├── EditTripView.swift         # Edit a saved trip
    └── GroupSetupView.swift       # Create / join a household group
```

## Hardware Requirements

- **BLE beacon**: any iBeacon-compatible beacon (MINEW, Estimote, Kontakt.io, or ESP32/nRF52)
  - Mount inside the vehicle; power via USB or battery
  - Note the beacon's UUID from the manufacturer's app (e.g. BeaconSET for MINEW)
  - Enter the UUID in the app when adding a vehicle

Physical device required — BLE and GPS do not work in the iOS Simulator.

## Setup (Xcode)

1. Open `FairFuel.xcodeproj` in Xcode.
2. Set the deployment target to **iOS 18.2** or later.
3. Ensure the app target includes `PrivacyInfo.xcprivacy` as a resource (add via Xcode if missing).
4. Build and run on a physical iPhone.

The app can be fully tested without hardware using the **Debug menu** in the bottom toolbar of the Session tab, which simulates beacon detection and driving confirmation.

## Security Notes

**Beacon spoofing**: iBeacon UUIDs are broadcast in plaintext. The beacon identifies the vehicle — it is not an authentication token. Local trip data can be triggered by a spoofed beacon, but the Supabase backend enforces Row Level Security: only users with a `memberships` row for a vehicle can write trips to it. See `SessionManager.enterPending()` for the security contract comment.

**Data storage**: The SwiftData store is opened with `FileProtectionType.completeUntilFirstUserAuthentication`. Raw GPS breadcrumbs (`TripPoint` records) are deleted after each session is finalized; only the summary metrics are kept.

**Auth tokens**: `KeychainService` stores auth tokens with `kSecAttrAccessibleAfterFirstUnlock` (not `kSecAttrAccessibleWhenUnlocked`) so background token refresh works during active trips.

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | Local app hardening (BLE-only, file protection, privacy manifest) | ✅ Complete |
| 2 | Supabase backend, Sign in with Apple, household invites, Realtime sync | Planned |
| 3 | StoreKit 2 / RevenueCat — FairFuel Pro analytics & export | Planned |
| 4 | App Store submission | Planned |
