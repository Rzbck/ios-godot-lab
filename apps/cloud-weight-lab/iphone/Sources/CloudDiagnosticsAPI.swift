import Foundation
import Network
import Security

final class CloudDiagnosticsAPI {
    enum State: Equatable {
        case stopped
        case ready
        case pairing
        case paired(String)
        case failed(String)
    }

    static let port: UInt16 = 8765

    var stateDidChange: ((State) -> Void)?

    private let store: CloudDiagnosticsStore
    private let sessionRecorder: CloudSessionRecorder
    private let queue = DispatchQueue(label: "cloudweight.diagnostics.api", qos: .utility)
    private var listener: NWListener?
    private var state: State = .stopped
    private var pairingDeadline: Date?
    private var pairedHost: String?
    private var bearerToken: String?

    init(store: CloudDiagnosticsStore, sessionRecorder: CloudSessionRecorder) {
        self.store = store
        self.sessionRecorder = sessionRecorder
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }

            do {
                guard let port = NWEndpoint.Port(rawValue: Self.port) else {
                    self.publish(.failed("Port API invalide"))
                    return
                }

                let listener = try NWListener(using: .tcp, on: port)
                listener.service = NWListener.Service(
                    name: "CloudWeight-\(BuildInfo.gitSHA)",
                    type: "_cloudweight._tcp"
                )
                listener.stateUpdateHandler = { [weak self] next in
                    guard let self else { return }
                    switch next {
                    case .ready:
                        self.publish(self.pairedHost == nil ? .ready : .paired(self.pairedHost!))
                    case .failed(let error):
                        self.publish(.failed(error.localizedDescription))
                    case .cancelled:
                        self.publish(.stopped)
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.publish(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.pairingDeadline = nil
            self.pairedHost = nil
            self.bearerToken = nil
            self.publish(.stopped)
        }
    }

    func armPairing(seconds: TimeInterval = 45) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pairingDeadline = Date().addingTimeInterval(seconds)
            self.pairedHost = nil
            self.bearerToken = nil
            self.publish(.pairing)
        }
    }

    func unpair() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pairingDeadline = nil
            self.pairedHost = nil
            self.bearerToken = nil
            self.publish(.ready)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection: connection, accumulated: Data())
    }

    private func receiveRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var next = accumulated
            if let content {
                next.append(content)
            }

            if next.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.route(connection: connection, requestData: next)
                return
            }

            if next.count >= 64 * 1024 || error != nil {
                self.send(
                    connection,
                    status: 400,
                    contentType: "application/json",
                    body: self.json(["error": "bad_request"])
                )
                return
            }

            self.receiveRequest(connection: connection, accumulated: next)
        }
    }

    private func route(connection: NWConnection, requestData: Data) {
        guard let text = String(data: requestData, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else {
            send(connection, status: 400, contentType: "application/json", body: json(["error": "bad_request"]))
            return
        }

        let headerText = String(text[..<headerEnd.lowerBound])
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else {
            send(connection, status: 400, contentType: "application/json", body: json(["error": "bad_request"]))
            return
        }

        let requestParts = first.split(separator: " ")
        guard requestParts.count >= 2 else {
            send(connection, status: 400, contentType: "application/json", body: json(["error": "bad_request"]))
            return
        }

        let method = String(requestParts[0]).uppercased()
        let rawTarget = String(requestParts[1])
        let components = URLComponents(string: "http://localhost\(rawTarget)")
        let path = components?.path ?? rawTarget
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let host = remoteHost(connection)

        if method == "GET", path == "/api/v1/health" {
            let armed = pairingDeadline.map { $0 > Date() } ?? false
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: json([
                    "app": "Cloud Weight Lab",
                    "api_version": "2",
                    "version": BuildInfo.version,
                    "build": BuildInfo.gitSHA,
                    "port": Int(Self.port),
                    "pairing_armed": armed,
                    "paired": pairedHost != nil,
                    "active_session": sessionRecorder.activeSessionID() ?? "",
                    "privacy": "local_persistent_bounded_sessions"
                ])
            )
            return
        }

        if method == "POST", path == "/api/v1/pair" {
            guard let deadline = pairingDeadline, deadline > Date() else {
                publish(pairedHost == nil ? .ready : .paired(pairedHost!))
                send(connection, status: 403, contentType: "application/json", body: json(["error": "pairing_not_armed"]))
                return
            }

            let token = randomToken()
            pairingDeadline = nil
            pairedHost = host
            bearerToken = token
            store.setCaptureEnabled(true)
            publish(.paired(host))
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: json([
                    "token": token,
                    "host": host,
                    "build": BuildInfo.gitSHA,
                    "active_session": sessionRecorder.activeSessionID() ?? "",
                    "expires": "app_session"
                ])
            )
            return
        }

        guard authorized(headers: headers, host: host) else {
            send(connection, status: 401, contentType: "application/json", body: json(["error": "unauthorized"]))
            return
        }

        if method == "GET", path == "/api/v1/status" {
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: store.statusData(buildSHA: BuildInfo.gitSHA, version: BuildInfo.version)
            )
            return
        }

        if method == "GET", path == "/api/v1/telemetry" {
            let requestedLimit = components?.queryItems?
                .first(where: { $0.name == "limit" })?
                .value
                .flatMap(Int.init) ?? 120
            let after = components?.queryItems?
                .first(where: { $0.name == "after" })?
                .value
                .flatMap(TimeInterval.init)
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: store.telemetryData(limit: requestedLimit, after: after)
            )
            return
        }

        if method == "GET", path == "/api/v1/snapshots" {
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: store.snapshotListData()
            )
            return
        }

        if method == "GET", path == "/api/v1/snapshots/latest.jpg" {
            guard let image = store.latestSnapshotData() else {
                send(connection, status: 404, contentType: "application/json", body: json(["error": "no_snapshot"])); return
            }
            send(connection, status: 200, contentType: "image/jpeg", body: image)
            return
        }

        if method == "GET", path.hasPrefix("/api/v1/snapshots/"), path.hasSuffix(".jpg") {
            let value = path
                .replacingOccurrences(of: "/api/v1/snapshots/", with: "")
                .replacingOccurrences(of: ".jpg", with: "")
            guard let image = store.snapshotData(id: value) else {
                send(connection, status: 404, contentType: "application/json", body: json(["error": "snapshot_not_found"])); return
            }
            send(connection, status: 200, contentType: "image/jpeg", body: image)
            return
        }

        if method == "DELETE", path == "/api/v1/snapshots" {
            store.removeAllSnapshots()
            send(connection, status: 200, contentType: "application/json", body: json(["ok": true]))
            return
        }

        if method == "GET", path == "/api/v1/sessions" {
            send(
                connection,
                status: 200,
                contentType: "application/json",
                body: sessionRecorder.sessionsData()
            )
            return
        }

        let pathParts = path.split(separator: "/").map(String.init)
        if pathParts.count >= 4,
           pathParts[0] == "api",
           pathParts[1] == "v1",
           pathParts[2] == "sessions" {
            let sessionID = pathParts[3]

            if method == "GET", pathParts.count == 5, pathParts[4] == "manifest" {
                guard let body = sessionRecorder.sessionManifestData(id: sessionID) else {
                    send(connection, status: 404, contentType: "application/json", body: json(["error": "session_not_found"])); return
                }
                send(connection, status: 200, contentType: "application/json", body: body)
                return
            }

            if method == "GET", pathParts.count == 5, pathParts[4] == "files" {
                guard let body = sessionRecorder.sessionFilesData(id: sessionID) else {
                    send(connection, status: 404, contentType: "application/json", body: json(["error": "session_not_found"])); return
                }
                send(connection, status: 200, contentType: "application/json", body: body)
                return
            }

            if method == "GET", pathParts.count == 5, pathParts[4] == "file" {
                guard let relativePath = components?.queryItems?
                        .first(where: { $0.name == "path" })?.value,
                      let body = sessionRecorder.sessionFileData(
                        id: sessionID,
                        relativePath: relativePath
                      ) else {
                    send(connection, status: 404, contentType: "application/json", body: json(["error": "session_file_not_found"])); return
                }
                send(
                    connection,
                    status: 200,
                    contentType: contentType(for: relativePath),
                    body: body
                )
                return
            }
        }

        if method == "POST", path == "/api/v1/unpair" {
            pairedHost = nil
            bearerToken = nil
            pairingDeadline = nil
            publish(.ready)
            send(connection, status: 200, contentType: "application/json", body: json(["ok": true]))
            return
        }

        send(connection, status: 404, contentType: "application/json", body: json(["error": "not_found"]))
    }

    private func authorized(headers: [String: String], host: String) -> Bool {
        guard let pairedHost,
              pairedHost == host,
              let bearerToken,
              let value = headers["authorization"],
              value == "Bearer \(bearerToken)" else {
            return false
        }
        return true
    }

    private func remoteHost(_ connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            return "\(host)"
        default:
            return "unknown"
        }
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func publish(_ next: State) {
        state = next
        DispatchQueue.main.async { [weak self] in
            self?.stateDidChange?(next)
        }
    }

    private func contentType(for path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".ndjson") { return "application/x-ndjson" }
        if lower.hasSuffix(".json") { return "application/json" }
        return "application/octet-stream"
    }

    private func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    private func send(
        _ connection: NWConnection,
        status: Int,
        contentType: String,
        body: Data
    ) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }

        let header = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
