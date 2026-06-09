import Foundation

// Supabase REST client — named CloudKitService so no other files need renaming.

struct RemoteSession {
    let recordName: String
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

    private let base = "https://pbhxyxmwdpbksgnrgzwr.supabase.co/rest/v1"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiaHh5eG13ZHBia3NnbnJnendyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MzgwNjcsImV4cCI6MjA5MjExNDA2N30.80LkKL8mKudMbYjYJ08yDMzTY0M7xaAPtFTj4Ivd_XA"
    private let iso = ISO8601DateFormatter()
    private init() {}

    // MARK: - Sessions

    func pushSession(_ session: DrivingSession, groupID: String) async {
        guard let endTime = session.endTime,
              let driverName = session.driver?.name,
              let vehicleName = session.vehicle?.name else { return }
        let body: [String: Any] = [
            "id": session.id.uuidString,
            "group_id": groupID,
            "driver_name": driverName,
            "vehicle_name": vehicleName,
            "start_time": iso.string(from: session.startTime),
            "end_time": iso.string(from: endTime),
            "distance_km": session.distanceKm,
            "idle_seconds": session.idleSeconds,
            "estimated_fuel_liters": session.estimatedFuelLiters,
            "aggressive_accel_events": session.aggressiveAccelEvents,
            "hard_brake_events": session.hardBrakeEvents
        ]
        await upsert(table: "group_sessions", body: body)
    }

    func fetchSessions(groupID: String, since: Date, until: Date) async -> [RemoteSession] {
        let rows = await fetchSimple(table: "group_sessions", queryItems: [
            URLQueryItem(name: "group_id", value: "eq.\(groupID)"),
            URLQueryItem(name: "end_time", value: "gte.\(iso.string(from: since))"),
            URLQueryItem(name: "end_time", value: "lte.\(iso.string(from: until))")
        ])
        return rows.compactMap { remoteSession(from: $0) }
    }

    // MARK: - Fill-ups

    func pushFillUp(_ entry: FuelEntry, groupID: String) async {
        var body: [String: Any] = [
            "id": entry.id.uuidString,
            "group_id": groupID,
            "liters": entry.liters,
            "total_cost": entry.totalCost,
            "date": iso.string(from: entry.date),
            "is_settled": entry.isSettled
        ]
        if let odo = entry.odometer { body["odometer"] = odo }
        await upsert(table: "group_fill_ups", body: body)
    }

    func fetchFillUps(groupID: String) async -> [RemoteFillUp] {
        let rows = await fetchSimple(table: "group_fill_ups",
                                     queryItems: [URLQueryItem(name: "group_id", value: "eq.\(groupID)")])
        return rows.compactMap { remoteFillUp(from: $0) }
    }

    func updateSettled(entryID: String, groupID: String, isSettled: Bool) async {
        var components = URLComponents(string: "\(base)/group_fill_ups")!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(entryID)"),
            URLQueryItem(name: "group_id", value: "eq.\(groupID)")
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

    // MARK: - Vehicles

    func pushVehicle(_ vehicle: Vehicle, groupID: String) async {
        var body: [String: Any] = [
            "id": vehicle.id.uuidString,
            "group_id": groupID,
            "name": vehicle.name,
            "beacon_uuid": vehicle.beaconUUID,
            "fuel_efficiency_liters_per_100km": vehicle.fuelEfficiencyLitersPer100Km
        ]
        if let make = vehicle.make { body["make"] = make }
        if let model = vehicle.vehicleModel { body["model"] = model }
        if let year = vehicle.year { body["year"] = year }
        await upsert(table: "group_vehicles", body: body)
    }

    func fetchVehicles(groupID: String) async -> [RemoteVehicle] {
        let rows = await fetchSimple(table: "group_vehicles",
                                     queryItems: [URLQueryItem(name: "group_id", value: "eq.\(groupID)")])
        return rows.compactMap { remoteVehicle(from: $0) }
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
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Parsers

    private func remoteSession(from row: [String: Any]) -> RemoteSession? {
        guard
            let id = row["id"] as? String,
            let driverName = row["driver_name"] as? String,
            let vehicleName = row["vehicle_name"] as? String,
            let startStr = row["start_time"] as? String,
            let endStr = row["end_time"] as? String,
            let startTime = iso.date(from: startStr),
            let endTime = iso.date(from: endStr)
        else { return nil }
        let distanceKm = (row["distance_km"] as? NSNumber)?.doubleValue ?? 0
        let idleSeconds = (row["idle_seconds"] as? NSNumber)?.doubleValue ?? 0
        let estimatedFuelLiters = (row["estimated_fuel_liters"] as? NSNumber)?.doubleValue ?? 0
        let aggressiveAccelEvents = (row["aggressive_accel_events"] as? NSNumber)?.intValue ?? 0
        let hardBrakeEvents = (row["hard_brake_events"] as? NSNumber)?.intValue ?? 0
        return RemoteSession(recordName: id, driverName: driverName, vehicleName: vehicleName,
                             startTime: startTime, endTime: endTime, distanceKm: distanceKm,
                             idleSeconds: idleSeconds, estimatedFuelLiters: estimatedFuelLiters,
                             aggressiveAccelEvents: aggressiveAccelEvents, hardBrakeEvents: hardBrakeEvents)
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
}
