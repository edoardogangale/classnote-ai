import Foundation

public enum Timeline {
    public static func chunk(at time: Double, in chunks: [AudioChunk]) -> AudioChunk? {
        guard time.isFinite, time >= 0 else { return nil }
        let sorted = chunks.sorted { $0.start < $1.start }
        return sorted.first { $0.start <= time && time < $0.end }
            ?? sorted.last.flatMap { abs($0.end - time) < 0.001 ? $0 : nil }
    }
    public static func recordingTime(for date: Date, chunks: [AudioChunk]) -> Double? {
        // Never assign a timestamp to ink made during pause or before the recording.
        for c in chunks.reversed() {
            let delta = date.timeIntervalSince(c.wallStart)
            if delta >= 0 && delta <= c.duration { return c.start + delta }
        }
        return nil
    }
    public static func format(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    public static func deepLink(lecture: UUID, time: Double) -> URL {
        var c = URLComponents()
        c.scheme = "classnote"; c.host = "lecture"; c.path = "/" + lecture.uuidString
        c.queryItems = [URLQueryItem(name: "t", value: String(max(0, time.isFinite ? time : 0)))]
        return c.url!
    }
    public static func parse(_ url: URL) -> (UUID, Double)? {
        guard url.scheme == "classnote", url.host == "lecture",
              let id = UUID(uuidString: url.lastPathComponent),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value,
              let time = Double(raw), time.isFinite, time >= 0 else { return nil }
        return (id, time)
    }
}

public enum TextAlignment {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    public static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    public static func reconcile(original: [TimedWord], correctedText: String) -> [TimedWord] {
        let newTokens = tokenize(correctedText)
        // Bound the dynamic programming matrix. An edited segment is normally under 45 seconds.
        guard original.count < 600, newTokens.count < 600 else {
            return newTokens.map { TimedWord(text: $0, start: nil, end: nil, state: .confirmed, alignment: .needsReview) }
        }
        let oldKeys = original.map { normalize($0.text) }; let newKeys = newTokens.map(normalize)
        var dp = Array(repeating: Array(repeating: 0, count: newTokens.count + 1), count: original.count + 1)
        if !original.isEmpty && !newTokens.isEmpty {
            for i in stride(from: original.count - 1, through: 0, by: -1) {
                for j in stride(from: newTokens.count - 1, through: 0, by: -1) {
                    dp[i][j] = oldKeys[i] == newKeys[j] && !newKeys[j].isEmpty ? 1 + dp[i+1][j+1] : max(dp[i+1][j], dp[i][j+1])
                }
            }
        }
        var matches: [Int: Int] = [:]; var i = 0; var j = 0
        while i < original.count && j < newTokens.count {
            if oldKeys[i] == newKeys[j] && !newKeys[j].isEmpty { matches[j] = i; i += 1; j += 1 }
            else if dp[i+1][j] >= dp[i][j+1] { i += 1 } else { j += 1 }
        }
        return newTokens.enumerated().map { index, token in
            if let old = matches[index] {
                var word = original[old]; word.text = token; word.alignment = .retained; return word
            }
            return TimedWord(text: token, start: nil, end: nil, state: .confirmed, alignment: .needsReview)
        }
    }
    public static func preserveIDs(previous: [TimedWord], next: [TimedWord]) -> [TimedWord] {
        // Revisions keep IDs only for an unchanged prefix at the same acoustic location.
        next.enumerated().map { index, word in
            var w = word
            if index < previous.count, normalize(previous[index].text) == normalize(word.text),
               abs((previous[index].start ?? -100) - (word.start ?? 100)) < 0.3 { w.id = previous[index].id }
            return w
        }
    }
}
