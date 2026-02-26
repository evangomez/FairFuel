import Foundation
import CoreNFC

protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReadVehicleTagURI uri: String)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

// Handles both reading (session start) and writing (vehicle setup).
// Reading:  invalidateAfterFirstRead = true  → didDetectNDEFs called automatically
// Writing:  invalidateAfterFirstRead = false → didDetectTags called so we can write
final class NFCService: NSObject {

    private enum Mode {
        case reading
        case writing(vehicleID: String)
    }

    weak var delegate: NFCServiceDelegate?

    private var activeSession: NFCNDEFReaderSession?
    private var currentMode: Mode = .reading
    private var writeCompletion: ((Result<Void, Error>) -> Void)?

    // MARK: - Public

    /// Tap phone to vehicle tag → delegate receives the vehicle URI → session starts.
    func startReading() {
        guard NFCNDEFReaderSession.readingAvailable else {
            delegate?.nfcService(self, didFailWithError: NFCError.notAvailable)
            return
        }
        currentMode = .reading
        let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold your iPhone near the vehicle tag to start your session."
        activeSession = session
        session.begin()
    }

    /// Tap phone to a blank sticker during vehicle setup to program it.
    func writeVehicleTag(vehicleID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(NFCError.notAvailable))
            return
        }
        currentMode = .writing(vehicleID: vehicleID)
        writeCompletion = completion
        let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold your iPhone near the new NFC sticker to program it."
        activeSession = session
        session.begin()
    }

    // MARK: - Parsing

    static func extractVehicleTagURI(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            if let url = record.wellKnownTypeURIPayload() {
                let uri = url.absoluteString
                if uri.hasPrefix("fairfuel://vehicle/") { return uri }
            }
        }
        return nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCService: NFCNDEFReaderSessionDelegate {

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        activeSession = nil
        let code = (error as? NFCReaderError)?.code
        guard code != .readerSessionInvalidationErrorUserCanceled,
              code != .readerSessionInvalidationErrorFirstNDEFTagRead else { return }
        switch currentMode {
        case .reading:
            delegate?.nfcService(self, didFailWithError: error)
        case .writing:
            writeCompletion?(.failure(error))
            writeCompletion = nil
        }
    }

    // Called in read mode
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first,
              let uri = NFCService.extractVehicleTagURI(from: message) else {
            delegate?.nfcService(self, didFailWithError: NFCError.invalidPayload)
            return
        }
        delegate?.nfcService(self, didReadVehicleTagURI: uri)
    }

    // Called in write mode
    func readerSession(_ session: NFCNDEFReaderSession, didDetectTags tags: [any NFCNDEFTag]) {
        guard case .writing(let vehicleID) = currentMode,
              let tag = tags.first else { return }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: "Could not connect to tag.")
                self.writeCompletion?(.failure(error))
                self.writeCompletion = nil
                return
            }
            guard let url = URL(string: "fairfuel://vehicle/\(vehicleID)"),
                  let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                session.invalidate(errorMessage: "Failed to build tag payload.")
                self.writeCompletion?(.failure(NFCError.invalidPayload))
                self.writeCompletion = nil
                return
            }
            let message = NFCNDEFMessage(records: [payload])
            tag.writeNDEF(message) { error in
                if let error {
                    session.invalidate(errorMessage: error.localizedDescription)
                    self.writeCompletion?(.failure(error))
                } else {
                    session.alertMessage = "Vehicle tag programmed successfully."
                    session.invalidate()
                    self.writeCompletion?(.success(()))
                }
                self.writeCompletion = nil
            }
        }
    }
}

// MARK: - NFCError

enum NFCError: LocalizedError {
    case notAvailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "NFC is not available on this device."
        case .invalidPayload: return "The tag does not contain a valid FairFuel vehicle ID."
        }
    }
}
