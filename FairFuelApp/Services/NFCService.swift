import Foundation
import CoreNFC

// Callback-based wrapper around NFCNDEFReaderSession.
// Week 3 will fill in the full implementation.
protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReadDriverID driverID: String)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

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

    // MARK: - Payload Parsing

    // Expected NDEF payload: a URI record with scheme "fairfuel://driver/<UUID>"
    static func extractDriverID(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            guard record.typeNameFormat == .nfcWellKnown,
                  let type = String(data: record.type, encoding: .utf8),
                  type == "U",
                  let payload = String(data: record.payload, encoding: .utf8) else { continue }

            // Payload for URI records: first byte is URI identifier code, rest is the URI
            let uriPrefix = "fairfuel://driver/"
            if payload.contains(uriPrefix),
               let range = payload.range(of: uriPrefix) {
                let driverID = String(payload[range.upperBound...])
                return driverID.isEmpty ? nil : driverID
            }
        }
        return nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        // Code 200 = user cancelled — not a real error
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            delegate?.nfcService(self, didFailWithError: error)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first,
              let driverID = NFCService.extractDriverID(from: message) else {
            delegate?.nfcService(self, didFailWithError: NFCError.invalidPayload)
            return
        }
        delegate?.nfcService(self, didReadDriverID: driverID)
    }
}

// MARK: - NFCError

enum NFCError: LocalizedError {
    case notAvailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "NFC is not available on this device."
        case .invalidPayload: return "The NFC tag does not contain a valid FairFuel driver ID."
        }
    }
}
