import AVFoundation
import Combine
import ClassNoteCore

@MainActor final class LecturePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published var time: Double = 0
    @Published var rate: Float = 1 { didSet { player?.rate = rate } }
    @Published var loopStart: Double?
    @Published var loopEnd: Double?
    var onError: ((String) -> Void)?
    private var player: AVAudioPlayer?
    private var chunk: AudioChunk?
    private var chunks: [AudioChunk] = []
    private var timer: Timer?
    private var directory: URL?
    override init() {
        super.init()
        timer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    deinit { timer?.invalidate() }
    func configure(chunks: [AudioChunk], directory: URL) {
        self.chunks = chunks.filter { $0.closed && $0.duration > 0 }.sorted { $0.start < $1.start }
        self.directory = directory
    }
    func seek(_ value: Double, play: Bool = true) {
        let safe = max(0,min(value,chunks.last?.end ?? 0))
        guard let c = Timeline.chunk(at:safe,in:chunks), let directory else { return }
        do {
            if chunk?.id != c.id || player == nil {
                player?.stop()
                try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(contentsOf:directory.appendingPathComponent(c.filename))
                p.delegate = self; p.enableRate = true; p.rate = rate; p.prepareToPlay()
                player = p; chunk = c
            }
            player?.currentTime = min(c.duration,max(0,safe-c.start)); time = safe
            if play { playing = player?.play() == true } else { player?.pause(); playing = false }
        } catch { playing = false; onError?(error.localizedDescription) }
    }
    func toggle() { playing ? pause() : seek(time) }
    func pause() { player?.pause(); playing = false }
    func reset() { pause(); player = nil; chunk = nil; time = 0; loopStart = nil; loopEnd = nil }
    private func tick() {
        guard playing, let chunk, let player else { return }
        time = chunk.start + player.currentTime
        if let a = loopStart, let b = loopEnd, b > a, time >= b { seek(a) }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, let c = self.chunk else { return }
            if let a = self.loopStart, let b = self.loopEnd, b <= c.end, b > a { self.seek(a); return }
            if let next = self.chunks.first(where: { $0.start >= c.end - 0.001 && $0.id != c.id }) { self.seek(next.start) }
            else { self.time = c.end; self.playing = false }
        }
    }
}

enum AudioExporter {
    static func export(chunks: [AudioChunk], directory: URL, range: ClosedRange<Double>?, destination: URL) async throws -> URL {
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else {
            throw ClassNoteError.message("Impossibile creare la clip.")
        }
        let lower = range?.lowerBound ?? 0
        let upper = range?.upperBound ?? (chunks.map(\.end).max() ?? 0)
        guard lower.isFinite, upper.isFinite, upper > lower else { throw ClassNoteError.message("Intervallo audio non valido.") }
        var insertion = CMTime.zero
        for chunk in chunks.sorted(by:{$0.start < $1.start}) where chunk.closed {
            let from = max(lower,chunk.start), to = min(upper,chunk.end)
            guard to > from else { continue }
            let asset = AVURLAsset(url:directory.appendingPathComponent(chunk.filename))
            guard let source = try await asset.loadTracks(withMediaType:.audio).first else { continue }
            let duration = CMTime(seconds:to-from,preferredTimescale:48_000)
            try target.insertTimeRange(CMTimeRange(start:CMTime(seconds:from-chunk.start,preferredTimescale:48_000),duration:duration),of:source,at:insertion)
            insertion = CMTimeAdd(insertion,duration)
        }
        guard insertion > .zero, let exporter = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetAppleM4A) else {
            throw ClassNoteError.message("Nessun audio disponibile nell’intervallo.")
        }
        exporter.outputURL = destination; exporter.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            exporter.exportAsynchronously {
                if exporter.status == .completed { continuation.resume() }
                else { continuation.resume(throwing:exporter.error ?? ClassNoteError.message("Esportazione audio interrotta.")) }
            }
        }
        return destination
    }
}
