# Week 4 – Session Reliability, Group Sync, and Imperial Units

## Objectives
- Resolve session auto-end failure in real-world testing
- Replace NFC-based session triggering with passive BLE detection
- Implement cross-device group sync via Supabase
- Switch all units to imperial (miles, gallons, MPG)
- Add vehicle make/model/year database with automatic MPG lookup
- Add edit and correction capabilities for trips and vehicles

---

## 1. Pivot: NFC Trigger Replaced by BLE Passive Detection

Week 3 implemented NFC tag scanning as the session start trigger. Real-world testing revealed a fundamental usability problem: the driver must remember to tap their phone to the tag every single time they get in the car. Forgetting to scan means no session is recorded, and a missed session means inaccurate cost splits — the exact problem the app is trying to solve.

The system was redesigned so that sessions start and end **without any user action**. The vehicle's iBeacon now serves as both the session trigger and the termination signal.

### New Session State Machine

| State | Trigger |
|---|---|
| IDLE → PENDING | BLE beacon region entry detected |
| PENDING → ACTIVE | 3 consecutive GPS readings ≥ 2.0 m/s (~7 km/h) |
| ACTIVE → STOPPING | Beacon absent ≥ 90s **or** GPS immobility ≥ 180s |
| STOPPING → ENDED | 10-second countdown completes without beacon return |
| STOPPING → ACTIVE | Beacon reappears within countdown (e.g. driver returns to car) |

The triple GPS confirmation step before committing to ACTIVE prevents false sessions when a driver loads groceries near the vehicle — the beacon may be in range, but the phone isn't moving at driving speed.

### Updated Files

| File | Change |
|---|---|
| `Services/BLEService.swift` | Uses `CLBeaconRegion` for hardware-efficient region monitoring; `startRangingBeacons` during active sessions; 90s absence timer |
| `Services/SessionManager.swift` | Removed `NFCService` dependency; wired `BLEServiceDelegate` and `LocationServiceDelegate`; new PENDING state |
| `Views/AddVehicleView.swift` | Removed NFC write flow; replaced with iBeacon UUID entry |
| `Views/HomeView.swift` | Updated state display for PENDING and the new confirmation-based flow |

`NFCService.swift` was removed. NFC tag writing is no longer part of the setup flow.

---

## 2. Session Auto-End Fix

During real-world testing the session never auto-ended after parking. The root cause was a logic gap in the `beaconPresenceChanged` handler inside `SessionManager`:

```swift
// Before fix — only handled STOPPING, not ACTIVE
func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool) {
    if isPresent {
        if case .stopping(let session) = state { cancelStoppingCountdown(for: session) }
    }
    // ACTIVE state: nothing happened here
}
```

The intended design required two independent conditions to both be true at exactly the same moment: GPS immobility (180s timer) AND beacon absence (90s timer). If the 180s immobility timer fired while the beacon was still present, the handler returned without starting the countdown. Even once the beacon later went absent, there was no second trigger — the session was permanently stuck in ACTIVE.

**Fix:** When the beacon goes absent and the session is in ACTIVE state, begin the stopping countdown immediately. This mirrors the original intent and is more intuitive: if the beacon has been unseen for 90 seconds, the driver has left the vehicle.

```swift
// After fix
} else {
    if case .active(let session) = state {
        beginStoppingCountdown(for: session)
    }
}
```

The 10-second stopping countdown still provides a grace period, and a beacon return during that window cancels it — so brief BLE signal drops do not terminate sessions prematurely.

---

## 3. Distance Tracking Accuracy

GPS distance calculations were producing results significantly larger than actual trip distance. The bug was in `updateSessionMetrics`, which retrieved the "previous" GPS point by calling `session.points.dropLast().last` on the SwiftData relationship array.

SwiftData does not guarantee insertion order in relationship arrays. The item returned by `.last` after `dropLast()` could be any point from the session — potentially one recorded several minutes earlier. The straight-line distance between two such non-adjacent points would be far larger than the distance between two consecutive readings, inflating the total.

**Fix:** A `lastTrackedLocation: CLLocation?` property is maintained directly in `SessionManager`. Each GPS callback stores the current location in memory and passes it to the metrics function. No SwiftData reads occur during the calculation. Additionally, the horizontal accuracy filter was tightened from 50m to 20m, and the minimum movement threshold raised from 5m to 10m to reduce noise accumulation.

---

## 4. Group Sync via Supabase

FR-02 required cost splits to reflect trips from all phones sharing a vehicle. A backend sync layer was added to satisfy this without requiring a paid Apple Developer account (CloudKit requires a paid membership).

### Why Supabase

Supabase was chosen because an existing account was already in use. It provides a PostgreSQL database with a REST API accessible via standard `URLSession` calls — no additional SDK or Swift Package is required.

A new Supabase project (`FairFuel`) was created with the following schema:

```sql
CREATE TABLE group_sessions (
    id TEXT PRIMARY KEY,           -- session UUID, prevents duplicate pushes
    group_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    vehicle_name TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    distance_km DOUBLE PRECISION NOT NULL DEFAULT 0,
    idle_seconds DOUBLE PRECISION NOT NULL DEFAULT 0,
    estimated_fuel_liters DOUBLE PRECISION NOT NULL DEFAULT 0,
    aggressive_accel_events INTEGER NOT NULL DEFAULT 0,
    hard_brake_events INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

Row-level security is enabled with policies allowing anonymous read and insert, keeping setup simple without user authentication.

### Group Code Design

Each household generates an 8-character alphanumeric code (e.g. `A1B2C3D4`, displayed as `A1B2-C3D4`). Any phone that joins with the same code shares the same `group_id` tag on all pushed sessions.

### Sync Flow

1. Session ends → `SessionManager.finalizeSession` → saves to SwiftData → if `groupID` is set, fires `CloudKitService.shared.pushSession` in a detached Task
2. Push is an HTTP POST with `Prefer: resolution=merge-duplicates` — idempotent, safe to retry
3. `CostSplitView.loadBreakdown()` — if a group is active, calls `fetchSessions(groupID:since:until:)` for the date window; uses `FuelEstimator.allocateCost(totalCost:sessions:[RemoteSession])` to build the breakdown; falls back to local-only if the fetch returns empty

### New Files

| File | Purpose |
|---|---|
| `Services/CloudKitService.swift` | Supabase REST client: `pushSession`, `fetchSessions`, `RemoteSession` struct |
| `Services/GroupManager.swift` | `ObservableObject` singleton; stores group ID in `UserDefaults`; `createGroup()`, `join(code:)`, `leaveGroup()` |
| `Views/GroupSetupView.swift` | Sheet with Create (generate + share) and Join (XXXX-XXXX input) modes |

### Modified Files

| File | Change |
|---|---|
| `Services/FuelEstimator.swift` | Added `allocateCost(totalCost:sessions:[RemoteSession])` overload keyed by driver name |
| `Views/CostSplitView.swift` | Async `loadBreakdown()`; Syncing… indicator; remote trip rows |
| `Views/DriversView.swift` | Group section: show code, Share, Leave, Create, Join |
| `App/FairFuelApp.swift` | Injects `GroupManager.shared` as environment object |

---

## 5. Imperial Units

All previous versions displayed metric values (km, L, L/100km). The app is used in the United States, so all display units were converted to imperial. Internal storage remains metric to avoid data migrations.

A new `Units.swift` enum provides conversion helpers:

| Function | Conversion |
|---|---|
| `kmToMiles` | × 0.621371 |
| `litersToGallons` | × 0.264172 |
| `gallonsToLiters` | × 3.78541 |
| `mpgToLitersPer100Km` | 235.214 ÷ MPG |
| `litersPer100KmToMPG` | 235.214 ÷ L/100km |

Fuel entry input was changed from liters to gallons. The entered value is converted to liters on save, preserving the existing `FuelEntry.liters` storage field. Odometer input changed to miles, stored as km.

Any fuel entries previously logged with a gallon value in the old liters field will display an incorrect price per gallon. Users must delete and re-enter those entries.

---

## 6. Vehicle Database and MPG Lookup

The `Vehicle` model was extended with three optional fields — `year: Int?`, `make: String?`, `vehicleModel: String?` — using SwiftData's lightweight migration (optional fields with no default require no manual migration step).

`VehicleDatabase.swift` contains EPA combined MPG estimates for approximately 150 models across 25 makes. The `AddVehicleView` was redesigned with cascading pickers:

1. **Make** → filters model list
2. **Model** → auto-fills MPG from database
3. **Year** → 2000 to present
4. **Name** → auto-fills as "2024 Toyota Camry", customizable
5. **MPG** → auto-filled, manually overridable
6. **Beacon UUID** → unchanged

Electric vehicles are represented in the database with MPG = 0. The app stores `fuelEfficiencyLitersPer100Km = 0` and `FuelEstimator` returns zero for those sessions, correctly excluding them from fuel cost allocation.

An `EditVehicleView` was also added, accessible via swipe-right on any vehicle row in Profile & Vehicles.

---

## 7. Edit and Correction Capabilities

Real sessions may record incorrect data due to GPS conditions or beacon timing. Two edit flows were added.

### Trip Editing (`EditTripView`)
Accessible via swipe-right on any row in Trip History. Editable fields:
- Distance (miles)
- Start and end times
- Driver reassignment (picker from all local profiles)
- Vehicle reassignment (picker from all registered vehicles)

Fuel estimate is recalculated on save using the edited distance and the selected vehicle's efficiency. Trip deletion is also available via swipe-left.

### Profile Rename
Accessible via swipe-left on the driver name in Profile & Vehicles → Rename.

**Note:** Editing a trip locally does not update the Supabase record if the session was already pushed. The remote record retains the original values. Re-push on edit is a planned improvement.

---

## 8. Testing Required

The following areas need structured testing before the app can be considered reliable for real-world cost splitting:

### Session Lifecycle
- **False start prevention:** Confirm PENDING → cancelled (not ACTIVE) when loading items into the car without driving
- **False end prevention:** Confirm session does not end during a brief stop (traffic light, drive-through) where the beacon remains in range
- **Tunnel handling:** Confirm GPS accuracy filter correctly ignores low-accuracy points; session should not accumulate phantom distance in dead zones
- **Background execution:** Verify session continues recording correctly when the app is backgrounded for a full trip duration
- **Cold start:** Confirm beacon region monitoring resumes correctly after the app is force-quit and relaunched

### Distance and Fuel Accuracy
- **Multi-trip consistency:** Drive the same known route 5+ times and compare recorded distances for variance
- **Idle detection:** Park with engine running for 5 minutes mid-trip and confirm `idleSeconds` accumulates
- **Event detection:** Perform deliberate hard acceleration and braking; confirm event counters increment correctly

### Group Sync
- **Simultaneous sessions:** Both phones drive at the same time; confirm both records appear in the cost split
- **Offline push:** Complete a session with no network; confirm push succeeds when connectivity is restored (currently not implemented — push is fire-and-forget)
- **Wrong group code:** Enter an invalid code; confirm cost split falls back to local data gracefully

### Cost Split Accuracy
- **Known-distance validation:** Drive measured routes, log a fill-up, and verify the allocation percentages match the distance ratio
- **Single driver:** Confirm 100% is allocated when only one driver has sessions in the window
- **No sessions:** Confirm the view handles a fill-up with no preceding sessions without crashing

---

## 9. Planned Features

| Feature | Rationale |
|---|---|
| Re-push edited trips to Supabase | Edits currently only update local SwiftData; remote records become stale |
| Offline session queue | Trips completed without network should be held and pushed when connectivity returns |
| Multi-vehicle households | A household with two cars needs separate group codes or a vehicle filter on the cost split |
| Push notifications | Notify the other driver when a new session is synced to the group |
| Trip map view | Display the GPS route for any completed session using MapKit |
| Fuel price lookup | Auto-fill current local gas price when logging a fill-up |
| Running cost summary | Running per-driver total between fill-ups, not just at fill-up time |
| Widget | Home screen widget showing the current session status or last split |
| Export | CSV or PDF export of sessions and cost splits for expense tracking |
| Group code validation | Verify a code exists in Supabase before accepting it, with a clear error for new empty groups |

---

## 10. Next Steps (Week 5)

- Implement offline session queue with retry logic
- Add MapKit trip route view to TripHistoryView
- Build multi-vehicle group filtering in CostSplitView
- Begin structured field testing of distance accuracy across multiple known routes
