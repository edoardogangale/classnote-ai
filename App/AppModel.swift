import SwiftUI
import AVFoundation
import PDFKit
import UniformTypeIdentifiers
import ClassNoteCore

enum SpeechEngine: String, CaseIterable { case apple = "Apple offline", whisper = "Whisper locale" }
struct SharePayload: Identifiable { let id = UUID(); var items: [Any] }
struct FileExportPayload: Identifiable { let id = UUID(); var urls: [URL] }

@MainActor final class AppModel: ObservableObject {
    let store: LectureStore
    let capture = AudioCapture()
    let player = LecturePlayer()
    let whisper: WhisperTranscriber
    @Published var lectures: [Lecture] = []
    @Published var current: Lecture?
    @Published var segments: [TranscriptSegment] = []
    @Published var message: String?
    @Published var error: String?
    @Published var processing = false
    @Published var progressText = ""
    @Published var share: SharePayload?
    @Published var files: FileExportPayload?
    @Published var pendingCount = 0
    @Published var engine: SpeechEngine {
        didSet {
            UserDefaults.standard.set(engine.rawValue,forKey:"engine")
            if engine == .apple && locale == "auto" { locale = "it-IT" }
        }
    }
    @Published var locale: String { didSet { UserDefaults.standard.set(locale,forKey:"locale") } }
    @Published var glossary: String { didSet { UserDefaults.standard.set(glossary,forKey:"glossary") } }
    @Published var modelName: String { didSet { UserDefaults.standard.set(modelName,forKey:"modelName") } }
    @Published var consent = false
    var foreground = true {
        didSet {
            if foreground { pumpWhisper() }
            else { whisperTask?.cancel() }
        }
    }
    private var recordingID: UUID?
    private var pending: [(UUID,AudioChunk)] = []
    private var whisperRunning = false
    private var whisperTask: Task<Void,Never>?
    private var toggleInProgress = false

    init(store: LectureStore? = nil) throws {
        self.store = try store ?? LectureStore()
        let savedEngine = SpeechEngine(rawValue:UserDefaults.standard.string(forKey:"engine") ?? "") ?? .apple
        let availableEngine: SpeechEngine = savedEngine == .whisper && !WhisperTranscriber.included ? .apple : savedEngine
        engine = availableEngine
        let savedLocale = UserDefaults.standard.string(forKey:"locale") ?? "it-IT"
        locale = availableEngine == .apple && savedLocale == "auto" ? "it-IT" : savedLocale
        glossary = UserDefaults.standard.string(forKey:"glossary") ?? "Kirchhoff\nBrønsted\nKant\nRothko\nWeierstrass"
        modelName = UserDefaults.standard.string(forKey:"modelName") ?? "openai_whisper-small"
        consent = UserDefaults.standard.bool(forKey:"recordingConsent")
        whisper = WhisperTranscriber(directory:self.store.root.appendingPathComponent("Models"))
        capture.onChunk = { [weak self] id,chunk in self?.updateChunk(chunk,lectureID:id) }
        capture.onClosed = { [weak self] id,chunk in self?.closedChunk(chunk,lectureID:id) }
        capture.onFailure = { [weak self] in self?.error = $0 }
        player.onError = { [weak self] in self?.error = $0 }
        try reload(recover:true)
    }
    func reload(recover: Bool = false) throws {
        var items = try store.list()
        if recover {
            for index in items.indices {
                do {
                    let wasRecording = items[index].wasRecording
                    items[index] = try store.recover(items[index])
                    if wasRecording {
                        message = "Registrazione interrotta recuperata. Controlla l’ultimo blocco audio."
                        for var s in try store.segments(items[index].id) where !s.finalized {
                            s.words = s.words.map { var w = $0; w.state = .interrupted; return w }
                            try store.save(s,lectureID:items[index].id)
                        }
                    }
                } catch { self.error = "Recupero di \(items[index].title): \(error.localizedDescription). I file originali sono conservati." }
            }
        }
        lectures = items
    }
    func create(title: String, subject: String) {
        guard !capture.recording && !capture.paused && !processing else { error = "Termina prima registrazioni ed elaborazioni."; return }
        do {
            let lecture = Lecture(title:title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Nuova lezione" : title,subject:subject)
            try store.save(lecture); try reload(); select(lecture.id)
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: UUID) {
        guard !capture.recording && !capture.paused && !processing else { if current?.id != id { error = "Termina registrazioni ed elaborazioni prima di cambiare lezione." }; return }
        do {
            guard let lecture = lectures.first(where:{$0.id == id}) else { return }
            player.reset(); current = lecture; segments = try store.segments(id); configurePlayer()
        } catch { self.error = error.localizedDescription }
    }
    func persist() {
        guard let current else { return }
        do {
            try store.save(current)
            if let i = lectures.firstIndex(where:{$0.id == current.id}) { lectures[i] = current }
        } catch { self.error = error.localizedDescription }
    }
    func rename(_ title: String, subject: String) { current?.title = title; current?.subject = subject; persist() }
    func favorite() { current?.favorite.toggle(); persist() }
    func delete(_ id: UUID) {
        guard !capture.recording && !capture.paused && !processing && pendingCount == 0 else { error = "Termina prima registrazioni e trascrizioni in coda."; return }
        do {
            pending.removeAll { $0.0 == id }; pendingCount = pending.count
            try store.delete(id)
            if current?.id == id { player.reset(); current = nil; segments = [] }
            try reload()
        } catch { self.error = error.localizedDescription }
    }
    func toggleRecording() async {
        guard !toggleInProgress, let id = current?.id else { return }
        toggleInProgress = true; defer { toggleInProgress = false }
        if capture.recording { await capture.pause(); current?.wasRecording = false; persist(); configurePlayer(); return }
        guard !processing else { error = "Attendi la fine dell’elaborazione prima di avviare la registrazione."; return }
        guard consent else { error = "Conferma prima le autorizzazioni alla registrazione nella schermata iniziale."; return }
        guard await AudioCapture.requestMicrophone() else { error = "Consenti il microfono nelle Impostazioni di iPadOS."; return }
        if engine == .whisper && !whisper.ready {
            do { try await whisper.prepare(model:modelName,allowDownload:false) }
            catch { self.error = error.localizedDescription; return }
        }
        player.pause()
        if engine == .apple {
            let authorized = await AppleSpeechTranscriber.requestPermission()
            let recognizer = AppleSpeechTranscriber(locale:locale,glossary:glossary.components(separatedBy:.newlines))
            if authorized && recognizer.availableOffline {
                recognizer.onSegment = { [weak self] segment in
                    Task { @MainActor in self?.receive(segment,lectureID:id) }
                }
                recognizer.onError = { [weak self] text in Task { @MainActor in self?.message = text } }
                capture.speech = recognizer
            } else {
                capture.speech = nil
                message = "Registro solo l’audio: riconoscimento Apple offline non disponibile o non autorizzato. Controlla il permesso di riconoscimento vocale e la lingua nelle Impostazioni."
                    + (WhisperTranscriber.included ? " Puoi anche preparare Whisper e trascrivere in seguito." : "")
            }
        } else { capture.speech = nil }
        do {
            recordingID = id
            current?.wasRecording = true; persist()
            try capture.start(store:store,lectureID:id,offset:current?.duration ?? 0)
        } catch { current?.wasRecording = false; persist(); self.error = error.localizedDescription }
    }
    func stopRecording() async {
        guard !toggleInProgress else { return }; toggleInProgress = true; defer { toggleInProgress = false }
        player.pause(); await capture.stop(); current?.wasRecording = false; persist(); configurePlayer()
    }
    func confirmConsent() { consent = true; UserDefaults.standard.set(true,forKey:"recordingConsent") }
    private func updateChunk(_ chunk: AudioChunk, lectureID: UUID) {
        guard current?.id == lectureID, lectureID == recordingID else { return }
        if let i = current?.chunks.firstIndex(where:{$0.id == chunk.id}) { current?.chunks[i] = chunk }
        else { current?.chunks.append(chunk) }
        persist()
    }
    private func closedChunk(_ chunk: AudioChunk, lectureID: UUID) {
        updateChunk(chunk,lectureID:lectureID)
        guard recordingID == lectureID else { return }
        if engine == .whisper { enqueue(lectureID,chunk) }
    }
    func receive(_ incoming: TranscriptSegment, lectureID: UUID) {
        do {
            var segment = incoming
            let existing = current?.id == lectureID ? segments.first(where:{$0.id == segment.id}) : try store.segments(lectureID).first(where:{$0.id == segment.id})
            if let existing {
                // Never replace a reviewed original with a second recognizer pass.
                if existing.source != incoming.source || existing.corrected != nil || existing.finalized {
                    if existing.original == incoming.original { return }
                    var proposal = existing; proposal.correctionProposal = incoming.original
                    try store.save(proposal,lectureID:lectureID)
                    if current?.id == lectureID, let i = segments.firstIndex(where:{$0.id == proposal.id}) { segments[i] = proposal }
                    return
                }
                if existing.finalized && !incoming.finalized { return }
                segment.words = TextAlignment.preserveIDs(previous:existing.words,next:incoming.words)
            }
            try store.save(segment,lectureID:lectureID)
            if current?.id == lectureID {
                if let i = segments.firstIndex(where:{$0.id == segment.id}) { segments[i] = segment }
                else { segments.append(segment); segments.sort { $0.start < $1.start } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func updateSegment(_ segment: TranscriptSegment) {
        guard let id = current?.id else { return }
        do {
            try store.save(segment,lectureID:id)
            if let i = segments.firstIndex(where:{$0.id == segment.id}) { segments[i] = segment }
        } catch { self.error = error.localizedDescription }
    }
    func seek(_ time: Double) async {
        if capture.recording { await capture.pause(); current?.wasRecording = false; persist() }
        configurePlayer(); player.seek(time)
    }
    func configurePlayer() {
        guard let current, let directory = try? store.mediaDirectory(current.id) else { return }
        player.configure(chunks:current.chunks,directory:directory)
    }
    func bookmark(title: String = "Punto importante") {
        current?.bookmarks.append(TimeBookmark(title:title,time:capture.recording ? capture.duration : player.time)); persist()
    }
    func saveDrawing(pageID: UUID, data: Data, strokes: [StrokeAnchor]) {
        guard let current, let index = current.pages.firstIndex(where:{$0.id == pageID}) else { return }
        do {
            try store.write(data,lecture:current.id,name:current.pages[index].drawingFile)
            self.current?.pages[index].strokes = strokes; persist()
        } catch { self.error = error.localizedDescription }
    }
    func updatePage(_ page: NotebookPage) {
        guard let i = current?.pages.firstIndex(where:{$0.id == page.id}) else { return }
        current?.pages[i] = page; persist()
    }
    func addPage() -> UUID? { let page = NotebookPage(); current?.pages.append(page); persist(); return page.id }
    func addImage(_ image: UIImage, duringImport: Bool = false) async {
        guard let id = current?.id else { return }
        guard !processing || duringImport else { error = "Attendi la fine dell’importazione prima di aggiungere immagini."; return }
        let time: Double? = capture.recording ? capture.duration : (player.playing ? player.time : nil)
        do {
            let filename = "image-\(UUID().uuidString).jpg"
            guard let data = image.jpegData(compressionQuality:0.9) else { return }
            try store.write(data,lecture:id,name:filename)
            var page = NotebookPage(); page.imageFile = filename; page.imageTime = time
            // Commit the photo before OCR, which may take longer or fail.
            current?.pages.append(page); persist()
            page.ocr = try await VisionTools.recognize(image)
            guard current?.id == id else { return }; updatePage(page)
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL, replacing: UUID? = nil) async {
        if url.hasDirectoryPath || url.pathExtension == "classnotepackage" { await restoreBackup(url); return }
        if current == nil, !processing, !url.hasDirectoryPath, url.pathExtension != "classnotepackage" {
            create(title:url.deletingPathExtension().lastPathComponent,subject:"Importazioni")
        }
        guard var lecture = current, !processing, !capture.recording, !capture.paused else { error = "Termina la registrazione prima di importare."; return }
        processing = true; progressText = "Importazione…"; defer { processing = false }
        do {
            if url.pathExtension.lowercased() == "pdf" {
                try DocumentBridge.importPDF(url:url,lecture:&lecture,replacing:replacing,store:store)
            } else if UTType(filenameExtension:url.pathExtension)?.conforms(to:.image) == true {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let image = UIImage(contentsOfFile:url.path) else { throw ClassNoteError.message("Immagine non leggibile.") }
                await addImage(image,duringImport:true); return
            } else { lecture = try await AudioImporter.run(url:url,lecture:lecture,store:store) }
            if current?.id == lecture.id { current = lecture; persist(); configurePlayer() }
            message = "Importazione completata. Per nuovi PDF Goodnotes conferma i collegamenti pagina-audio."
        } catch { self.error = error.localizedDescription }
    }
    func restoreBackup(_ url:URL) async {
        guard !processing, !capture.recording, !capture.paused else { error = "Termina registrazioni ed elaborazioni prima del ripristino."; return }
        processing = true; progressText = "Ripristino backup…"; defer { processing = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let restored = try await Task.detached(priority:.utility) { [store] in try store.restore(url) }.value
            try reload(); processing = false; select(restored.id); message = "Backup ripristinato."
        } catch { self.error = error.localizedDescription }
    }
    func updateDocument(_ document: LinkedDocument) {
        guard let index = current?.documents.firstIndex(where:{$0.id == document.id}) else { return }
        current?.documents[index] = document; persist()
    }
    func transcribeMissing(includeConfirmed: Bool = false) async {
        guard let current, !capture.recording, !capture.paused else { return }
        do {
            if !whisper.ready { try await whisper.prepare(model:modelName,allowDownload:false) }
            for c in current.chunks where c.closed {
                if includeConfirmed || !segments.contains(where:{$0.id == c.id && $0.finalized}) { enqueue(current.id,c) }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func enqueue(_ id:UUID,_ chunk:AudioChunk) {
        guard !pending.contains(where:{$0.0 == id && $0.1.id == chunk.id}) else { return }
        pending.append((id,chunk)); pendingCount = pending.count; pumpWhisper()
    }
    private func pumpWhisper() {
        guard foreground, !whisperRunning, !pending.isEmpty, whisper.ready else { return }
        whisperRunning = true
        whisperTask = Task {
            while foreground, !pending.isEmpty, !Task.isCancelled {
                let (id,chunk) = pending.removeFirst(); pendingCount = pending.count + 1
                do {
                    let language = locale == "auto" ? "auto" : locale.hasPrefix("en") ? "en" : "it"
                    let segment = try await whisper.transcribe(chunk:chunk,audio:store.media(id,chunk.filename),language:language)
                    receive(segment,lectureID:id)
                } catch is CancellationError {
                    pending.insert((id,chunk),at:0)
                } catch { self.message = error.localizedDescription }
            }
            pendingCount = pending.count; whisperRunning = false; whisperTask = nil
            if foreground { pumpWhisper() }
        }
    }
    func searchAll(_ query: String, semantic: Bool = false) -> [SearchHit] {
        do {
            let corpus = try lectures.map { ($0,try store.segments($0.id)) }
            let lexical = StudyIndex.search(query,corpus:corpus)
            guard semantic else { return lexical }
            let extra = corpus.flatMap { LocalStudyService.semanticSearch(query:query,lecture:$0.0,segments:$0.1) }
            return (lexical + extra.filter { hit in !lexical.contains(where:{$0.id == hit.id}) }).prefix(30).map { $0 }
        } catch { self.error = error.localizedDescription; return [] }
    }
    func generate(_ task: String, query: String? = nil) async {
        guard let lecture = current, !processing else { return }
        processing = true; progressText = task; defer { processing = false }
        do {
            let selected: [TranscriptSegment]
            var references: [SourceReference] = []
            if task.lowercased().contains("precedente") || task.lowercased().contains("confronta") {
                guard let previous = lectures.filter({$0.id != lecture.id && $0.subject == lecture.subject && $0.date < lecture.date}).max(by:{$0.date < $1.date}) else {
                    throw ClassNoteError.message("Non c’è una lezione precedente della stessa materia.")
                }
                let old = StudyIndex.extractiveSummary(try store.segments(previous.id),count:5)
                let recent = StudyIndex.extractiveSummary(segments,count:5)
                selected = recent + old
                references = recent.map { SourceReference(lecture:lecture,segment:$0) } + old.map { SourceReference(lecture:previous,segment:$0) }
            } else if let match = task.range(of:"(?:minuto|minuti|min)\\s+([0-9]+)",options:.regularExpression),
                      let minutes = Int(task[match].filter(\.isNumber)) {
                let second = Double(minutes)*60
                selected = segments.filter { $0.end >= max(0,second-30) && $0.start <= second+60 }
                references = selected.map { SourceReference(lecture:lecture,segment:$0) }
            } else if let query {
                let hits = searchAll(query,semantic:true)
                let scoped = task.lowercased().contains("tutte le lezioni") ? hits : hits.filter { $0.lectureID == lecture.id }
                selected = scoped.map(\.segment)
                references = scoped.compactMap { hit in lectures.first(where:{$0.id == hit.lectureID}).map { SourceReference(lecture:$0,segment:hit.segment) } }
            } else {
                selected = StudyIndex.extractiveSummary(segments,count:10)
                references = selected.map { SourceReference(lecture:lecture,segment:$0) }
            }
            let artifact = try await LocalStudyService.generate(task:task,segments:selected,references:references)
            guard current?.id == lecture.id else { return }; current?.artifacts.append(artifact); persist()
        } catch { self.error = error.localizedDescription }
    }
    func makeCards() {
        let known = Set(current?.cards.map(\.segmentID) ?? [])
        current?.cards.append(contentsOf:StudyIndex.flashcards(segments).filter { !known.contains($0.segmentID) }); persist()
    }
    func makeChapters() {
        let known = current?.bookmarks ?? []
        current?.bookmarks.append(contentsOf:StudyIndex.chapters(segments).filter { candidate in !known.contains(where:{abs($0.time-candidate.time)<1 && $0.title == candidate.title}) })
        persist()
    }
    func reviewCard(_ id:UUID,remembered:Bool) {
        guard let i = current?.cards.firstIndex(where:{$0.id == id}) else { return }
        current?.cards[i].review(remembered:remembered); persist()
    }
    func export(_ format: String) async {
        guard let lecture = current, !capture.recording, !capture.paused, !processing else { error = "Termina la registrazione prima di esportare."; return }
        processing = true; progressText = "Esportazione \(format)…"; defer { processing = false }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClassNote-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let name = "ClassNote_\(lecture.date.formatted(.iso8601.year().month().day()))"
            let output: URL
            switch format {
            case "PDF": output = try DocumentBridge.exportPDF(lecture:lecture,segments:segments,store:store,to:folder.appendingPathComponent(name+".pdf"))
            case "Audio", "Clip":
                let range: ClosedRange<Double>?
                if format == "Clip" {
                    guard let a = player.loopStart, let b = player.loopEnd, b > a else { throw ClassNoteError.message("Imposta prima un intervallo A–B valido.") }; range = a...b
                } else { range = nil }
                output = try await AudioExporter.export(chunks:lecture.chunks,directory:store.mediaDirectory(lecture.id),range:range,destination:folder.appendingPathComponent(name+".m4a"))
            case "Backup":
                output = try await Task.detached(priority:.utility) { [store] in try store.backup(lecture,destination:folder) }.value
                files = FileExportPayload(urls:[output]); return
            case "JSON":
                output = folder.appendingPathComponent(name+".json")
                let payload = TranscriptExport(lecture:lecture,segments:segments)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                try encoder.encode(payload).write(to:output,options:.atomic)
            case "Flashcard TSV":
                output = folder.appendingPathComponent(name+".tsv")
                let text = lecture.cards.map { card in
                    [card.question,card.answer+" ["+Timeline.format(card.time)+"]"].map { $0.replacingOccurrences(of:"\t",with:" ").replacingOccurrences(of:"\n",with:" ") }.joined(separator:"\t")
                }.joined(separator:"\n")
                try text.write(to:output,atomically:true,encoding:.utf8)
            default:
                let markdown = format == "Markdown"
                output = folder.appendingPathComponent(name+(markdown ? ".md" : ".txt"))
                var text = (markdown ? "# " : "") + lecture.title + "\n\n"
                text += segments.map { s in
                    let stamp = Timeline.format(s.start)
                    return (markdown ? "[\(stamp)](\(Timeline.deepLink(lecture:lecture.id,time:s.start).absoluteString))" : "[\(stamp)]") + " " + s.displayText
                }.joined(separator:"\n\n")
                text += "\n\n" + lecture.artifacts.map { $0.title+"\n"+$0.text }.joined(separator:"\n\n")
                try text.write(to:output,atomically:true,encoding:.utf8)
            }
            share = SharePayload(items:[output])
        } catch { self.error = error.localizedDescription }
    }
    func openURL(_ url: URL) {
        guard let (id,time) = Timeline.parse(url) else {
            guard url.isFileURL else { error = "Collegamento non supportato."; return }
            Task { await importFile(url) }; return
        }
        guard !capture.recording && !capture.paused else { error = "Termina la registrazione prima di aprire un’altra lezione."; return }
        guard lectures.contains(where:{$0.id == id}) else { error = "La lezione di questo collegamento non è presente su questo iPad."; return }
        select(id); Task { await seek(time) }
    }
}

private struct TranscriptExport: Codable { var lecture: Lecture; var segments: [TranscriptSegment] }
