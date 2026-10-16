import Foundation
import SQLite3
import AVFoundation
import ClassNoteCore

enum ClassNoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// One protected local database. All access is serialized; transcript updates only touch one row.
final class LectureStore: @unchecked Sendable {
    let root: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClassNote", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true,
                                             attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = self.root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let url = self.root.appendingPathComponent("classnote.sqlite")
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw ClassNoteError.message("Impossibile aprire l’archivio locale.")
        }
        try sql("PRAGMA foreign_keys=ON;")
        try sql("PRAGMA journal_mode=WAL;")
        try sql("PRAGMA synchronous=FULL;")
        try sql("PRAGMA secure_delete=ON;")
        try sql("PRAGMA busy_timeout=3000;")
        try sql("CREATE TABLE IF NOT EXISTS lectures(id TEXT PRIMARY KEY, payload BLOB NOT NULL);")
        try sql("CREATE TABLE IF NOT EXISTS segments(id TEXT PRIMARY KEY, lecture_id TEXT NOT NULL REFERENCES lectures(id) ON DELETE CASCADE, start REAL NOT NULL, payload BLOB NOT NULL);")
        try sql("CREATE INDEX IF NOT EXISTS segments_lecture ON segments(lecture_id,start);")
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(db) }
    private func sql(_ statement: String) throws {
        if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK { throw failure() }
    }
    private func failure() -> Error { ClassNoteError.message("Archivio: \(String(cString: sqlite3_errmsg(db)))") }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw failure() }
        return s
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }
    private func bind(_ data: Data, to statement: OpaquePointer, at index: Int32) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
    }
    private func payload(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    func save(_ lecture: Lecture) throws {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("INSERT INTO lectures(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload;")
        defer { sqlite3_finalize(s) }
        bind(lecture.id.uuidString, to:s, at:1); bind(try encoder.encode(lecture), to:s, at:2)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    func save(_ segment: TranscriptSegment, lectureID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("INSERT INTO segments(id,lecture_id,start,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET start=excluded.start,payload=excluded.payload;")
        defer { sqlite3_finalize(s) }
        bind(segment.id.uuidString,to:s,at:1); bind(lectureID.uuidString,to:s,at:2)
        sqlite3_bind_double(s,3,segment.start); bind(try encoder.encode(segment),to:s,at:4)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    func list() throws -> [Lecture] {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT payload FROM lectures;"); defer { sqlite3_finalize(s) }
        var items: [Lecture] = []
        while sqlite3_step(s) == SQLITE_ROW { items.append(try decoder.decode(Lecture.self,from:payload(s,column:0))) }
        return items.sorted { $0.date > $1.date }
    }
    func segments(_ lectureID: UUID) throws -> [TranscriptSegment] {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("SELECT payload FROM segments WHERE lecture_id=? ORDER BY start;")
        defer { sqlite3_finalize(s) }; bind(lectureID.uuidString,to:s,at:1)
        var items: [TranscriptSegment] = []
        while sqlite3_step(s) == SQLITE_ROW { items.append(try decoder.decode(TranscriptSegment.self,from:payload(s,column:0))) }
        return items
    }
    func mediaDirectory(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,
                                               attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        return url
    }
    func media(_ id: UUID, _ name: String) throws -> URL {
        guard !name.isEmpty, name == (name as NSString).lastPathComponent,
              !name.contains(".."), !name.contains("\\"), !name.contains(":"), !name.hasPrefix(".") else {
            throw ClassNoteError.message("Nome di file non valido.")
        }
        return try mediaDirectory(id).appendingPathComponent(name)
    }
    func write(_ data: Data, lecture: UUID, name: String) throws {
        try data.write(to: media(lecture,name), options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    func delete(_ lectureID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare("DELETE FROM lectures WHERE id=?;"); defer { sqlite3_finalize(s) }
        bind(lectureID.uuidString,to:s,at:1)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
        let dir = root.appendingPathComponent(lectureID.uuidString)
        if FileManager.default.fileExists(atPath:dir.path) { try FileManager.default.removeItem(at:dir) }
        try sql("PRAGMA wal_checkpoint(TRUNCATE);")
    }
    /// Reconstruct missing manifest entries from sidecars. Closed audio is never discarded on ASR failure.
    func recover(_ lecture: Lecture) throws -> Lecture {
        var result = lecture
        let urls = try FileManager.default.contentsOfDirectory(at:mediaDirectory(lecture.id), includingPropertiesForKeys:nil)
        for url in urls where url.pathExtension == "chunkmeta" {
            var chunk = try decoder.decode(AudioChunk.self,from:Data(contentsOf:url))
            let audio = try media(lecture.id,chunk.filename)
            if !chunk.closed, FileManager.default.fileExists(atPath:audio.path) {
                let file = try AVAudioFile(forReading:audio)
                chunk.duration = Double(file.length) / file.processingFormat.sampleRate
                chunk.closed = true; chunk.recovered = true
                try write(try encoder.encode(chunk),lecture:lecture.id,name:url.lastPathComponent)
            }
            if chunk.duration > 0 {
                if let index = result.chunks.firstIndex(where:{$0.id == chunk.id}) { result.chunks[index] = chunk }
                else { result.chunks.append(chunk) }
            }
        }
        result.chunks.sort { $0.start < $1.start }; result.wasRecording = false
        try save(result); return result
    }
    func backup(_ lecture: Lecture, destination: URL) throws -> URL {
        guard !lecture.wasRecording else { throw ClassNoteError.message("Termina la registrazione prima del backup.") }
        let url = destination.appendingPathComponent("ClassNote-\(lecture.id.uuidString).classnotepackage",isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        do {
            try encoder.encode(lecture).write(to:url.appendingPathComponent("lecture.json"),options:.atomic)
            try encoder.encode(segments(lecture.id)).write(to:url.appendingPathComponent("segments.json"),options:.atomic)
            try FileManager.default.copyItem(at:mediaDirectory(lecture.id),to:url.appendingPathComponent("Media"))
            return url
        } catch { try? FileManager.default.removeItem(at:url); throw error }
    }
    func restore(_ package: URL) throws -> Lecture {
        for name in ["lecture.json","segments.json","Media"] {
            let flag = try package.appendingPathComponent(name).resourceValues(forKeys:[.isSymbolicLinkKey])
            guard flag.isSymbolicLink != true else { throw ClassNoteError.message("Backup con collegamenti simbolici non ammessi.") }
        }
        let lecture = try decoder.decode(Lecture.self,from:Data(contentsOf:package.appendingPathComponent("lecture.json")))
        guard lecture.schemaVersion == 1, !lecture.wasRecording else { throw ClassNoteError.message("Backup non compatibile o incompleto.") }
        guard try !list().contains(where:{$0.id == lecture.id}) else {
            throw ClassNoteError.message("Questa lezione esiste già. Il ripristino non sovrascrive i dati esistenti.")
        }
        let segments = try decoder.decode([TranscriptSegment].self,from:Data(contentsOf:package.appendingPathComponent("segments.json")))
        let source = package.appendingPathComponent("Media",isDirectory:true)
        let entries = try FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard entries.count < 100_000 else { throw ClassNoteError.message("Il backup contiene troppi file.") }
        var lastEnd = 0.0
        for chunk in lecture.chunks.sorted(by:{$0.start < $1.start}) {
            guard chunk.start.isFinite, chunk.duration.isFinite, chunk.sampleRate.isFinite,
                  chunk.duration > 0, chunk.start >= lastEnd-0.001, chunk.sampleRate > 0, chunk.closed else {
                throw ClassNoteError.message("Timeline del backup non valida.")
            }
            lastEnd = chunk.end
        }
        for entry in entries {
            let flags = try entry.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard flags.isRegularFile == true, flags.isSymbolicLink != true else { throw ClassNoteError.message("Backup con file non ammessi.") }
            _ = try media(lecture.id,entry.lastPathComponent)
        }
        let referenced = lecture.chunks.map(\.filename) + lecture.pages.map(\.drawingFile) + lecture.documents.map(\.filename)
        for name in referenced {
            _ = try media(lecture.id,name)
            // Empty pages do not yet have a drawing file.
            if !name.hasSuffix(".drawing"), !entries.contains(where:{$0.lastPathComponent == name}) {
                throw ClassNoteError.message("Il backup non contiene tutti i file necessari.")
            }
        }
        do {
            for entry in entries {
                let dest = try media(lecture.id,entry.lastPathComponent)
                try FileManager.default.copyItem(at:entry,to:dest)
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:dest.path)
            }
            try save(lecture)
            for segment in segments { try save(segment,lectureID:lecture.id) }
            return lecture
        } catch { try? delete(lecture.id); throw error }
    }
}
