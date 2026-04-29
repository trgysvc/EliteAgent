import Foundation

public struct ID3EditorTool: AgentTool {
    public let name = "id3_editor"
    public let summary = "Modifies MP3 ID3 tags and cover art natively."
    public let description = "Embeds ID3 tags and a JPEG cover art into an MP3 file. Params: path (mp3 path), title (string), coverPath (jpeg path)."
    public let ubid: Int128 = 85
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let path = params["path"]?.value as? String,
              let title = params["title"]?.value as? String,
              let coverPath = params["coverPath"]?.value as? String else {
            throw AgentToolError.missingParameter("path, title, or coverPath")
        }
        
        let pyScript = """
import sys
import os
import subprocess

def install_and_run():
    try:
        import mutagen
        from mutagen.mp3 import MP3
        from mutagen.id3 import ID3, APIC, TIT2, error
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "--break-system-packages", "mutagen"])
        import mutagen
        from mutagen.mp3 import MP3
        from mutagen.id3 import ID3, APIC, TIT2, error

    mp3_path = sys.argv[1]
    title = sys.argv[2]
    cover_path = sys.argv[3]

    audio = MP3(mp3_path, ID3=ID3)
    try:
        audio.add_tags()
    except error:
        pass

    audio.tags.add(TIT2(encoding=3, text=title))
    with open(cover_path, 'rb') as img:
        audio.tags.add(
            APIC(
                encoding=3,
                mime='image/jpeg',
                type=3,
                desc=u'Cover',
                data=img.read()
            )
        )
    audio.save()

if __name__ == '__main__':
    install_and_run()
"""
        let scriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("id3_edit_\(UUID().uuidString).py")
        try? pyScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptPath) }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptPath.path, path, title, coverPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return "HATA: Python script başarısız oldu. Çıkış Kodu: \(process.terminationStatus)"
            }
            return "SUCCESS: ID3 tag and cover applied to \(path)"
        } catch {
            return "HATA: Script çalıştırılamadı: \(error.localizedDescription)"
        }
    }
}
