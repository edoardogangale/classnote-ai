import Speech
import AVFoundation
import ClassNoteCore

/// Each recognition request consumes exactly one persisted chunk, so offsets never depend on wall-clock timers.
final class AppleSpeechTranscriber: @unchecked Sendable {
    private let queue = DispatchQueue(label:"classnote.speech")
    private let recognizer: SFSpeechRecognizer?
    private var requests: [UUID:SFSpeechAudioBufferRecognitionRequest] = [:]
    private var tasks: [UUID:SFSpeechRecognitionTask] = [:]
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((String) -> Void)?
    let glossary: [String]
    init(locale: String, glossary: [String]) {
        recognizer = SFSpeechRecognizer(locale:Locale(identifier:locale)); self.glossary = glossary
    }
    var availableOffline: Bool { recognizer?.supportsOnDeviceRecognition == true && recognizer?.isAvailable == true }
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0 == .authorized) }
        }
    }
    func open(_ chunk: AudioChunk) {
        queue.async {
            guard let recognizer = self.recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
                self.onError?("Trascrizione Apple offline non disponibile per questa lingua/dispositivo. L’audio continua a essere salvato."); return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true; request.addsPunctuation = true
            request.contextualStrings = Array(self.glossary.prefix(100))
            self.requests[chunk.id] = request
            self.tasks[chunk.id] = recognizer.recognitionTask(with:request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let words = result.bestTranscription.segments.map { s in
                        TimedWord(text:s.substring,start:chunk.start + s.timestamp,
                                  end:chunk.start + s.timestamp + s.duration,chunkID:chunk.id,
                                  confidence:result.isFinal ? s.confidence : nil,
                                  state:result.isFinal ? .confirmed : .provisional)
                    }
                    let segment = TranscriptSegment(id:chunk.id,source:"Apple Speech · locale · \(recognizer.locale.identifier)",
                        original:result.bestTranscription.formattedString,words:words,start:words.first?.start ?? chunk.start,
                        end:words.last?.end ?? chunk.start,finalized:result.isFinal)
                    self.onSegment?(segment)
                }
                if error != nil || result?.isFinal == true {
                    self.queue.async {
                        self.requests.removeValue(forKey:chunk.id); self.tasks.removeValue(forKey:chunk.id)
                    }
                    if let error { self.onError?("Trascrizione interrotta: \(error.localizedDescription). Il file audio è conservato.") }
                }
            }
        }
    }
    func append(_ buffer: AVAudioPCMBuffer, chunkID: UUID) {
        // A strong buffer reference keeps the writer's copied PCM alive until appended.
        queue.async { self.requests[chunkID]?.append(buffer) }
    }
    func finish(chunkID: UUID) {
        queue.async {
            self.requests[chunkID]?.endAudio()
            // Do not cancel immediately: final results often arrive after endAudio.
            self.queue.asyncAfter(deadline:.now()+8) {
                self.tasks.removeValue(forKey:chunkID)?.cancel(); self.requests.removeValue(forKey:chunkID)
            }
        }
    }
}
