import AppKit
import Foundation
import Vision

enum QRScannerError: LocalizedError {
    case noImageInClipboard
    case invalidImage
    case noQRCodeFound
    case invalidQRPayload

    var errorDescription: String? {
        switch self {
        case .noImageInClipboard:
            return "Aucune image ou JSON de QR Code trouvé dans le presse-papiers."
        case .invalidImage:
            return "Impossible de lire l'image fournie."
        case .noQRCodeFound:
            return "Aucun QR Code détecté dans cette image."
        case .invalidQRPayload:
            return "Le QR Code détecté n'est pas un QR Code Pronote valide."
        }
    }
}

enum QRCodeScanner {
    static func decodeFromClipboard() throws -> QRCodePayload {
        let pasteboard = NSPasteboard.general

        // 1. Si le presse-papiers contient directement du texte JSON
        if let text = pasteboard.string(forType: .string),
           let payload = try? decodeJSONString(text) {
            return payload
        }

        // 2. Sinon, chercher une image (capture d'écran Cmd+Ctrl+Shift+4, copier l'image, etc.)
        if let image = NSImage(pasteboard: pasteboard) {
            return try decode(image: image)
        }

        // 3. Ou un fichier image copié dans le Finder
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first,
           let image = NSImage(contentsOf: firstURL) {
            return try decode(image: image)
        }

        throw QRScannerError.noImageInClipboard
    }

    static func decode(url: URL) throws -> QRCodePayload {
        guard let image = NSImage(contentsOf: url) else {
            throw QRScannerError.invalidImage
        }
        return try decode(image: image)
    }

    static func decode(image: NSImage) throws -> QRCodePayload {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw QRScannerError.invalidImage
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let results = request.results, !results.isEmpty else {
            throw QRScannerError.noQRCodeFound
        }

        for observation in results {
            if let raw = observation.payloadStringValue,
               let payload = try? decodeJSONString(raw) {
                return payload
            }
        }

        throw QRScannerError.invalidQRPayload
    }

    static func decodeJSONString(_ string: String) throws -> QRCodePayload {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw QRScannerError.invalidQRPayload
        }
        return try JSONDecoder().decode(QRCodePayload.self, from: data)
    }
}
