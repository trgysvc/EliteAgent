import Foundation
import Network

/// A lightweight, native macOS HTTP server that exposes the InferenceActor via an Ollama-compatible API.
/// Defaults to port 11500.
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
        
        if method == "POST" && (path == "/api/generate" || path == "/v1/chat/completions") {
            handleInferenceRequest(data: data, on: connection)
        } else if method == "GET" && path == "/api/tags" {
            handleTagsRequest(on: connection)
        } else {
            sendResponse(on: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func handleInferenceRequest(data: Data, on connection: NWConnection) {
        guard let headerEndRange = data.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            sendResponse(on: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let bodyData = data.advanced(by: headerEndRange.upperBound)
        
        Task {
            do {
                // HTTP boundary: external clients (Ollama-compatible) send JSON
                let decoder = JSONDecoder()
                let request = try decoder.decode(InferenceRequest.self, from: bodyData)
                
                let prompt = request.prompt ?? request.messages?.last?["content"] ?? ""
                let maxTokens = request.max_tokens ?? 200
                
                let stream = try await InferenceActor.shared.generate(
                    messages: [Message(role: "user", content: prompt)],
                    maxTokens: maxTokens
                )
                
                sendStreamHeader(on: connection)

                let encoder = JSONEncoder()

                for await chunk in stream {
                    guard case .token(let text) = chunk else { continue }

                    let response = InferenceResponse(response: text, done: false)
                    let responseData = try encoder.encode(response)

                    // HTTP Chunked encoding: <length in hex>\r\n<data>\r\n
                    let hexLength = String(responseData.count, radix: 16)
                    let chunkData = Data("\(hexLength)\r\n".utf8) + responseData + Data("\r\n".utf8)
                    connection.send(content: chunkData, completion: .contentProcessed({ _ in }))
                }

                let finalResponse = InferenceResponse(response: nil, done: true)
                let finalData = try encoder.encode(finalResponse)
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
    
    private func handleTagsRequest(on connection: NWConnection) {
        let models = ModelRegistry.availableModels.map { ["name": $0.name, "id": $0.id] }
        let body: [String: [[String: String]]] = ["models": models]

        do {
            let data = try JSONEncoder().encode(body)
            sendJSONResponse(on: connection, data: data)
        } catch {
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

// MARK: - Binary DTOs

struct InferenceRequest: Codable {
    let prompt: String?
    let messages: [[String: String]]?
    let max_tokens: Int?
}

struct InferenceResponse: Codable {
    let response: String?
    let done: Bool
}
