import Foundation
import SQLite3

public struct ExperienceEntry: Codable, Sendable {
    public let id: Int64?
    public let task: String
    public let solution: String
    public let timestamp: Date
}

public actor ExperienceVault {
    public static let shared = ExperienceVault()
    private var db: OpaquePointer?
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let eliteDir = appSupport.appendingPathComponent("EliteAgent")
        try? FileManager.default.createDirectory(at: eliteDir, withIntermediateDirectories: true)
        let dbPath = eliteDir.appendingPathComponent("experience_vault.sqlite").path
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[ExperienceVault] Failed to open DB")
            return
        }
        
        // Setup tables in a detached task to avoid actor isolation issues in init
        Task {
            await self.createTables()
        }
    }
    
    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS experiences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task TEXT NOT NULL,
            solution TEXT NOT NULL,
            embedding BLOB,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            summary TEXT NOT NULL,
            full_text TEXT,
            embedding BLOB,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS habits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            description TEXT NOT NULL,
            frequency INTEGER DEFAULT 1,
            embedding BLOB,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_task ON experiences(task);
        CREATE INDEX IF NOT EXISTS idx_conv_embedding ON conversations(embedding);
        CREATE INDEX IF NOT EXISTS idx_habit_embedding ON habits(embedding);
        """
        execute(sql)
    }
    
    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = String(cString: errMsg!)
            print("[ExperienceVault] SQL Error: \(error)")
            sqlite3_free(errMsg)
        }
    }
    
    public func save(task: String, solution: String, embedding: [Float]) {
        let sql = "INSERT INTO experiences (task, solution, embedding) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (task as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (solution as NSString).utf8String, -1, nil)
            
            // Fix dangling pointer by creating a persistent Data object
            let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("[ExperienceVault] Failed to insert experience")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // Helper to ensure we don't use the db pointer before it's ready/if it fails
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    public func search(embedding: [Float], limit: Int = 3) -> [(task: String, solution: String, score: Float)] {
        // Fast retrieval from SQLite
        let sql = "SELECT task, solution, embedding FROM experiences;"
        var statement: OpaquePointer?
        var results: [(String, String, Float)] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let task = String(cString: sqlite3_column_text(statement, 0))
                let solution = String(cString: sqlite3_column_text(statement, 1))
                
                if let blob = sqlite3_column_blob(statement, 2) {
                    let count = Int(sqlite3_column_bytes(statement, 2)) / MemoryLayout<Float>.size
                    let pointer = blob.bindMemory(to: Float.self, capacity: count)
                    let storedVector = Array(UnsafeBufferPointer(start: pointer, count: count))
                    
                    let score = cosineSimilarity(embedding, storedVector)
                    results.append((task, solution, score))
                }
            }
        }
        sqlite3_finalize(statement)
        
        return results.sorted { $0.2 > $1.2 }.prefix(limit).map { $0 }
    }
    
    private func cosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count, v1.count > 0 else { return 0 }
        var dotProduct: Float = 0
        var mag1: Float = 0
        var mag2: Float = 0
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            mag1 += v1[i] * v1[i]
            mag2 += v2[i] * v2[i]
        }
        return dotProduct / (sqrt(mag1) * sqrt(mag2))
    }
    
    // Singleton deinit is handled by process exit; actor deinit isolation is complex for pointers.
}
