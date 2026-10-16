import XCTest
import AVFoundation
import PDFKit
import PencilKit
import ClassNoteCore
@testable import ClassNoteAI

/// Requires the Apple SDK and a simulator/device. These tests are NOT claimed as executed on Linux.
final class AppleIntegrationTests: XCTestCase {
    private var root:URL!
    private var store:LectureStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try LectureStore(root:root)
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at:root) }
    func testIncrementalTranscriptPersistenceAndCascadeDelete() throws {
        let lecture = Lecture(title:"Prova",subject:"Fisica"); try store.save(lecture)
        var segment = TranscriptSegment(source:"test",original:"inizio",words:[],start:0,end:2)
        try store.save(segment,lectureID:lecture.id)
        segment.original = "inizio e fine"; segment.finalized = true
        try store.save(segment,lectureID:lecture.id)
        XCTAssertEqual(try store.segments(lecture.id).count,1)
        XCTAssertEqual(try store.segments(lecture.id)[0].original,"inizio e fine")
        try store.delete(lecture.id)
        XCTAssertTrue(try store.segments(lecture.id).isEmpty)
    }
    func testProtectedAtomicDrawingRoundTrip() throws {
        let lecture = Lecture(title:"Pencil",subject:"Arte"); try store.save(lecture)
        let data = PKDrawing().dataRepresentation()
        try store.write(data,lecture:lecture.id,name:lecture.pages[0].drawingFile)
        let url = try store.media(lecture.id,lecture.pages[0].drawingFile)
        XCTAssertEqual(try Data(contentsOf:url),data)
        XCTAssertNoThrow(try PKDrawing(data:Data(contentsOf:url)))
    }
    func testJournalRecoveryUsesActualAudioLength() throws {
        var lecture = Lecture(title:"Recupero",subject:"Fisica"); lecture.wasRecording = true; try store.save(lecture)
        let format = AVAudioFormat(standardFormatWithSampleRate:16_000,channels:1)!
        let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1600)!; buffer.frameLength = 1600
        for i in 0..<1600 { buffer.floatChannelData![0][i] = Float(sin(Double(i)*0.03))*0.1 }
        let chunk = AudioChunk(filename:"recovered.caf",start:0,sampleRate:16000,closed:false)
        do { let file = try AVAudioFile(forWriting:store.media(lecture.id,chunk.filename),settings:format.settings); try file.write(from:buffer) }
        try store.write(JSONEncoder().encode(chunk),lecture:lecture.id,name:"\(chunk.id.uuidString).chunkmeta")
        let recovered = try store.recover(lecture)
        XCTAssertEqual(recovered.chunks.count,1)
        XCTAssertEqual(recovered.chunks[0].duration,0.1,accuracy:0.001)
        XCTAssertTrue(recovered.chunks[0].recovered); XCTAssertFalse(recovered.wasRecording)
    }
    @MainActor func testPDFExportContainsTranscriptAndNotebookPage() throws {
        let lecture = Lecture(title:"Verifica PDF",subject:"Matematica"); try store.save(lecture)
        let s = TranscriptSegment(source:"test",original:"La funzione è continua",words:[],start:15,end:18,finalized:true)
        let url = root.appendingPathComponent("export.pdf")
        _ = try DocumentBridge.exportPDF(lecture:lecture,segments:[s],store:store,to:url)
        let pdf = try XCTUnwrap(PDFDocument(url:url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount,2)
        XCTAssertTrue(pdf.string?.contains("La funzione") == true)
        XCTAssertTrue(pdf.page(at:0)?.annotations.contains(where:{$0.url?.scheme == "classnote"}) == true)
    }
    func testBackupRestoreDoesNotOverwriteAndRejectsTraversal() throws {
        let lecture = Lecture(title:"Backup",subject:"Storia"); try store.save(lecture)
        let package = try store.backup(lecture,destination:root)
        XCTAssertThrowsError(try store.restore(package))
        XCTAssertThrowsError(try store.media(lecture.id,"../secret"))
        let other = try LectureStore(root:root.appendingPathComponent("other"))
        let restored = try other.restore(package)
        XCTAssertEqual(restored.id,lecture.id)
    }
}
