import Darwin
import Foundation

/// 测试专用自签 HTTPS 服务；证书、密钥和进程均随测试结束清理。
@MainActor
final class LocalHTTPSServer {
    let port: UInt16
    let baseURL: URL
    private let directory: URL
    private let process: Process

    init(title: String = "trusted-local") async throws {
        directory = try makeTemporaryDirectory("https")
        let certificate = directory.appendingPathComponent("certificate.pem")
        let key = directory.appendingPathComponent("key.pem")
        try """
        <!doctype html><html><head><title>\(title)</title></head><body>local TLS ok</body></html>
        """.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Self.run(Self.openssl, arguments: [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
            "-subj", "/CN=localhost", "-keyout", key.path, "-out", certificate.path
        ])

        port = try Self.unusedPort()
        baseURL = URL(string: "https://localhost:\(port)/index.html")!

        process = Process()
        process.executableURL = Self.openssl
        process.currentDirectoryURL = directory
        process.arguments = [
            "s_server", "-accept", "\(port)", "-cert", certificate.path,
            "-key", key.path, "-WWW", "-quiet"
        ]
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        do {
            try await Self.waitForTCP(port: port)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
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
