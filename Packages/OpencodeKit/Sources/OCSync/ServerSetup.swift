import Foundation
import OCModels
import OCNetworking
import OCSecurity

public enum ServerSetupError: Error, LocalizedError {
    case invalidURL, lastEndpoint, invalidToken, notLoaded, duplicateServer
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid HTTP or HTTPS server URL without credentials or query parameters."
        case .lastEndpoint: "Keep at least one endpoint for this server."
        case .invalidToken: "The server returned an invalid pairing token. Create a new pairing link."
        case .notLoaded: "Saved servers could not be loaded. Retry before adding a server."
        case .duplicateServer: "This server record is already saved."
        }
    }
}

extension ServerRegistry {
    @discardableResult public func addManually(name: String, address: String, password: String) async throws -> ServerStore {
        let endpoint = try Self.endpoint(address)
        return try await add(ServerRecord(name: name.isEmpty ? endpoint.url.host ?? "opencode" : name,
                                          endpoints: [endpoint]), credential: .password(password))
    }
    @discardableResult public func pair(_ input: String, replacing server: ServerStore? = nil) async throws -> ServerStore {
        let link = try PairingParser.parse(input)
        let result: RedeemedPairing
        do { result = try await PairingService().redeem(link) }
        catch PairingError.unreachable {
            let endpoints = link.urls.map { EndpointRecord(url: $0, kind: EndpointPolicy.classify($0)) }
            let resolution = await EndpointResolver().resolve(endpoints: endpoints, credential: nil)
            throw PairingDiagnosisError(endpoints: endpoints, resolution: resolution)
        }
        guard let credential = PairingToken.credential(result.token) else { throw ServerSetupError.invalidToken }
        try Task.checkCancellation()
        if let server {
            try await server.repair(credential: credential, endpoints: result.server.endpoints)
            return server
        }
        return try await add(result.server, credential: credential)
    }
    public static func endpoint(_ address: String) throws -> EndpointRecord {
        guard let url = PairingParser.serverAddress(address) else { throw ServerSetupError.invalidURL }
        try EndpointPolicy.validate(url)
        return .init(url: url, kind: EndpointPolicy.classify(url))
    }
    public static func errorMessage(_ error: any Error) -> String {
        if case APIError.refused(let reason) = error { return reason.message }
        if let error = error as? any LocalizedError, let description = error.errorDescription { return description }
        return "Could not save or connect to the server. Try again."
    }
}

private struct PairingDiagnosisError: LocalizedError {
    let endpoints: [EndpointRecord]
    let resolution: EndpointResolution
    var errorDescription: String? {
        "None of the server addresses could be reached.\n" + endpoints.map { endpoint in
            let message: String
            switch resolution.diagnoses[endpoint.id] {
            case .failure(let failure): message = failure.message
            case .incompatible(.v1): message = "This is an opencode 1 server. Update opencode."
            case .incompatible: message = "This server version is too old. Update opencode."
            default: message = "Pairing is unavailable. Create a new link on the server."
            }
            return "\(endpoint.url.host ?? "Endpoint"): \(message)"
        }.joined(separator: "\n")
    }
}
