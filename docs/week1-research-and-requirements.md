# Week 1 – Requirements and Background Research

## 1. Technology Research

### 1.1 NFC on iOS (Core NFC)

**Capabilities:**
- iOS 13+ supports both tag reading and background tag reading via Core NFC.
- `NFCNDEFReaderSession` is the primary API for reading NDEF-formatted tags (the standard for NFC business cards, stickers, etc.).
- `NFCTagReaderSession` provides lower-level access to ISO 7816, ISO 15693, FeliCa, and MiFare tags.
- Background tag reading (iOS 13+): The OS can wake the app when an NDEF tag is scanned without the app being open, but only for specific NDEF record types. This is useful for driver identification.

**Constraints:**
- NFC scanning requires explicit user action (bring phone within ~4cm of tag) — no passive background polling.
- The entitlement `com.apple.developer.nfc.readersession.formats` must be added to the app.
- A reader session times out after 60 seconds of inactivity.
- NFC writing to tags requires `NFCNDEFReaderSession` in read-write mode (iOS 13+).
- Background NFC wakeup only works for Universal Links (`https://`) or custom URL schemes embedded in the NDEF payload.
- Physical NFC tag cost: NTAG213/215 stickers cost < $1 each and hold 144–504 bytes, sufficient to store a unique driver ID URI.

**Design Decision:** Each driver will be assigned a unique UUID written to their NFC tag. The tag payload will use a custom URI scheme (`fairfuel://driver/<UUID>`) to trigger app launch via background tag reading.

---

### 1.2 BLE Beacon Behavior (Core Bluetooth)

**Capabilities:**
- `CBCentralManager` is used to scan for BLE peripherals by service UUID.
- RSSI (Received Signal Strength Indicator) values allow rough proximity estimation.
- A BLE beacon (e.g., Estimote Sticker, Tile, or a custom ESP32/nRF52 device) is placed inside the vehicle and advertises a fixed service UUID.
- Core Bluetooth can scan in the background when the app has the `bluetooth-central` background mode enabled.

**Constraints:**
- iOS background BLE scanning is duty-cycled; the OS may delay scanning to save battery. Scan intervals increase when the screen is off.
- `CBCentralManagerScanOptionAllowDuplicatesKey: true` is required to receive repeated RSSI updates, but this only works reliably in the foreground.
- Apple's iBeacon protocol (`CLBeaconRegion` / `CLLocationManager`) provides more reliable background ranging but requires an MFi-certified beacon.
- Signal strength alone is not perfectly reliable — RSSI varies with phone orientation, obstructions, and radio interference.
- Detecting "departure" requires sustained signal loss (e.g., RSSI below threshold or no advertisement received for N seconds).

**Design Decision:** Use `CLLocationManager` iBeacon ranging for background reliability if an iBeacon-compatible beacon is used. Otherwise, use Core Bluetooth with a conservative signal-loss timeout (90 seconds below –85 dBm) combined with vehicle immobility detection before ending a session.

---

### 1.3 Smartphone-Based Trip Detection (Core Location)

**Capabilities:**
- `CLLocationManager` provides GPS coordinates, speed (m/s), and heading.
- `desiredAccuracy` can be set to `kCLLocationAccuracyBest` (~5m) during active sessions.
- `activityType = .automotiveNavigation` optimizes the location filter for driving.
- Speed data from GPS is typically averaged and smoothed by the OS — usable for detecting stops/idle time.
- Significant Location Change mode (`startMonitoringSignificantLocationChanges`) wakes the app with ~500m precision but uses minimal battery.

**Constraints:**
- iOS requires user to grant "Always" location permission for background tracking.
- Background location execution is limited; the app must use the `location` background mode.
- Continuous GPS is battery-intensive. The system uses `pausesLocationUpdatesAutomatically = false` to prevent unwanted pauses during sessions.
- Indoor environments and tunnels degrade GPS accuracy.
- Speed via GPS is reliable above ~5 mph; below that it can be noisy.

**Derived Metrics for Fuel Estimation:**
| Metric | Source | Notes |
|---|---|---|
| Distance | Accumulated GPS coordinates | Haversine formula between consecutive points |
| Average speed | GPS speed | Filter outliers (> 120 mph) |
| Idle time | Periods where speed < 2 mph for > 30s | Indicates engine idling |
| Aggressive acceleration | Speed delta > 5 mph/s | Contributes to higher fuel consumption |
| Hard braking | Speed delta < –5 mph/s | Indicates inefficient driving |

---

## 2. System Requirements

### 2.1 Functional Requirements

| ID | Requirement |
|----|-------------|
| FR-01 | The system shall allow a driver to start a session by scanning their unique NFC tag inside the vehicle. |
| FR-02 | The system shall automatically end a session when the vehicle has been stationary for at least 3 minutes AND the BLE beacon signal is lost for at least 90 seconds. |
| FR-03 | The system shall record GPS distance, average speed, idle time, and aggressive driving events for each session. |
| FR-04 | The system shall associate all session data with the driver who initiated it. |
| FR-05 | The system shall allow entry of a fuel refill event (gallons/liters purchased, cost). |
| FR-06 | The system shall calculate each driver's share of a fuel cost based on estimated fuel consumption since the last refill. |
| FR-07 | The system shall support at least 4 simultaneous driver profiles per vehicle. |
| FR-08 | The system shall display a summary of trips and fuel usage per driver. |

### 2.2 Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | The app shall not track location outside of an active driving session. |
| NFR-02 | All data shall be stored locally on-device; no server required for core functionality. |
| NFR-03 | Battery impact during an active session shall not exceed 5% per hour of normal driving. |
| NFR-04 | Session start shall be completable within 5 seconds of NFC scan. |
| NFR-05 | The app shall be compatible with iOS 16.0 and later. |
| NFR-06 | The system shall be vehicle-agnostic and require no OBD-II or CAN bus access. |

---

## 3. Constraints

| Constraint | Detail |
|---|---|
| iOS background execution | Background location requires "Always" permission; BLE scanning is duty-cycled. Session termination logic must account for delayed BLE events. |
| NFC tag writing | Driver tags must be pre-written with the correct NDEF payload (app can do this, or tags can be pre-provisioned). |
| Fuel estimation accuracy | Without OBD-II, fuel usage is estimated from driving behavior. Results are consistent and fair, not necessarily exact. |
| Single driver per session | The system assumes one driver per session; passengers do not affect attribution. |
| BLE beacon hardware | A BLE beacon must be physically placed in the vehicle. The system supports iBeacon-compatible or custom BLE peripherals. |
| No real-time sharing | V1 does not require a backend or multi-device sync; all data is local to the driver's phone. |

---

## 4. Success Metrics

| Metric | Target |
|---|---|
| Session start accuracy | NFC-initiated session starts within 5 seconds, 99% of scans. |
| Session end accuracy | Session ends within 5 minutes of driver leaving the vehicle, with < 5% false terminations. |
| Fuel estimate consistency | Per-mile fuel consumption estimates vary < 15% for the same driver across similar trips. |
| Cost split fairness | Allocation error compared to actual odometer/fuel usage is < 10% over a month of multi-driver use. |
| Battery usage | < 5% battery drain per hour of active session on a modern iPhone. |
| Usability | A new driver can complete setup (NFC tag pairing, first session) in under 3 minutes. |

---

## 5. Next Steps (Week 2)

- Design the full system architecture and component diagram.
- Define the data model (Driver, Session, TripPoint, FuelEntry).
- Specify the session lifecycle state machine.
- Choose local storage strategy (Core Data vs. SwiftData).
