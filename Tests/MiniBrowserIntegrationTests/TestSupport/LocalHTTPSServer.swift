import Darwin
import Foundation
import Security

/// 测试专用自签 HTTPS 服务；证书、密钥和进程均随测试结束清理。
@MainActor
final class LocalHTTPSServer {
    let port: UInt16
    let baseURL: URL
    private let directory: URL
    private let process: Process

    init(title: String = "trusted-local", trustedCA: Bool = false,
         lifetime: TimeInterval = 120) async throws {
        directory = try makeTemporaryDirectory("https")
        let certificate = directory.appendingPathComponent("certificate.pem")
        let key = directory.appendingPathComponent("key.pem")
        try """
        <!doctype html><html><head><title>\(title)</title></head><body>local TLS ok</body></html>
        """.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        if trustedCA {
            let caCertificate = directory.appendingPathComponent("ca-certificate.pem")
            let caKey = directory.appendingPathComponent("ca-key.pem")
            let request = directory.appendingPathComponent("leaf-request.pem")
            let extensions = directory.appendingPathComponent("leaf-extensions.cnf")
            let caConfiguration = directory.appendingPathComponent("ca-configuration.cnf")
            try """
            [req]
            distinguished_name=dn
            [dn]
            [ca_ext]
            basicConstraints=critical,CA:TRUE
            keyUsage=critical,keyCertSign,cRLSign
            subjectKeyIdentifier=hash
            """.write(to: caConfiguration, atomically: true, encoding: .utf8)
            try """
            basicConstraints=critical,CA:FALSE
            keyUsage=critical,digitalSignature,keyEncipherment
            extendedKeyUsage=serverAuth
            subjectAltName=DNS:localhost,IP:127.0.0.1
            """.write(to: extensions, atomically: true, encoding: .utf8)
            try Self.run(Self.openssl, arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
                "-config", caConfiguration.path, "-extensions", "ca_ext",
                "-subj", "/CN=MiniBrowserTestCA", "-keyout", caKey.path, "-out", caCertificate.path
            ])
            try Self.run(Self.openssl, arguments: [
                "x509", "-in", caCertificate.path, "-outform", "der",
                "-out", directory.appendingPathComponent("ca-certificate.der").path
            ])
            try Self.run(Self.openssl, arguments: [
                "req", "-new", "-newkey", "rsa:2048", "-sha256", "-nodes",
                "-subj", "/CN=localhost", "-keyout", key.path, "-out", request.path
            ])
            try Self.run(Self.openssl, arguments: [
                "x509", "-req", "-in", request.path, "-CA", caCertificate.path,
                "-CAkey", caKey.path, "-CAcreateserial", "-days", "1", "-sha256",
                "-extfile", extensions.path, "-out", certificate.path
            ])
        } else {
            try Self.run(Self.openssl, arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
                "-subj", "/CN=localhost", "-keyout", key.path, "-out", certificate.path
            ])
        }

        port = try Self.unusedPort()
        baseURL = URL(string: "https://localhost:\(port)/index.html")!

        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.currentDirectoryURL = directory
        let supervisor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/test-tls-server.py")
        process.arguments = [
            supervisor.path, "\(getpid())", "\(lifetime)", "/usr/bin/python3",
            supervisor.path, "serve", "\(port)", certificate.path, key.path
        ]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            try await Self.waitForTCP(port: port)
        } catch {
            stop()
            throw error
        }
    }

    func caCertificate() -> SecCertificate? {
        let url = directory.appendingPathComponent("ca-certificate.der")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    func stop() {
        if process.isRunning { process.terminate() }
        if process.processIdentifier > 0 { process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        if process.isRunning { process.terminate() }
        if process.processIdentifier > 0 { process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func unusedPort() throws -> UInt16 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw WebViewTestError(description: "Could not allocate TLS port") }
        defer { Darwin.close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw WebViewTestError(description: "Could not bind TLS port probe") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socket, $0, &length)
            }
        }
        guard named == 0 else { throw WebViewTestError(description: "Could not read TLS port probe") }
        return UInt16(bigEndian: address.sin_port)
    }

    private static var openssl: URL {
        URL(fileURLWithPath: "/usr/bin/openssl")
    }

    private static func run(_ executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WebViewTestError(description: "openssl failed with status \(process.terminationStatus)")
        }
    }

    private static func waitForTCP(port: UInt16) async throws {
        for _ in 0..<100 {
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            Darwin.close(socket)
            if connected == 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw WebViewTestError(description: "TLS server startup timed out")
    }
}
