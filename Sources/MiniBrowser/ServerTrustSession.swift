import Foundation
import Security
import WebKit

@MainActor
final class ServerTrustSession {
    struct Site: Hashable {
        let scheme: String
        let host: String
        let port: Int

        init(protectionSpace: URLProtectionSpace) {
            scheme = protectionSpace.`protocol`?.lowercased() ?? "https"
            host = protectionSpace.host.lowercased()
            port = protectionSpace.port
        }
    }

    static let shared = ServerTrustSession()
    private var allowedCertificates: [Site: Data] = [:]
    private let trustEvaluator: (SecTrust) -> Bool

    init(trustEvaluator: @escaping (SecTrust) -> Bool = { SecTrustEvaluateWithError($0, nil) }) {
        self.trustEvaluator = trustEvaluator
    }

    func isValid(_ trust: SecTrust) -> Bool {
        trustEvaluator(trust)
    }

    func allows(site: Site, trust: SecTrust) -> Bool {
        guard let certificate = Self.leafCertificateData(trust) else { return false }
        return allowedCertificates[site] == certificate
    }

    func allow(site: Site, trust: SecTrust) {
        guard let certificate = Self.leafCertificateData(trust) else { return }
        allowedCertificates[site] = certificate
    }

    private static func leafCertificateData(_ trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else { return nil }
        return SecCertificateCopyData(certificate) as Data
    }
}
