import Foundation

fileprivate extension UInt32 {
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }
}

public struct ID3EditorTool: AgentTool {
    public let name = "id3_processor"
    public let summary = "Recursive Native Swift Music Processor (ID3, Cover Art, Rename, Cleanup)."
    public let description = "Processes a directory and all subdirectories. Matches MP3s with JSON/TXT/JPEG files, embeds metadata, renames cleanly, and cleans up. Param: directory (string)."
    public let ubid: Int128 = 85
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let dirPath = params["directory"]?.value as? String else {
            throw AgentToolError.missingParameter("directory")
        }
        
        let expandedPath = dirPath.hasPrefix("~")
            ? dirPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            : dirPath
            
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: expandedPath)
        
        guard fm.fileExists(atPath: rootURL.path) else {
            return "HATA: Klasör bulunamadı - \(expandedPath)"
        }
        
        var processedCount = 0
        var errorCount = 0
        
        // v2.1: Recursive Enumerator to find all MP3s in any subfolder
        let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "mp3" else { continue }
            
            let containerURL = fileURL.deletingLastPathComponent()
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            
            let jsonURL = containerURL.appendingPathComponent(baseName + ".json")
            let txtURL = containerURL.appendingPathComponent(baseName + ".txt")
            var jpegURL = containerURL.appendingPathComponent(baseName + ".jpeg")
            if !fm.fileExists(atPath: jpegURL.path) {
                jpegURL = containerURL.appendingPathComponent(baseName + ".jpg")
            }
            
            var title = baseName
            
            // Extract Title from JSON
            if fm.fileExists(atPath: jsonURL.path), let data = try? Data(contentsOf: jsonURL) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let t = json["title"] as? String, !t.isEmpty {
                    title = t
                }
            } else if fm.fileExists(atPath: txtURL.path), let text = try? String(contentsOf: txtURL, encoding: .utf8) {
                title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            do {
                // Native ID3 Write
                try writeID3Native(to: fileURL, title: title, jpegURL: fm.fileExists(atPath: jpegURL.path) ? jpegURL : nil)
                
                // Clean Rename
                let allowedChars = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
                var cleanTitle = String(title.unicodeScalars.filter { allowedChars.contains($0) }).trimmingCharacters(in: .whitespaces)
                if cleanTitle.isEmpty { cleanTitle = "Track_\(processedCount)" }
                
                var targetURL = containerURL.appendingPathComponent(cleanTitle + ".mp3")
                var counter = 1
                while fm.fileExists(atPath: targetURL.path) && targetURL.path != fileURL.path {
                    targetURL = containerURL.appendingPathComponent("\(cleanTitle) \(counter).mp3")
                    counter += 1
                }
                
                if targetURL.path != fileURL.path {
                    try fm.moveItem(at: fileURL, to: targetURL)
                }
                
                // Cleanup
                for metaURL in [jsonURL, txtURL, jpegURL] {
                    if fm.fileExists(atPath: metaURL.path) {
                        try? fm.removeItem(at: metaURL)
                    }
                }
                
                processedCount += 1
            } catch {
                errorCount += 1
            }
        }
        
        return "İŞLEM TAMAM: \(processedCount) dosya başarıyla işlendi. \(errorCount) hata oluştu."
    }
    
    private func writeID3Native(to mp3URL: URL, title: String, jpegURL: URL?) throws {
        let originalData = try Data(contentsOf: mp3URL)
        var audioStartIndex = 0
        if originalData.count > 10 && originalData[0...2] == Data([0x49, 0x44, 0x33]) {
            let sizeBytes = originalData[6...9]
            let tagSize = Int(sizeBytes[sizeBytes.startIndex]) << 21 |
                          Int(sizeBytes[sizeBytes.startIndex + 1]) << 14 |
                          Int(sizeBytes[sizeBytes.startIndex + 2]) << 7 |
                          Int(sizeBytes[sizeBytes.startIndex + 3])
            audioStartIndex = 10 + tagSize
        }
        let audioData = originalData.subdata(in: audioStartIndex..<originalData.count)
        
        var framesData = Data()
        // TIT2
        var tit2Data = Data([0x01]) // UTF-16
        if let utf16 = title.data(using: .utf16) {
            tit2Data.append(utf16); tit2Data.append(Data([0x00, 0x00]))
            framesData.append("TIT2".data(using: .ascii)!); framesData.append(UInt32(tit2Data.count).bigEndianData)
            framesData.append(Data([0x00, 0x00])); framesData.append(tit2Data)
        }
        // APIC
        if let jpeg = jpegURL, let jpegData = try? Data(contentsOf: jpeg) {
            var apicData = Data([0x00]); apicData.append("image/jpeg".data(using: .ascii)!); apicData.append(Data([0x00]))
            apicData.append(Data([0x03])); apicData.append("Cover".data(using: .ascii)!); apicData.append(Data([0x00])); apicData.append(jpegData)
            framesData.append("APIC".data(using: .ascii)!); framesData.append(UInt32(apicData.count).bigEndianData)
            framesData.append(Data([0x00, 0x00])); framesData.append(apicData)
        }
        
        let tagSize = framesData.count
        let b = [UInt8((tagSize >> 21) & 0x7F), UInt8((tagSize >> 14) & 0x7F), UInt8((tagSize >> 7) & 0x7F), UInt8(tagSize & 0x7F)]
        var finalData = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) + Data(b) + framesData + audioData
        try finalData.write(to: mp3URL, options: .atomic)
    }
}
