import Foundation

fileprivate extension UInt32 {
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }
}

public struct ID3EditorTool: AgentTool {
    public let name = "id3_processor"
    public let summary = "Recursive Native Swift Music Processor (Universal ID3 Tag Support)."
    public let description = "Embeds all metadata from JSON/TXT and supports manual overrides for ANY ID3 tag. Param: directory (string), custom_tags (dictionary, optional - e.g. {'TPE1': 'Artist', 'TALB': 'Album'})."
    public let ubid: Int128 = 85
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let dirPath = params["directory"]?.value as? String else {
            throw AgentToolError.missingParameter("directory")
        }
        
        let customOverrides = params["custom_tags"]?.value as? [String: String] ?? [:]
        
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
            
            var metadata: [String: String] = [:]
            
            // 1. Process JSON
            if fm.fileExists(atPath: jsonURL.path), let data = try? Data(contentsOf: jsonURL) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadata["TIT2"] = json["title"] as? String
                    metadata["TPE1"] = json["display_name"] as? String
                    metadata["TALB"] = json["project_name"] as? String
                    
                    var commentParts: [String] = []
                    if let inner = json["metadata"] as? [String: Any] {
                        if let tags = inner["tags"] as? String { commentParts.append("Tags: \(tags)") }
                        if let prompt = inner["prompt"] as? String { commentParts.append("Prompt: \(prompt)") }
                    }
                    if !commentParts.isEmpty {
                        metadata["COMM"] = commentParts.joined(separator: "\n\n")
                    }
                }
            }
            
            // 2. Process TXT
            if fm.fileExists(atPath: txtURL.path), let text = try? String(contentsOf: txtURL, encoding: .utf8) {
                metadata["USLT"] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if metadata["TIT2"] == nil {
                    metadata["TIT2"] = text.components(separatedBy: .newlines).first
                }
            }
            
            // 3. Apply CUSTOM OVERRIDES (Turgay's explicit request)
            for (key, value) in customOverrides {
                metadata[key] = value
            }
            
            let finalTitle = metadata["TIT2"] ?? baseName
            
            do {
                try writeID3Native(to: fileURL, metadata: metadata, jpegURL: fm.fileExists(atPath: jpegURL.path) ? jpegURL : nil)
                
                // Clean Rename
                let allowedChars = CharacterSet.letters.union(CharacterSet.whitespaces)
                var cleanTitle = String(finalTitle.unicodeScalars.filter { allowedChars.contains($0) }).trimmingCharacters(in: .whitespaces)
                if cleanTitle.isEmpty { cleanTitle = "UnknownTrack" }
                
                var targetURL = containerURL.appendingPathComponent(cleanTitle + ".mp3")
                let suffixes = ["Alternative", "Variation", "Original", "Mix", "Edit"]
                var suffixIndex = 0
                
                while fm.fileExists(atPath: targetURL.path) && targetURL.path != fileURL.path {
                    if suffixIndex < suffixes.count {
                        targetURL = containerURL.appendingPathComponent("\(cleanTitle) \(suffixes[suffixIndex]).mp3")
                        suffixIndex += 1
                    } else {
                        targetURL = containerURL.appendingPathComponent("\(cleanTitle) \(processedCount).mp3")
                    }
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
        
        return "İŞLEM TAMAM: \(processedCount) dosya işlendi. Manuel girilen etiketler (Artist: \(customOverrides["TPE1"] ?? "N/A"), Album: \(customOverrides["TALB"] ?? "N/A")) başarıyla uygulandı."
    }
    
    private func writeID3Native(to mp3URL: URL, metadata: [String: String], jpegURL: URL?) throws {
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
        
        for (key, value) in metadata {
            guard !value.isEmpty else { continue }
            
            let encodingByte: UInt8 = 0x01
            guard let textData = value.data(using: .utf16) else { continue }
            
            var frameBody = Data()
            if key == "COMM" || key == "USLT" {
                frameBody.append(encodingByte)
                frameBody.append("eng".data(using: .ascii)!)
                frameBody.append(Data([0xFE, 0xFF, 0x00, 0x00]))
                frameBody.append(textData)
                frameBody.append(Data([0x00, 0x00]))
            } else {
                frameBody.append(encodingByte)
                frameBody.append(textData)
                frameBody.append(Data([0x00, 0x00]))
            }
            
            framesData.append(key.data(using: .ascii)!)
            framesData.append(UInt32(frameBody.count).bigEndianData)
            framesData.append(Data([0x00, 0x00]))
            framesData.append(frameBody)
        }
        
        if let jpeg = jpegURL, let jpegData = try? Data(contentsOf: jpeg) {
            var apicData = Data([0x00])
            apicData.append("image/jpeg".data(using: .ascii)!)
            apicData.append(Data([0x00, 0x03, 0x00]))
            apicData.append(jpegData)
            
            framesData.append("APIC".data(using: .ascii)!)
            framesData.append(UInt32(apicData.count).bigEndianData)
            framesData.append(Data([0x00, 0x00]))
            framesData.append(apicData)
        }
        
        let tagSize = framesData.count
        let b = [UInt8((tagSize >> 21) & 0x7F), UInt8((tagSize >> 14) & 0x7F), UInt8((tagSize >> 7) & 0x7F), UInt8(tagSize & 0x7F)]
        let finalData = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) + Data(b) + framesData + audioData
        try finalData.write(to: mp3URL, options: .atomic)
    }
}
