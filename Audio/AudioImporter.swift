import AVFoundation
import ClassNoteCore

enum AudioImporter {
    static func run(url: URL, lecture: Lecture, store: LectureStore) async throws -> Lecture {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority:.userInitiated) {
            var result = lecture
            let input = try AVAudioFile(forReading:url)
            let format = input.processingFormat
            guard format.sampleRate > 0 else { throw ClassNoteError.message("Formato audio non supportato.") }
            let framesPerChunk = AVAudioFrameCount(min(Double(UInt32.max),format.sampleRate*12))
            guard let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:framesPerChunk) else {
                throw ClassNoteError.message("Memoria insufficiente per l’importazione.")
            }
            var offset = lecture.duration
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into:buffer,frameCount:framesPerChunk)
                guard buffer.frameLength > 0 else { break }
                let directory = try store.mediaDirectory(lecture.id)
                let attrs = try FileManager.default.attributesOfFileSystem(forPath:directory.path)
                guard ((attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) > 200*1024*1024 else {
                    throw ClassNoteError.message("Spazio insufficiente. I blocchi già importati sono recuperabili.")
                }
                let id = UUID()
                let chunk = AudioChunk(id:id,filename:"audio-\(id.uuidString).caf",start:offset,
                    duration:Double(buffer.frameLength)/format.sampleRate,sampleRate:format.sampleRate,
                    wallStart:.distantPast,closed:true)
                do {
                    let output = try AVAudioFile(forWriting:store.media(lecture.id,chunk.filename),settings:format.settings,
                        commonFormat:format.commonFormat,interleaved:format.isInterleaved)
                    try output.write(from:buffer)
                }
                try store.write(JSONEncoder().encode(chunk),lecture:lecture.id,name:"\(id.uuidString).chunkmeta")
                result.chunks.append(chunk); offset = chunk.end
                try store.save(result)
            }
            return result
        }.value
    }
}
