import AVFoundation

let path = "/Users/trgysvc/Developer/EliteAgent/analysis_target.mp3"
let url = URL(fileURLWithPath: path)

do {
    print("Testing AVAudioFile for: \(path)")
    let file = try AVAudioFile(forReading: url)
    print("Success! Length: \(file.length) frames, SR: \(file.fileFormat.sampleRate)")
} catch {
    print("FAILED: \(error)")
}
