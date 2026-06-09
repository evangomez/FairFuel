import Foundation

// Supabase REST client — named CloudKitService so no other files need renaming.

struct RemoteSession {
    let recordName: String
    let vehicleID: String        // vehicle_id from the trips table
    let driverName: String
    let vehicleName: String
    let startTime: Date
    let endTime: Date
    let distanceKm: Double
    let idleSeconds: Double
    let estimatedFuelLiters: Double
    let aggressiveAccelEvents: Int
    let hardBrakeEvents: Int
}

struct RemoteFillUp {
    let id: String
    let liters: Double
    let totalCost: Double
    let odometer: Double?
    let date: Date
    let isSettled: Bool
}

struct RemoteVehicle {
    let id: String
    let name: String
    let beaconUUID: String
    let make: String?
    let model: String?
    let year: Int?
    let fuelEfficiencyLitersPer100Km: Double
}

final class CloudKitService {
    static let shared = CloudKitService()

    private let base = "\(SupabaseConfig.projectURL)/rest/v1"
    private let rpcBase = "\(SupabaseConfig.projectURL)/rest/v1/rpc"
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private init() {}

    // MARK: - Trips

    func pushTrip(_ session: DrivingSession, vehicleID: String) async {
        guard let endTime = session.endTime,
              let driverName = session.driver?.name,
              let vehicleName = session.vehicle?.name else { return }
        var body: [String: Any] = [
            "id": session.id.uuidString,
            "vehicle_id": vehicleID,
            "driver_id": AuthService.shared.userId as Any,
            "driver_name": driverName,
            "vehicle_name": vehicleName,
            "start_time": iso.string(from: session.startTime),
            "end_time": iso.string(from: endTime),
            "distance_km": session.distanceKm,
            "idle_seconds": session.idleSeconds,
            "estimated_fuel_liters": session.estimatedFuelLiters,
            "aggressive_accel_events": session.aggressiveAccelEvents,
            "hard_brake_events": session.hardBrakeEvents,
            "is_manual": session.isManual
        ]
        // Remove driver_id key if nil so Postgres accepts null correctly
        if AuthService.shared.userId == nil { body.removeValue(forKey: "driver_id") }
        await upsert(table: "trips", body: body)
    }

    func fetchTrips(vehicleIDs: [String], since: Date, until: Date) async -> [RemoteSession] {
        guard !vehicleIDs.isEmpty else { return [] }
        // Supabase PostgREST in() filter: vehicle_id=in.(uuid1,uuid2,...)
        let inFilter = "(\(vehicleIDs.joined(separator: ",")))"
        let rows = await fetchSimple(table: "trips", queryItems: [
            URLQueryItem(name: "vehicle_id", value: "in.\(inFilter)"),
            URLQueryItem(name: "end_time", value: "gte.\(iso.string(from: since))"),
            URLQueryItem(name: "end_time", value: "lte.\(iso.string(from: until))")
        ])
        return rows.compactMap { remoteSession(from: $0) }
    }

    // MARK: - Fuel Entries

    func pushFuelEntry(_ entry: FuelEntry, vehicleID: String) async {
        var body: [String: Any] = [
            "id": entry.id.uuidString,
            "vehicle_id": vehicleID,
            "liters": entry.liters,
            "total_cost": entry.totalCost,
            "date": iso.string(from: entry.date),
            "is_settled": entry.isSettled
        ]
        if let userId = AuthService.shared.userId { body["logged_by"] = userId }
        if let odo = entry.odometer { body["odometer"] = odo }
        await upsert(table: "fuel_entries", body: body)
    }

    func fetchFuelEntries(vehicleIDs: [String]) async -> [RemoteFillUp] {
        guard !vehicleIDs.isEmpty else { return [] }
        let inFilter = "(\(vehicleIDs.joined(separator: ",")))"
        let rows = await fetchSimple(table: "fuel_entries",
                                     queryItems: [URLQueryItem(name: "vehicle_id", value: "in.\(inFilter)")])
        return rows.compactMap { remoteFillUp(from: $0) }
    }

    func updateSettled(entryID: String, vehicleID: String, isSettled: Bool) async {
        var components = URLComponents(string: "\(base)/fuel_entries")!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(entryID)"),
            URLQueryItem(name: "vehicle_id", value: "eq.\(vehicleID)")
        ]
        guard let url = components.url,
              let body = try? JSONSerialization.data(withJSONObject: ["is_settled": isSettled]) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.httpBody = body
        addHeaders(to: &req)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                print("[Supabase] updateSettled failed: HTTP \(http.statusCode)")
            }
        } catch {
            print("[Supabase] updateSettled error: \(error)")
        }
    }

    // MARK: - Vehicles & Memberships

    /// Upserts vehicle to `vehicles`, then upserts an owner membership for the current user.
    func pushVehicle(_ vehicle: Vehicle) async {
        var body: [String: Any] = [
            "id": vehicle.id.uuidString,
            "name": vehicle.name,
            "beacon_uuid": vehicle.beaconUUID,
            "fuel_efficiency_liters_per_100km": vehicle.fuelEfficiencyLitersPer100Km
        ]
        if let make = vehicle.make { body["make"] = make }
        if let model = vehicle.vehicleModel { body["model"] = model }
        if let year = vehicle.year { body["year"] = year }

        let vehicleOK = await upsertReturning(table: "vehicles", body: body)
        guard vehicleOK, let userId = AuthService.shared.userId else { return }

        // Create owner membership
        let membershipBody: [String: Any] = [
            "user_id": userId,
            "vehicle_id": vehicle.id.uuidString,
            "role": "owner"
        ]
        await upsert(table: "memberships", body: membershipBody)
    }

    /// Returns all vehicles the current user has membership in.
    func fetchMemberVehicles() async -> [RemoteVehicle] {
        // Fetch memberships for current user, then resolve vehicle IDs
        guard AuthService.shared.isAuthenticated else { return [] }
        let memberships = await fetchSimple(table: "memberships", queryItems: [
            URLQueryItem(name: "select", value: "vehicle_id")
        ])
        let vehicleIDs = memberships.compactMap { $0["vehicle_id"] as? String }
        guard !vehicleIDs.isEmpty else { return [] }

        let inFilter = "(\(vehicleIDs.joined(separator: ",")))"
        let rows = await fetchSimple(table: "vehicles",
                                     queryItems: [URLQueryItem(name: "id", value: "in.\(inFilter)")])
        return rows.compactMap { remoteVehicle(from: $0) }
    }

    // MARK: - Invites

    /// Generates an 8-char code, inserts the invite row, returns formatted XXXX-XXXX code.
    func createInvite(vehicleID: String) async -> String? {
        guard let userId = AuthService.shared.userId else { return nil }
        let rawCode = generateInviteCode()
        let expiresAt = Date().addingTimeInterval(7 * 24 * 3600) // 7 days
        let body: [String: Any] = [
            "vehicle_id": vehicleID,
            "created_by": userId,
            "code": rawCode,
            "expires_at": iso.string(from: expiresAt)
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(base)/invites") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        addHeaders(to: &req)
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("[Supabase] createInvite failed: HTTP \(http.statusCode) — \(msg)")
                return nil
            }
            // Return formatted XXXX-XXXX
            let formatted = "\(rawCode.prefix(4))-\(rawCode.dropFirst(4))"
            print("[Supabase] Invite created: \(formatted)")
            return formatted
        } catch {
            print("[Supabase] createInvite error: \(error)")
            return nil
        }
    }

    /// Calls RPC redeem_invite. Returns (vehicleID, vehicleName) on success.
    func redeemInvite(code: String) async -> (vehicleID: String, vehicleName: String)? {
        let clean = code.uppercased().replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: "\(rpcBase)/redeem_invite") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["invite_code": clean])
        addHeaders(to: &req)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("[Supabase] redeemInvite failed: HTTP \(http.statusCode) — \(msg)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success,
                  let vehicleID = json["vehicle_id"] as? String,
                  let vehicleName = json["vehicle_name"] as? String else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("[Supabase] redeemInvite — server returned failure: \(msg)")
                return nil
            }
            print("[Supabase] Invite redeemed — vehicle: \(vehicleName)")
            return (vehicleID: vehicleID, vehicleName: vehicleName)
        } catch {
            print("[Supabase] redeemInvite error: \(error)")
            return nil
        }
    }

    // MARK: - Generic helpers

    private func upsert(table: String, body: [String: Any]) async {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(base)/\(table)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        addHeaders(to: &req)
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: respData, encoding: .utf8) ?? ""
                print("[Supabase] Upsert \(table) failed: HTTP \(http.statusCode) — \(msg)")
                OfflineQueue.shared.enqueue(table: table, bodyData: bodyData)
            }
        } catch {
            print("[Supabase] Upsert \(table) error: \(error)")
            OfflineQueue.shared.enqueue(table: table, bodyData: bodyData)
        }
    }

    /// Like upsert but returns true on success — used when chaining (e.g. vehicle + membership).
    @discardableResult
    private func upsertReturning(table: String, body: [String: Any]) async -> Bool {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(base)/\(table)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        addHeaders(to: &req)
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: respData, encoding: .utf8) ?? ""
                print("[Supabase] Upsert \(table) failed: HTTP \(http.statusCode) — \(msg)")
                OfflineQueue.shared.enqueue(table: table, bodyData: bodyData)
                return false
            }
            return true
        } catch {
            print("[Supabase] Upsert \(table) error: \(error)")
            OfflineQueue.shared.enqueue(table: table, bodyData: bodyData)
            return false
        }
    }

    // Used by OfflineQueue.drainIfNeeded — does NOT re-enqueue on failure.
    func upsertRaw(table: String, bodyData: Data) async -> Bool {
        guard let url = URL(string: "\(base)/\(table)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        addHeaders(to: &req)
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse { return http.statusCode < 300 }
            return false
        } catch {
            return false
        }
    }

    private func fetchSimple(table: String, queryItems: [URLQueryItem]) async -> [[String: Any]] {
        var components = URLComponents(string: "\(base)/\(table)")!
        components.queryItems = queryItems
        guard let url = components.url else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addHeaders(to: &req)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[Supabase] Fetch \(table) failed: HTTP \(http.statusCode) — \(body)")
                return []
            }
            let parsed = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            print("[Supabase] Fetch \(table) returned \(parsed.count) rows (url: \(url.absoluteString))")
            return parsed
        } catch {
            print("[Supabase] Fetch \(table) error: \(error)")
            return []
        }
    }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        // Use user access token if authenticated; fall back to anon key for unauthenticated reads
        let bearer = AuthService.shared.accessToken ?? SupabaseConfig.anonKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Code generation

    private func generateInviteCode() -> String {
        // Excludes ambiguous chars: 0/O, 1/I/L
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    // MARK: - Parsers

    private func remoteSession(from row: [String: Any]) -> RemoteSession? {
        guard
            let id = row["id"] as? String,
            let driverName = row["driver_name"] as? String,
            let startStr = row["start_time"] as? String,
            let endStr = row["end_time"] as? String,
            let startTime = iso.date(from: startStr),
            let endTime = iso.date(from: endStr)
        else { return nil }
        let vehicleID = (row["vehicle_id"] as? String) ?? ""
        let vehicleName = (row["vehicle_name"] as? String) ?? ""
        let distanceKm = (row["distance_km"] as? NSNumber)?.doubleValue ?? 0
        let idleSeconds = (row["idle_seconds"] as? NSNumber)?.doubleValue ?? 0
        let estimatedFuelLiters = (row["estimated_fuel_liters"] as? NSNumber)?.doubleValue ?? 0
        let aggressiveAccelEvents = (row["aggressive_accel_events"] as? NSNumber)?.intValue ?? 0
        let hardBrakeEvents = (row["hard_brake_events"] as? NSNumber)?.intValue ?? 0
        return RemoteSession(recordName: id, vehicleID: vehicleID, driverName: driverName,
                             vehicleName: vehicleName, startTime: startTime, endTime: endTime,
                             distanceKm: distanceKm, idleSeconds: idleSeconds,
                             estimatedFuelLiters: estimatedFuelLiters,
                             aggressiveAccelEvents: aggressiveAccelEvents,
                             hardBrakeEvents: hardBrakeEvents)
    }

    private func remoteFillUp(from row: [String: Any]) -> RemoteFillUp? {
        guard
            let id = row["id"] as? String,
            let dateStr = row["date"] as? String,
            let date = iso.date(from: dateStr)
        else { return nil }
        let liters = (row["liters"] as? NSNumber)?.doubleValue ?? 0
        let totalCost = (row["total_cost"] as? NSNumber)?.doubleValue ?? 0
        let odometer = (row["odometer"] as? NSNumber)?.doubleValue
        let isSettled = (row["is_settled"] as? Bool) ?? false
        return RemoteFillUp(id: id, liters: liters, totalCost: totalCost,
                            odometer: odometer, date: date, isSettled: isSettled)
    }

    private func remoteVehicle(from row: [String: Any]) -> RemoteVehicle? {
        guard
            let id = row["id"] as? String,
            let name = row["name"] as? String,
            let beaconUUID = row["beacon_uuid"] as? String
        else {
            print("[Supabase] remoteVehicle parse failed for row: \(row)")
            return nil
        }
        let efficiency = (row["fuel_efficiency_liters_per_100km"] as? NSNumber)?.doubleValue ?? 0
        return RemoteVehicle(id: id, name: name, beaconUUID: beaconUUID,
                             make: row["make"] as? String,
                             model: row["model"] as? String,
                             year: (row["year"] as? NSNumber)?.intValue,
                             fuelEfficiencyLitersPer100Km: efficiency)
    }

    // MARK: - Compatibility shims
    // AddManualTripView, AddFuelEntryView, EditVehicleView, CostSplitView, and NotificationService
    // are in the do-not-change list and still call the old groupID-based signatures.
    // These shims forward to the new schema methods so those files continue to compile.

    /// Maps old groupID-based push to new vehicle-scoped push.
    /// The vehicleID is used as-is (old code stored vehicle UUIDs as groupIDs in many cases).
    func pushSession(_ session: DrivingSession, groupID: String) async {
        await pushTrip(session, vehicleID: groupID)
    }

    func pushFillUp(_ entry: FuelEntry, groupID: String) async {
        await pushFuelEntry(entry, vehicleID: groupID)
    }

    func pushVehicle(_ vehicle: Vehicle, groupID: String) async {
        await pushVehicle(vehicle)
    }

    func fetchSessions(groupID: String, since: Date, until: Date) async -> [RemoteSession] {
        return await fetchTrips(vehicleIDs: [groupID], since: since, until: until)
    }

    func fetchFillUps(groupID: String) async -> [RemoteFillUp] {
        return await fetchFuelEntries(vehicleIDs: [groupID])
    }

    func updateSettled(entryID: String, groupID: String, isSettled: Bool) async {
        await updateSettled(entryID: entryID, vehicleID: groupID, isSettled: isSettled)
    }
}
