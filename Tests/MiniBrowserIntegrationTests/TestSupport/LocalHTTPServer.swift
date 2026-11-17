import Foundation
import Network

/// 仅供集成测试使用的单次请求 HTTP/1.1 服务，监听随机 localhost 端口。
final class LocalHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response: Sendable {
        var status: String
        var headers: [String: String]
        var body: Data

        init(_ body: String = "", status: String = "200 OK",
             contentType: String = "text/html; charset=utf-8",
             headers: [String: String] = [:]) {
            self.status = status
            self.body = Data(body.utf8)
            self.headers = headers.merging(["Content-Type": contentType]) { custom, _ in custom }
        }

        init(data: Data, status: String = "200 OK",
             contentType: String = "application/octet-stream",
             headers: [String: String] = [:]) {
            self.status = status
            self.body = data
            self.headers = headers.merging(["Content-Type": contentType]) { custom, _ in custom }
        }
    }

    struct ServerError: Error, CustomStringConvertible {
        let description: String
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "MiniBrowserIntegrationTests.LocalHTTPServer")
    private let handler: @Sendable (Request) -> Response
    private let lock = NSLock()
    private var recordedRequests: [Request] = []

    private(set) var port: UInt16 = 0

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        self.handler = handler
        listener = try NWListener(using: .tcp, on: .any)
    }

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumption = LockedResumption(continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.port = self.listener.port?.rawValue ?? 0
                    resumption.resume(with: .success(()))
                case .failed(let error):
                    resumption.resume(with: .failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    var requests: [Request] {
        lock.withLock { recordedRequests }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receive(into: Data(), on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receive(into buffer: Data, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil {
                connection.cancel()
                return
            }
            if let request = Self.parseRequest(buffer) {
                self.lock.withLock { self.recordedRequests.append(request) }
                self.respond(to: request, on: connection)
            } else if complete {
                connection.cancel()
            } else {
                self.receive(into: buffer, on: connection)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        var response = handler(request)
        var head = "HTTP/1.1 \(response.status)\r\n"
        response.headers["Content-Length"] = "\(response.body.count)"
        response.headers["Connection"] = "close"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(_ data: Data) -> Request? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerRange.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        return Request(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + length))
        )
    }
}

private final class LockedResumption: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Void, Error>) {
        let continuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            return value
        }
        switch result {
        case .success: continuation?.resume()
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }
}
