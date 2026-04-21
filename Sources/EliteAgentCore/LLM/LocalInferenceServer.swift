import Foundation
import Network
import os

/// A lightweight, native macOS HTTP server that exposes the InferenceActor via an Ollama-compatible API.
/// Defaults to port 11500.
public actor LocalInferenceServer {
    public static let shared = LocalInferenceServer()
    
    private var listener: NWListener?
    private var port: NWEndpoint.Port = 11500
    private let logger = Logger(subsystem: "app.eliteagent", category: "LocalServer")
    
    @MainActor public private(set) var isRunning = false
    
    private init() {}
    
    public func start(portNumber: Int? = nil) throws {
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
                self.logger.info("Titan Local API Server ready on port \(portToUse.rawValue)")
            case .failed(let error):
                Task { @MainActor in 
                    self.isRunning = false 
                    AISessionState.shared.isLocalServerRunning = false
                }
                self.logger.error("Local Server failed: \(error.localizedDescription)")
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
        logger.info("Titan Local API Server stopped.")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection)
    }
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { await self.processRequest(data, on: connection) }
            }
            if error != nil || isComplete {
                connection.cancel()
            }
        }
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
            handleInferenceRequest(requestString, on: connection)
        } else if method == "GET" && path == "/api/tags" {
            handleTagsRequest(on: connection)
        } else {
            sendResponse(on: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func handleInferenceRequest(_ request: String, on connection: NWConnection) {
        // Simple JSON extractor for proof-of-concept
        // In a real scenario, we'd use a proper HTTP parser to get the body.
        guard let bodyRange = request.range(of: "\r\n\r\n") else {
            sendResponse(on: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let bodyData = Data(request[bodyRange.upperBound...].utf8)
        
        Task {
            do {
                // v9.0: Native Binary-Safe Inference Pipeline
                // We extract the prompt from the JSON body
                let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let prompt = json?["prompt"] as? String ?? (json?["messages"] as? [[String: Any]])?.last?["content"] as? String ?? ""
                
                let stream = await InferenceActor.shared.generate(
                    messages: [Message(role: "user", content: prompt)],
                    maxTokens: json?["max_tokens"] as? Int ?? 200
                )
                
                sendStreamHeader(on: connection)
                
                for await chunk in stream {
                    let responseObj: [String: Any] = ["response": chunk, "done": false]
                    let responseData = try JSONSerialization.data(withJSONObject: responseObj)
                    connection.send(content: responseData + "\n".data(using: .utf8)!, completion: .contentProcessed({ _ in }))
                }
                
                let finalObj: [String: Any] = ["done": true]
                let finalData = try JSONSerialization.data(withJSONObject: finalObj)
                connection.send(content: finalData + "\n".data(using: .utf8)!, completion: .contentProcessed({ _ in 
                    connection.cancel()
                }))
                
            } catch {
                sendResponse(on: connection, statusCode: 500, body: "Internal Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleTagsRequest(on connection: NWConnection) {
        let models = ModelRegistry.availableModels.map { ["name": $0.name, "id": $0.id] }
        let body: [String: Any] = ["models": models]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            sendJSONResponse(on: connection, data: data)
        }
    }
    
    private func sendResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let response = "HTTP/1.1 \(statusCode) OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in 
            connection.cancel()
        }))
    }
    
    private func sendJSONResponse(on connection: NWConnection, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: header.data(using: .utf8)! + data, completion: .contentProcessed({ _ in 
            connection.cancel()
        }))
    }
    
    private func sendStreamHeader(on connection: NWConnection) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nTransfer-Encoding: chunked\r\n\r\n"
        connection.send(content: header.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }
}
