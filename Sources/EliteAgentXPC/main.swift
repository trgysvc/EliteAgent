import Foundation

@objc public protocol SandboxProtocol {
    func runCommand(_ command: String, inDirectory directory: String?, reply: @escaping (String?, Error?) -> Void)
}

class SandboxXPCService: NSObject, NSXPCListenerDelegate, SandboxProtocol {
    func runCommand(_ command: String, inDirectory directory: String?, reply: @escaping (String?, Error?) -> Void) {
        let prohibited = ["rm -rf /", "sudo rm -rf", "chmod -R 777 /"]
        guard !prohibited.contains(where: { command.contains($0) }) else {
            reply(nil, NSError(domain: "SandboxError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Forbidden command detected. Operation Blocked."]))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let dir = directory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            reply(output, nil)
        } catch {
            reply(nil, error)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SandboxProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
}

let delegate = SandboxXPCService()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
