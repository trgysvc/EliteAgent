import Foundation
import Network
import CryptoKit

/// A lightweight, native macOS HTTP server that exposes the InferenceActor via an Ollama-compatible API.
/// Defaults to port 11500.
///
/// Endpoints:
///   POST /api/generate          — Raw LLM inference (Ollama-compatible)
///   POST /v1/chat/completions   — Raw LLM inference (OpenAI-compatible)
///   POST /api/agent             — Full Orchestrator pipeline (intent → tools → response)
///   GET  /api/tags              — List available models
///   GET  /api/health            — Server and model health check
public actor LocalInferenceServer {
    public static let shared = LocalInferenceServer()

    private var listener: NWListener?
    private var port: NWEndpoint.Port = 11500

    @MainActor public private(set) var isRunning = false

    private init() {}

    public func start(portNumber: Int? = nil) throws {
        // v11.1: Guard against port conflicts by ensuring the previous listener is closed.
        self.stop()

        if let p = portNumber {
            self.port = NWEndpoint.Port(integerLiteral: UInt16(p))
        }
        let parameters = NWParameters.tcp
        let portToUse = self.port
        let listener = try NWListener(using: parameters, on: portToUse)

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self.isRunning = true
                    AISessionState.shared.isLocalServerRunning = true
                }
                AgentLogger.logInfo("Titan Local API Server ready on port \(portToUse.rawValue)", agent: "LocalServer")
            case .failed(let error):
                Task { @MainActor in
                    self.isRunning = false
                    AISessionState.shared.isLocalServerRunning = false
                }
                AgentLogger.logError("Local Server failed: \(error.localizedDescription)", agent: "LocalServer")
            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in
            Task { await self.handleConnection(connection) }
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        Task { @MainActor in
            isRunning = false
            AISessionState.shared.isLocalServerRunning = false
        }
        AgentLogger.logInfo("Titan Local API Server stopped.", agent: "LocalServer")
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            Task {
                await self.handleReceivedData(data, isComplete: isComplete, error: error, on: connection, accumulated: accumulated)
            }
        }
    }

    private func handleReceivedData(_ data: Data?, isComplete: Bool, error: Error?, on connection: NWConnection, accumulated: Data) {
        var current = accumulated
        if let data = data {
            current.append(data)
        }

        if isRequestComplete(current) {
            processRequest(current, on: connection)
        } else if error == nil && !isComplete {
            receiveRequest(on: connection, accumulated: current)
        } else {
            connection.cancel()
        }
    }

    private func isRequestComplete(_ data: Data) -> Bool {
        guard let requestString = String(data: data, encoding: .utf8) else { return false }
        guard let headerEndRange = requestString.range(of: "\r\n\r\n") else { return false }

        let headers = requestString[..<headerEndRange.lowerBound]
        if let contentLengthRange = headers.range(of: "Content-Length: ", options: .caseInsensitive) {
            let start = contentLengthRange.upperBound
            let end = headers[start...].range(of: "\r\n")?.lowerBound ?? headers.endIndex
            if let length = Int(headers[start..<end].trimmingCharacters(in: .whitespaces)) {
                let bodyData = data.advanced(by: requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound))
                return bodyData.count >= length
            }
        }

        // If no Content-Length, assume complete if we have headers (for GET) or just return true for now
        return true
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        let requestString = String(data: data, encoding: .utf8) ?? ""
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let path = parts[1]

        if method == "POST" && path == "/api/agent" {
            handleAgentRequest(data: data, on: connection)
        } else if method == "POST" && (path == "/api/generate" || path == "/v1/chat/completions") {
            handleInferenceRequest(data: data, on: connection)
        } else if method == "GET" && path == "/api/tags" {
            handleTagsRequest(on: connection)
        } else if method == "GET" && path == "/api/health" {
            Task {
                let modelLoaded = await InferenceActor.shared.isModelLoaded
                let body = "{\"status\":\"ok\",\"model_loaded\":\(modelLoaded),\"port\":\(self.port.rawValue)}"
                sendResponse(on: connection, statusCode: 200, body: body)
            }
        } else {
            sendResponse(on: connection, statusCode: 404, body: "Not Found")
        }
    }

    private func handleInferenceRequest(data: Data, on connection: NWConnection) {
        guard let separatorData = "\r\n\r\n".data(using: .utf8),
              let headerEndRange = data.range(of: separatorData) else {
            sendResponse(on: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let bodyData = data.advanced(by: headerEndRange.upperBound)

        Task {
            do {
                // HTTP boundary: external clients (Ollama-compatible) send JSON
                let request = try UNOExternalBridge.decodeExternalDecodable(InferenceRequest.self, from: bodyData)

                let prompt = request.prompt ?? request.messages?.last?["content"] ?? ""
                let maxTokens = request.max_tokens ?? 200

                let stream = try await InferenceActor.shared.generate(
                    messages: [Message(role: "user", content: prompt)],
                    maxTokens: maxTokens
                )

                sendStreamHeader(on: connection)

                for await chunk in stream {
                    guard case .token(let text) = chunk else { continue }

                    let response = InferenceResponse(response: text, done: false)
                    guard let responseData = UNOExternalBridge.encodeEncodable(response) else { continue }

                    // HTTP Chunked encoding: <length in hex>\r\n<data>\r\n
                    let hexLength = String(responseData.count, radix: 16)
                    let chunkData = Data("\(hexLength)\r\n".utf8) + responseData + Data("\r\n".utf8)
                    connection.send(content: chunkData, completion: .contentProcessed({ _ in }))
                }

                let finalResponse = InferenceResponse(response: nil, done: true)
                guard let finalData = UNOExternalBridge.encodeEncodable(finalResponse) else { return }
                let finalHex = String(finalData.count, radix: 16)
                let terminator = Data("\(finalHex)\r\n".utf8) + finalData + Data("\r\n0\r\n\r\n".utf8)
                connection.send(content: terminator, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))

            } catch {
                AgentLogger.logError("Inference Request Failed: \(error.localizedDescription)", agent: "LocalServer")
                sendResponse(on: connection, statusCode: 500, body: "Internal Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - /api/agent — Full Orchestrator Pipeline

    private func handleAgentRequest(data: Data, on connection: NWConnection) {
        Task {
            guard let separatorData = "\r\n\r\n".data(using: .utf8),
                  let headerEndRange = data.range(of: separatorData) else {
                sendResponse(on: connection, statusCode: 400, body: "Bad Request")
                return
            }
            let bodyData = data.advanced(by: headerEndRange.upperBound)

            do {
                let request = try UNOExternalBridge.decodeExternalDecodable(AgentAPIRequest.self, from: bodyData)

                // Same symmetric key as the main Orchestrator so bus signals route correctly.
                let busKey = SymmetricKey(data: SHA256.hash(data: "ELITE_BUS_SECRET".data(using: .utf8)!))
                let bus = SignalBus(secretKey: busKey)
                let localProvider = MLXProvider(providerID: .mlx)
                let planner = PlannerAgent(bus: bus)
                let memory = MemoryAgent(bus: bus)

                // VaultManager.shared is set by the running Orchestrator on @MainActor.
                guard let vault = await MainActor.run(body: { VaultManager.shared }) else {
                    let errBody = AgentAPIResponse(response: "", toolsUsed: [], category: "", done: false,
                                                   error: "VaultManager not ready — start EliteAgent app first.")
                    sendAgentResponse(errBody, on: connection)
                    return
                }

                // ToolRegistry.shared already has all 38 tools registered by the running app.
                let runtime = OrchestratorRuntime(
                    planner: planner,
                    memory: memory,
                    cloudProvider: nil,
                    localProvider: localProvider,
                    toolRegistry: ToolRegistry.shared,
                    bus: bus,
                    vaultManager: vault
                )

                let collector = AgentResponseCollector()

                await runtime.setChatMessageUpdateHandler { msg in
                    guard !msg.isStatus else { return }
                    Task { await collector.capture(response: msg.content) }
                }
                await runtime.setStepUpdateHandler { step in
                    Task { await collector.addTool(step.name) }
                }

                let workspaceURL = request.workspace.map { URL(fileURLWithPath: $0) }
                    ?? PathConfiguration.shared.workspaceURL
                let session = Session(workspaceURL: workspaceURL, complexity: 3)

                do {
                    try await runtime.executeTask(
                        prompt: request.prompt,
                        session: session,
                        complexity: 3,
                        config: .default
                    )
                } catch {
                    AgentLogger.logError("[AgentAPI] executeTask failed: \(error.localizedDescription)", agent: "LocalServer")
                }

                var finalResponse = await collector.response
                if finalResponse.isEmpty {
                    finalResponse = await session.finalAnswer ?? ""
                }
                
                let toolsUsed = await collector.toolsUsed
                let agentResponse = AgentAPIResponse(
                    response: finalResponse.isEmpty ? "(no response)" : finalResponse,
                    toolsUsed: toolsUsed,
                    category: "",
                    done: true,
                    error: nil
                )
                sendAgentResponse(agentResponse, on: connection)

            } catch {
                AgentLogger.logError("[AgentAPI] Request parse failed: \(error.localizedDescription)", agent: "LocalServer")
                sendResponse(on: connection, statusCode: 400, body: "Bad Request: \(error.localizedDescription)")
            }
        }
    }

    private func sendAgentResponse(_ response: AgentAPIResponse, on connection: NWConnection) {
        guard let data = UNOExternalBridge.encodeEncodable(response) else {
            sendResponse(on: connection, statusCode: 500, body: "Encoding error")
            return
        }
        sendJSONResponse(on: connection, data: data)
    }

    private func handleTagsRequest(on connection: NWConnection) {
        let models = ModelRegistry.availableModels.map { ["name": $0.name, "id": $0.id] }
        let body: [String: [[String: String]]] = ["models": models]

        if let data = UNOExternalBridge.encodeEncodable(body) {
            sendJSONResponse(on: connection, data: data)
        } else {
            sendResponse(on: connection, statusCode: 500, body: "Internal Error")
        }
    }

    private func sendResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let response = "HTTP/1.1 \(statusCode) OK\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendJSONResponse(on connection: NWConnection, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendStreamHeader(on connection: NWConnection) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ _ in }))
    }
}

// MARK: - Agent API response collector (actor-isolated for thread safety)

private actor AgentResponseCollector {
    private(set) var response: String = ""
    private(set) var toolsUsed: [String] = []

    func capture(response: String) { self.response = response }
    func addTool(_ name: String) {
        if !toolsUsed.contains(name) { toolsUsed.append(name) }
    }
}

// MARK: - Binary DTOs

struct AgentAPIRequest: Codable {
    let prompt: String
    let workspace: String?
}

struct AgentAPIResponse: Codable {
    let response: String
    let toolsUsed: [String]
    let category: String
    let done: Bool
    let error: String?
}

struct InferenceRequest: Codable {
    let prompt: String?
    let messages: [[String: String]]?
    let max_tokens: Int?
}

struct InferenceResponse: Codable {
    let response: String?
    let done: Bool
}
