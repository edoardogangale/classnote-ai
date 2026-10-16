import Foundation

public enum WordState: String, Codable, Sendable { case provisional, confirmed, interrupted }
public enum Alignment: String, Codable, Sendable { case recognizer, retained, needsReview }

public struct TimedWord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var start: Double?
    public var end: Double?
    public var chunkID: UUID?
    public var confidence: Float?
    public var state: WordState
    public var alignment: Alignment
    public init(id: UUID = UUID(), text: String, start: Double?, end: Double?,
                chunkID: UUID? = nil, confidence: Float? = nil,
                state: WordState = .provisional, alignment: Alignment = .recognizer) {
        self.id = id; self.text = text; self.start = start; self.end = end
        self.chunkID = chunkID; self.confidence = confidence; self.state = state
        self.alignment = alignment
    }
    public func contains(_ time: Double) -> Bool {
        guard let start, let end else { return false }
        return start <= time && time < end
    }
}

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var source: String
    public var original: String
    public var words: [TimedWord]
    public var corrected: String?
    public var correctedWords: [TimedWord]?
    public var correctionProposal: String?
    public var start: Double
    public var end: Double
    public var finalized: Bool
    public var displayText: String { corrected ?? original }
    public var displayWords: [TimedWord] { correctedWords ?? words }
    public init(id: UUID = UUID(), source: String, original: String, words: [TimedWord],
                start: Double, end: Double, finalized: Bool = false) {
        self.id = id; self.source = source; self.original = original; self.words = words
        self.start = start; self.end = end; self.finalized = finalized
    }
    public mutating func acceptCorrection(_ text: String) {
        corrected = text
        correctedWords = TextAlignment.reconcile(original: words, correctedText: text)
        correctionProposal = nil
    }
    public mutating func restoreOriginal() { corrected = nil; correctedWords = nil; correctionProposal = nil }
}

public struct AudioChunk: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var start: Double
    public var duration: Double
    public var sampleRate: Double
    public var wallStart: Date
    public var closed: Bool
    public var recovered: Bool
    public var end: Double { start + duration }
    public init(id: UUID = UUID(), filename: String, start: Double, duration: Double = 0,
                sampleRate: Double, wallStart: Date = Date(), closed: Bool = false,
                recovered: Bool = false) {
        self.id = id; self.filename = filename; self.start = start; self.duration = duration
        self.sampleRate = sampleRate; self.wallStart = wallStart; self.closed = closed; self.recovered = recovered
    }
}

public struct TimeBookmark: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var time: Double
    public init(title: String, time: Double) { self.title = title; self.time = max(0, time) }
}
public struct StrokeAnchor: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var time: Double?
    public var duration: Double
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(id: String, time: Double?, duration: Double, x: Double, y: Double, width: Double, height: Double) {
        self.id = id; self.time = time; self.duration = duration
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public enum PaperStyle: String, CaseIterable, Codable, Sendable { case blank, ruled, grid }
public struct NotebookPage: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var style: PaperStyle = .grid
    public var drawingFile: String
    public var strokes: [StrokeAnchor] = []
    public var text = ""
    public var ocr = ""
    public var imageFile: String?
    public var imageTime: Double?
    public init() { drawingFile = "page-\(id.uuidString).drawing" }
}
public struct PageAnchor: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var page: Int
    public var time: Double
    public var confirmed: Bool
    public var source: String
    public init(page: Int, time: Double, confirmed: Bool, source: String) {
        self.page = page; self.time = time; self.confirmed = confirmed; self.source = source
    }
}
public struct LinkedDocument: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var filename: String
    public var sha256: String
    public var pageCount: Int
    public var revision: Int = 1
    public var importedAt = Date()
    public var anchors: [PageAnchor] = []
    public init(title: String, filename: String, sha256: String, pageCount: Int) {
        self.title = title; self.filename = filename; self.sha256 = sha256; self.pageCount = pageCount
    }
    public mutating func replace(filename: String, sha256: String, pageCount: Int) {
        guard self.sha256 != sha256 else { return }
        self.filename = filename; self.sha256 = sha256; self.pageCount = pageCount
        self.revision += 1; self.importedAt = Date()
        // Page identity cannot be inferred after reorder/insertion. Require review even at the same index.
        anchors = anchors.filter { $0.page < pageCount }.map { anchor in
            var a = anchor; a.confirmed = false; a.source = "Da riconfermare dopo aggiornamento PDF"; return a
        }
    }
}
public struct Flashcard: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var question: String
    public var answer: String
    public var segmentID: UUID
    public var time: Double
    public var level = 0
    public var due = Date()
    public init(question: String, answer: String, segmentID: UUID, time: Double) {
        self.question = question; self.answer = answer; self.segmentID = segmentID; self.time = time
    }
    public mutating func review(remembered: Bool, now: Date = Date()) {
        level = remembered ? min(level + 1, 6) : 0
        let days = [0.01, 1.0, 3, 7, 14, 30, 60][level]
        due = now.addingTimeInterval(days * 86_400)
    }
}
public struct SourceReference: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { segmentID }
    public var lectureID: UUID
    public var lectureTitle: String
    public var segmentID: UUID
    public var time: Double
    public init(lecture: Lecture, segment: TranscriptSegment) {
        lectureID = lecture.id; lectureTitle = lecture.title; segmentID = segment.id; time = segment.start
    }
}
public struct StudyArtifact: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var text: String
    public var segmentIDs: [UUID]
    public var generated: Bool
    public var references: [SourceReference] = []
    public var createdAt = Date()
    public init(title: String, text: String, segmentIDs: [UUID], generated: Bool, references: [SourceReference] = []) {
        self.title = title; self.text = text; self.segmentIDs = segmentIDs; self.generated = generated
        self.references = references
    }
}
public struct Lecture: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var schemaVersion = 1
    public var title: String
    public var subject: String
    public var date = Date()
    public var favorite = false
    public var tags: [String] = []
    public var chunks: [AudioChunk] = []
    public var bookmarks: [TimeBookmark] = []
    public var pages: [NotebookPage] = [NotebookPage()]
    public var documents: [LinkedDocument] = []
    public var cards: [Flashcard] = []
    public var artifacts: [StudyArtifact] = []
    public var wasRecording = false
    public var duration: Double { chunks.map(\.end).max() ?? 0 }
    public init(title: String, subject: String) { self.title = title; self.subject = subject }
}
