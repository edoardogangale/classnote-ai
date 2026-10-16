import Foundation
import Combine
import ClassNoteCore
#if canImport(WhisperKit)
import WhisperKit
import CoreML
#endif

@MainActor final class WhisperTranscriber: ObservableObject {
    @Published private(set) var status = "Modello non caricato"
    @Published private(set) var progress = 0.0
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    private let directory: URL
    #if canImport(WhisperKit)
    private var pipeline: WhisperKit?
    #endif
    init(directory: URL) { self.directory = directory }
    static var included: Bool {
        #if canImport(WhisperKit)
        true
        #else
        false
        #endif
    }
    func clearModel() {
        guard !busy else { return }; ready = false; status = "Modello non caricato"; progress = 0
        #if canImport(WhisperKit)
        pipeline = nil
        #endif
    }
    func prepare(model: String, allowDownload: Bool) async throws {
        guard !busy else { throw ClassNoteError.message("Un’elaborazione Whisper è già in corso.") }
        busy = true; ready = false; defer { busy = false }
        #if canImport(WhisperKit)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let key = "whisper.local.\(model)"
        let tokenizerBase = directory.appendingPathComponent("Tokenizers")
        if !allowDownload {
            let files = FileManager.default.enumerator(at:tokenizerBase,includingPropertiesForKeys:nil)?.allObjects as? [URL] ?? []
            guard UserDefaults.standard.bool(forKey:"whisper.complete.\(model)"),
                  files.contains(where:{$0.lastPathComponent == "tokenizer.json"}),
                  files.contains(where:{$0.lastPathComponent == "tokenizer_config.json"}) else {
                throw ClassNoteError.message("Completa prima il download del modello e del tokenizer dalle Impostazioni.")
            }
        }
        let saved = UserDefaults.standard.string(forKey:key)
        let folder: URL
        if let saved, FileManager.default.fileExists(atPath:saved) { folder = URL(fileURLWithPath:saved) }
        else {
            guard allowDownload else { throw ClassNoteError.message("Scarica prima il modello da Impostazioni, oppure usa Apple offline.") }
            status = "Download modello \(model)…"; progress = 0
            folder = try await WhisperKit.download(variant:model,downloadBase:directory,from:"argmaxinc/whisperkit-coreml",progressCallback:{ p in
                let fraction = p.fractionCompleted
                Task { @MainActor [weak self] in self?.progress = fraction }
            })
            UserDefaults.standard.set(folder.path,forKey:key)
        }
        status = "Preparazione Core ML…"
        let compute = ModelComputeOptions(melCompute:.cpuOnly,audioEncoderCompute:.cpuAndNeuralEngine,
                                          textDecoderCompute:.cpuAndNeuralEngine,prefillCompute:.cpuOnly)
        pipeline = try await WhisperKit(WhisperKitConfig(modelFolder:folder.path,tokenizerFolder:tokenizerBase,computeOptions:compute,
                                                        verbose:false,prewarm:true,load:true,download:false))
        UserDefaults.standard.set(true,forKey:"whisper.complete.\(model)")
        ready = true; status = "\(model) · locale · pronto"; progress = 1
        #else
        throw ClassNoteError.message("Whisper non è incluso in questa edizione. Seleziona Apple offline nelle impostazioni.")
        #endif
    }
    func transcribe(chunk: AudioChunk, audio: URL, language: String) async throws -> TranscriptSegment {
        guard !busy else { throw ClassNoteError.message("Whisper occupato. Il segmento audio resta disponibile per la trascrizione successiva.") }
        busy = true; defer { busy = false }
        #if canImport(WhisperKit)
        guard let pipeline else { throw ClassNoteError.message("Modello Whisper non caricato.") }
        try Task.checkCancellation()
        let options = DecodingOptions(language:language == "auto" ? nil : language,
                                      temperature:0,temperatureFallbackCount:0,
                                      detectLanguage:language == "auto",skipSpecialTokens:true,
                                      withoutTimestamps:false,wordTimestamps:true,
                                      concurrentWorkerCount:1)
        let results: [TranscriptionResult] = try await pipeline.transcribe(audioPath:audio.path,decodeOptions:options)
        try Task.checkCancellation()
        let utterances = results.flatMap(\.segments).filter { $0.noSpeechProb < 0.8 }
        let words: [TimedWord] = utterances.flatMap { s in
            (s.words ?? []).compactMap { word in
                let from = max(0,Double(word.start)); let to = min(chunk.duration,Double(word.end))
                guard to >= from, from <= chunk.duration else { return nil }
                return TimedWord(text:word.word.trimmingCharacters(in:.whitespacesAndNewlines),
                    start:chunk.start+from,end:chunk.start+to,chunkID:chunk.id,confidence:word.probability,state:.confirmed)
            }
        }
        let text = utterances.map(\.text).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        return TranscriptSegment(id:chunk.id,source:"WhisperKit · locale",original:text,words:words,
                                 start:words.first?.start ?? chunk.start,end:words.last?.end ?? chunk.end,finalized:true)
        #else
        throw ClassNoteError.message("WhisperKit non incluso in questo schema.")
        #endif
    }
}
