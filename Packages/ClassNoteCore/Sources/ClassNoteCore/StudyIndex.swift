import Foundation

public struct SearchHit: Identifiable, Sendable {
    public var id: UUID { segment.id }
    public var lectureID: UUID
    public var lectureTitle: String
    public var segment: TranscriptSegment
    public var score: Double
    public init(lectureID: UUID, lectureTitle: String, segment: TranscriptSegment, score: Double) {
        self.lectureID = lectureID; self.lectureTitle = lectureTitle; self.segment = segment; self.score = score
    }
}
public enum StudyIndex {
    static let stop = Set("il lo la i gli le un una uno e o di da del della dei delle che a al alla in con per si non è sono come cosa ha hai mi nel nella the a an of to and is what".split(separator: " ").map(String.init))
    public static func terms(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 && !stop.contains($0) }
    }
    public static func search(_ query: String, corpus: [(Lecture, [TranscriptSegment])], limit: Int = 12) -> [SearchHit] {
        let q = Set(terms(query)); guard !q.isEmpty else { return [] }
        let docs = corpus.flatMap { lecture, segments in segments.map { (lecture, $0, terms($0.displayText)) } }
        guard !docs.isEmpty else { return [] }
        let average = Double(docs.map { $0.2.count }.reduce(0,+)) / Double(docs.count)
        var df: [String:Int] = [:]
        for doc in docs { for token in Set(doc.2) { df[token, default: 0] += 1 } }
        return docs.compactMap { lecture, segment, tokens in
            var score = 0.0
            for token in q {
                let count = Double(tokens.filter { $0 == token }.count)
                guard count > 0 else { continue }
                let n = Double(df[token] ?? 0)
                let idf = log(1 + (Double(docs.count) - n + 0.5) / (n + 0.5))
                score += idf * count * 2.2 / (count + 1.2 * (0.25 + 0.75 * Double(tokens.count) / max(1, average)))
            }
            guard score > 0 else { return nil }
            return SearchHit(lectureID: lecture.id, lectureTitle: lecture.title, segment: segment, score: score)
        }.sorted { $0.score == $1.score ? $0.segment.start < $1.segment.start : $0.score > $1.score }.prefix(max(0, limit)).map { $0 }
    }
    public static func extractiveSummary(_ segments: [TranscriptSegment], count: Int = 8) -> [TranscriptSegment] {
        let available = segments.filter { !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var frequencies: [String:Int] = [:]
        for s in available { for t in Set(terms(s.displayText)) { frequencies[t, default:0] += 1 } }
        return available.sorted { left, right in
            func score(_ s: TranscriptSegment) -> Double {
                let t = terms(s.displayText)
                return t.map { Double(frequencies[$0, default: 0]) }.reduce(0,+) / sqrt(Double(max(1,t.count)))
            }
            return score(left) > score(right)
        }.prefix(max(0,count)).sorted { $0.start < $1.start }
    }
    public static func flashcards(_ segments: [TranscriptSegment]) -> [Flashcard] {
        // The answer remains an exact excerpt; no invented textbook definitions.
        extractiveSummary(segments, count: 12).map { s in
            let topic = terms(s.displayText).prefix(3).joined(separator: ", ")
            return Flashcard(question: "Spiega il passaggio su: \(topic)", answer: s.displayText, segmentID: s.id, time: s.start)
        }
    }
    public static func chapters(_ segments: [TranscriptSegment]) -> [TimeBookmark] {
        var result: [TimeBookmark] = []; var previous: Set<String> = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let current = Set(terms(segment.displayText))
            let union = previous.union(current).count
            let similarity = union == 0 ? 1 : Double(previous.intersection(current).count) / Double(union)
            if result.isEmpty || (segment.start - (result.last?.time ?? 0) >= 180 && similarity < 0.12) {
                result.append(TimeBookmark(title: terms(segment.displayText).prefix(5).joined(separator: " · "), time: segment.start))
            }
            previous = current
        }
        return result
    }
}
