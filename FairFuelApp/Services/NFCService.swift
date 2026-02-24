import Foundation
import CoreNFC

protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReadVehicleID vehicleID: String)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

// Reads the vehicle's NFC tag and extracts the vehicle ID.
// Driver identity is NOT in the tag — it comes from the local DriverProfile on this device.
final class NFCService: NSObject {
    weak var delegate: NFCServiceDelegate?

    private var readerSession: NFCNDEFReaderSession?

    // MARK: - Public

    func startScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            delegate?.nfcService(self, didFailWithError: NFCError.notAvailable)
            return
        }
        readerSession = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
        readerSession?.alertMessage = "Hold your iPhone near the FairFuel tag inside the vehicle."
        readerSession?.begin()
    }

    func stopScanning() {
        readerSession?.invalidate()
        readerSession = nil
    }

    // MARK: - Tag Writing (Vehicle Setup)

    // Writes a vehicle ID URI to an NFC tag.
    // Called once during vehicle setup — any driver can then scan that tag to start a session.
    func writeVehicleTag(vehicleID: String, to session: NFCNDEFReaderSession) throws {
        let uri = "fairfuel://vehicle/\(vehicleID)"
        guard let uriData = uri.data(using: .utf8) else { throw NFCError.invalidPayload }
        let payload = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: "U".data(using: .utf8)!,
            identifier: Data(),
            payload: uriData
        )
        let message = NFCNDEFMessage(records: [payload])
        session.connect(to: session.connectedTag!) { _ in
            (session.connectedTag as? NFCNDEFTag)?.writeNDEF(message) { error in
                if let error { session.invalidate(errorMessage: error.localizedDescription) }
                else { session.invalidate() }
            }
        }
    }

    // MARK: - Payload Parsing

    // Expected payload: URI record with scheme "fairfuel://vehicle/<ID>"
    static func extractVehicleID(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            guard let uri = record.wellKnownTypeURIPayload() else { continue }
            let uriString = uri.absoluteString
            let prefix = "fairfuel://vehicle/"
            if uriString.hasPrefix(prefix) {
                let vehicleID = String(uriString.dropFirst(prefix.count))
                return vehicleID.isEmpty ? nil : vehicleID
            }
        }
        return nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            delegate?.nfcService(self, didFailWithError: error)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first,
              let vehicleID = NFCService.extractVehicleID(from: message) else {
            delegate?.nfcService(self, didFailWithError: NFCError.invalidPayload)
            return
        }
        delegate?.nfcService(self, didReadVehicleID: vehicleID)
    }
}

// MARK: - NFCError

enum NFCError: LocalizedError {
    case notAvailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "NFC is not available on this device."
        case .invalidPayload: return "The NFC tag does not contain a valid FairFuel vehicle ID."
        }
    }
}
