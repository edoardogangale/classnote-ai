import AVFoundation
import Combine
import ClassNoteCore

/// The tap only copies a bounded buffer. Disk I/O and ASR run on a separate serial queue.
final class AudioChunkWriter: @unchecked Sendable {
    let queue = DispatchQueue(label:"classnote.audio.writer",qos:.userInitiated)
    private let capacity = DispatchSemaphore(value:96)
    private let store: LectureStore
    private let lectureID: UUID
    private var file: AVAudioFile?
    private var chunk: AudioChunk?
    private var frames: AVAudioFramePosition = 0
    private var cursor: Double
    private var lastCheckpoint = 0.0
    private var failed = false
    private let snapshotLock = NSLock()
    private var latest: AudioChunk?
    private var lastClosed: AudioChunk?
    var snapshot: AudioChunk? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return latest }
    var onOpen: ((AudioChunk) -> Void)?
    var onBuffer: ((UUID, AVAudioPCMBuffer) -> Void)?
    var onUpdate: ((AudioChunk) -> Void)?
    var onClose: ((AudioChunk) -> Void)?
    var onError: ((Error) -> Void)?

    init(store: LectureStore, lectureID: UUID, offset: Double) {
        self.store = store; self.lectureID = lectureID; self.cursor = offset
    }
    func submit(_ buffer: AVAudioPCMBuffer, capturedAt: Date) {
        guard capacity.wait(timeout:.now()) == .success else {
            queue.async { self.fail(ClassNoteError.message("Scrittura audio in ritardo. Registrazione fermata per evitare perdite silenziose.")) }
            return
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat:buffer.format,frameCapacity:buffer.frameLength) else {
            capacity.signal()
            queue.async { self.fail(ClassNoteError.message("Memoria insufficiente per acquisire l’audio.")) }; return
        }
        copy.frameLength = buffer.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:buffer.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(src.count,dst.count) {
            if let a = src[index].mData, let b = dst[index].mData { memcpy(b,a,Int(src[index].mDataByteSize)) }
        }
        queue.async {
            defer { self.capacity.signal() }
            guard !self.failed else { return }
            do { try self.write(copy,capturedAt:capturedAt) } catch { self.fail(error) }
        }
    }
    private func write(_ buffer: AVAudioPCMBuffer, capturedAt: Date) throws {
        if file == nil {
            let directory = try store.mediaDirectory(lectureID)
            let attrs = try FileManager.default.attributesOfFileSystem(forPath:directory.path)
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            guard free > 200 * 1024 * 1024 else { throw ClassNoteError.message("Meno di 200 MB liberi: libera spazio prima di registrare.") }
            let id = UUID()
            let next = AudioChunk(id:id,filename:"audio-\(id.uuidString).caf",start:cursor,
                                  sampleRate:buffer.format.sampleRate,wallStart:capturedAt)
            chunk = next; frames = 0; lastCheckpoint = 0
            try checkpoint(next) // Write-ahead metadata; the file may still be open at a crash.
            let settings: [String:Any] = [AVFormatIDKey:kAudioFormatLinearPCM,
                AVSampleRateKey:buffer.format.sampleRate,AVNumberOfChannelsKey:buffer.format.channelCount,
                AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false,
                AVLinearPCMIsNonInterleaved:false]
            file = try AVAudioFile(forWriting:store.media(lectureID,next.filename),settings:settings,
                                  commonFormat:buffer.format.commonFormat,interleaved:buffer.format.isInterleaved)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],
                                                 ofItemAtPath:store.media(lectureID,next.filename).path)
            onOpen?(next)
        }
        guard var c = chunk, file != nil else { return }
        try file?.write(from:buffer); frames += AVAudioFramePosition(buffer.frameLength)
        c.duration = Double(frames) / c.sampleRate; chunk = c
        snapshotLock.lock(); latest = c; snapshotLock.unlock()
        onBuffer?(c.id,buffer)
        if c.duration - lastCheckpoint >= 1 {
            try checkpoint(c); onUpdate?(c); lastCheckpoint = c.duration
        }
        if c.duration >= 12 { try close() }
    }
    private func checkpoint(_ c: AudioChunk) throws {
        try store.write(JSONEncoder().encode(c),lecture:lectureID,name:"\(c.id.uuidString).chunkmeta")
    }
    private func close() throws {
        guard var c = chunk else { return }
        file = nil // Finalize before consumers open this CAF.
        c.closed = true; lastClosed = c
        snapshotLock.lock(); latest = c; snapshotLock.unlock()
        cursor = c.end; chunk = nil
        defer { onUpdate?(c); onClose?(c) }
        try checkpoint(c)
    }
    private func fail(_ error: Error) {
        guard !failed else { return }; failed = true
        try? close(); onError?(error)
    }
    func finish() async -> AudioChunk? {
        await withCheckedContinuation { continuation in
            queue.async { do { try self.close() } catch { self.onError?(error) }; continuation.resume(returning:self.lastClosed) }
        }
    }
}

@MainActor final class AudioCapture: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var paused = false
    @Published private(set) var duration = 0.0
    @Published private(set) var levels: [Float] = Array(repeating:0,count:60)
    @Published private(set) var voiceActive = false
    var onChunk: ((UUID,AudioChunk) -> Void)?
    var onClosed: ((UUID,AudioChunk) -> Void)?
    var onFailure: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var writer: AudioChunkWriter?
    private var lectureID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var meterTick = 0
    var speech: AppleSpeechTranscriber?
    var noiseReduction = false
    var latestChunk: AudioChunk? { writer?.snapshot }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            let kind = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            guard kind == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                await self?.pause(); self?.onFailure?("Registrazione in pausa per un’interruzione audio. Riprendi quando puoi.")
            }
        })
        for name in [AVAudioSession.routeChangeNotification,AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                if name == AVAudioSession.routeChangeNotification {
                    let raw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
                    guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ||
                          raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
                }
                Task { @MainActor [weak self] in
                    guard self?.recording == true else { return }
                    await self?.pause(); self?.onFailure?("Dispositivo audio cambiato: verifica il microfono e riprendi.")
                }
            })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning:$0) }
        }
    }
    func start(store: LectureStore, lectureID: UUID, offset: Double) throws {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,mode:noiseReduction ? .voiceChat : .default,options:[.defaultToSpeaker,.allowBluetooth])
        try session.setActive(true)
        let engine = AVAudioEngine()
        if noiseReduction { try engine.inputNode.setVoiceProcessingEnabled(true) }
        let format = engine.inputNode.outputFormat(forBus:0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ClassNoteError.message("Microfono non disponibile.") }
        let writer = AudioChunkWriter(store:store,lectureID:lectureID,offset:offset)
        let speech = self.speech
        writer.onOpen = { speech?.open($0) }
        writer.onBuffer = { speech?.append($1,chunkID:$0) }
        writer.onClose = { [weak self] chunk in
            speech?.finish(chunkID:chunk.id)
            Task { @MainActor in self?.onClosed?(lectureID,chunk) }
        }
        writer.onUpdate = { [weak self] chunk in
            Task { @MainActor in self?.duration = chunk.end; self?.onChunk?(lectureID,chunk) }
        }
        writer.onError = { [weak self] error in
            Task { @MainActor in await self?.pause(); self?.onFailure?(error.localizedDescription) }
        }
        var lastMeter = Date.distantPast
        engine.inputNode.installTap(onBus:0,bufferSize:2048,format:format) { [weak self, writer] buffer, _ in
            let now = Date()
            writer.submit(buffer,capturedAt:now.addingTimeInterval(-Double(buffer.frameLength)/buffer.format.sampleRate))
            if now.timeIntervalSince(lastMeter) > 0.08 {
                lastMeter = now
                var rms: Float = 0
                if let data = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    for i in 0..<Int(buffer.frameLength) { rms += data[i] * data[i] }
                    rms = sqrt(rms / Float(buffer.frameLength))
                }
                let amplitude = min(1,max(0,rms * 8))
                Task { @MainActor in
                    guard let self else { return }
                    self.levels.removeFirst(); self.levels.append(amplitude); self.voiceActive = rms > 0.012
                }
            }
        }
        engine.prepare()
        do { try engine.start() } catch { engine.inputNode.removeTap(onBus:0); throw error }
        self.engine = engine; self.writer = writer; self.lectureID = lectureID
        duration = offset; recording = true; paused = false
    }
    func pause() async {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus:0); engine.stop(); self.engine = nil
        let writer = self.writer; self.writer = nil
        if let final = await writer?.finish(), let lectureID { duration = final.end; onChunk?(lectureID,final) }
        recording = false; paused = true; voiceActive = false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func stop() async {
        await pause(); paused = false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
}
