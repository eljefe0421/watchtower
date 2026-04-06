import Foundation
import Network

/// Lightweight HTTP server that receives Claude Code hook events.
/// Listens on a local port and processes JSON POST requests.
/// Supports holding connections for permission approve/deny flow.
final class EventServer {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "watchtower.server", attributes: .concurrent)

    var onEvent: ((HookEvent) -> Void)?

    /// Held connections waiting for user approval (keyed by session_id)
    private let lock = NSLock()
    private var pendingResponses: [String: (Data?) -> Void] = [:]

    init(port: UInt16 = 47777) {
        self.port = port
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            Log.info("[Watchtower] Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Log.info("[Watchtower] Server listening on port \(self.port)")
            case .failed(let error):
                Log.info("[Watchtower] Server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Permission Response

    /// Called when user approves a permission from the notch UI
    func approvePermission(sessionId: String) {
        respondToPermission(sessionId: sessionId, allow: true)
    }

    /// Called when user denies a permission from the notch UI
    func denyPermission(sessionId: String) {
        respondToPermission(sessionId: sessionId, allow: false)
    }

    private func respondToPermission(sessionId: String, allow: Bool) {
        lock.lock()
        let respond = pendingResponses.removeValue(forKey: sessionId)
        lock.unlock()

        guard let respond else { return }

        let body: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "permissionDecision": allow ? "allow" : "deny",
                "permissionDecisionReason": allow ? "Approved via Watchtower" : "Denied via Watchtower"
            ]
        ]

        let data = try? JSONSerialization.data(withJSONObject: body)
        respond(data)
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection, buffer: Data())
    }

    /// Accumulate data until we have a complete HTTP request
    private func readRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data { accumulated.append(data) }

            // Check if we have the full HTTP request
            if let (method, path, body) = self.parseHTTP(accumulated) {
                self.routeRequest(method: method, path: path, body: body, connection: connection)
                return
            }

            if isComplete || error != nil {
                // Connection done — try to process what we have
                if let (method, path, body) = self.parseHTTP(accumulated, force: true) {
                    self.routeRequest(method: method, path: path, body: body, connection: connection)
                } else {
                    connection.cancel()
                }
                return
            }

            // Need more data
            self.readRequest(connection: connection, buffer: accumulated)
        }
    }

    /// Parse raw HTTP bytes into method, path, and body.
    /// Returns nil if the request isn't complete yet.
    private func parseHTTP(_ data: Data, force: Bool = false) -> (String, String, Data?)? {
        guard let str = String(data: data, encoding: .utf8),
              let headerEnd = str.range(of: "\r\n\r\n") else {
            return force ? ("GET", "/", nil) : nil
        }

        let headerSection = str[..<headerEnd.lowerBound]
        let lines = headerSection.split(separator: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        // Find Content-Length
        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStartIndex = str.index(headerEnd.upperBound, offsetBy: 0)
        let bodyStr = String(str[bodyStartIndex...])
        let bodyData = bodyStr.data(using: .utf8) ?? Data()

        if bodyData.count < contentLength && !force {
            return nil // Body not fully received yet
        }

        return (method, path, bodyData.isEmpty ? nil : bodyData)
    }

    // MARK: - Routing

    private func routeRequest(method: String, path: String, body: Data?, connection: NWConnection) {
        // POST /toggle — show/hide the notch overlay
        if method == "POST", path == "/toggle" || path == "/toggle/" {
            DispatchQueue.main.async {
                NotchWindowController.shared.toggleVisibility()
            }
            let hidden = NotchWindowController.shared.isHidden
            let body = "{\"hidden\": \(!hidden)}".data(using: .utf8)
            sendResponse(connection: connection, status: 200, body: body)
            return
        }

        // POST /name — rename a session
        if method == "POST", path == "/name" || path == "/name/" {
            if let body,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let sessionId = json["session_id"] as? String,
               let name = json["name"] as? String {
                SessionScanner.setCustomName(sessionId: sessionId, name: name)
                // Update the in-memory session too
                DispatchQueue.main.async {
                    SessionManager.shared.sessions[sessionId]?.label = name
                    NotchWindowController.shared.refreshPanel()
                }
                Log.info("[Watchtower] Renamed \(sessionId.prefix(8)) → \"\(name)\"")
            }
            sendResponse(connection: connection, status: 200, body: nil)
            return
        }

        guard method == "POST", path == "/events" || path == "/events/" else {
            sendResponse(connection: connection, status: 404, body: nil)
            return
        }

        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let event = HookEvent(json: json) else {
            sendResponse(connection: connection, status: 200, body: nil)
            return
        }

        // For PermissionRequest events, hold the connection for approve/deny
        if event.hookEventName == "PermissionRequest" {
            let sessionId = event.sessionId

            lock.lock()
            pendingResponses[sessionId] = { [weak self] responseData in
                self?.sendResponse(connection: connection, status: 200, body: responseData)
            }
            lock.unlock()

            // Timeout: respond empty after 25s so Claude Code doesn't time out
            queue.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let respond = self.pendingResponses.removeValue(forKey: sessionId)
                self.lock.unlock()
                if let respond {
                    respond(nil) // empty response = fall through to terminal
                    // Clear the needsAttention status since user handled it in terminal
                    DispatchQueue.main.async {
                        SessionManager.shared.clearPermission(for: sessionId)
                    }
                }
            }
        } else {
            // All other events: respond immediately
            sendResponse(connection: connection, status: 200, body: nil)
        }

        // Dispatch event to the session manager on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    // MARK: - HTTP Response

    private func sendResponse(connection: NWConnection, status: Int, body: Data?) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Connection: close\r\n"

        if let body, !body.isEmpty {
            header += "Content-Length: \(body.count)\r\n\r\n"
            var responseData = header.data(using: .utf8)!
            responseData.append(body)
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            header += "Content-Length: 0\r\n\r\n"
            connection.send(content: header.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
