import XCTest
@testable import ClassNoteCore

final class CoreTests: XCTestCase {
    private func chunk(_ start:Double,_ duration:Double,wall:Date = Date(timeIntervalSince1970:1000)) -> AudioChunk {
        AudioChunk(filename:"test.caf",start:start,duration:duration,sampleRate:16000,wallStart:wall,closed:true)
    }
    private func segment(_ text:String,start:Double = 0) -> TranscriptSegment {
        TranscriptSegment(source:"test",original:text,words:[],start:start,end:start+5,finalized:true)
    }
    func testTimelineBoundarySelectsFollowingChunk() {
        let a = chunk(0,12), b = chunk(12,12)
        XCTAssertEqual(Timeline.chunk(at:12,in:[a,b])?.id,b.id)
        XCTAssertEqual(Timeline.chunk(at:24,in:[a,b])?.id,b.id)
        XCTAssertNil(Timeline.chunk(at:25,in:[a,b]))
        XCTAssertNil(Timeline.chunk(at:.nan,in:[a]))
        XCTAssertNil(Timeline.chunk(at:-1,in:[a]))
    }
    func testPausesHaveNoFabricatedInkTime() {
        let a = chunk(0,10)
        let b = chunk(10,10,wall:Date(timeIntervalSince1970:1020))
        XCTAssertEqual(Timeline.recordingTime(for:Date(timeIntervalSince1970:1025),chunks:[a,b]),15)
        XCTAssertNil(Timeline.recordingTime(for:Date(timeIntervalSince1970:1015),chunks:[a,b]))
        XCTAssertNil(Timeline.recordingTime(for:Date(timeIntervalSince1970:999),chunks:[a,b]))
    }
    func testDeepLinkRoundTripAndValidation() {
        let id = UUID(); let link = Timeline.deepLink(lecture:id,time:125.75)
        XCTAssertEqual(Timeline.parse(link)?.0,id)
        XCTAssertEqual(Timeline.parse(link)?.1,125.75)
        XCTAssertNil(Timeline.parse(URL(string:"classnote://lecture/\(id)?t=nan")!))
        XCTAssertNil(Timeline.parse(URL(string:"classnote://lecture/\(id)?t=-3")!))
        XCTAssertNil(Timeline.parse(URL(string:"https://lecture/\(id)?t=3")!))
    }
    func testPunctuationRetainsWordIdentityAndTime() {
        let old = TimedWord(text:"limite",start:4,end:4.5,state:.confirmed)
        let result = TextAlignment.reconcile(original:[old],correctedText:"Limite,")
        XCTAssertEqual(result[0].id,old.id); XCTAssertEqual(result[0].start,4)
        XCTAssertEqual(result[0].alignment,.retained)
    }
    func testInsertedWordNeverReceivesInventedTimestamp() {
        let old = [TimedWord(text:"il",start:1,end:1.2),TimedWord(text:"limite",start:1.3,end:2)]
        let result = TextAlignment.reconcile(original:old,correctedText:"il nuovo limite")
        XCTAssertEqual(result[0].id,old[0].id); XCTAssertEqual(result[2].id,old[1].id)
        XCTAssertNil(result[1].start); XCTAssertNil(result[1].end)
        XCTAssertEqual(result[1].alignment,.needsReview)
    }
    func testReplacementLosesOnlyChangedWords() {
        let old = [TimedWord(text:"legge",start:1,end:2),TimedWord(text:"di",start:2,end:3),TimedWord(text:"Kirkoff",start:3,end:4)]
        let result = TextAlignment.reconcile(original:old,correctedText:"legge di Kirchhoff")
        XCTAssertEqual(result[0].start,1); XCTAssertEqual(result[1].start,2)
        XCTAssertNil(result[2].start)
    }
    func testRepeatedTokensStayMonotonic() {
        let old = ["la","legge","e","la","legge"].enumerated().map { TimedWord(text:$0.element,start:Double($0.offset),end:Double($0.offset+1)) }
        let result = TextAlignment.reconcile(original:old,correctedText:"la legge")
        XCTAssertEqual(result.compactMap(\.start),[0,1])
        XCTAssertEqual(Set(result.map(\.id)).count,result.count)
    }
    func testCorrectionDoesNotMutateOriginal() throws {
        var s = segment("Testo sbalgiato")
        s.words = [TimedWord(text:"Testo",start:0,end:1),TimedWord(text:"sbalgiato",start:1,end:2)]
        let original = s.words
        s.acceptCorrection("Testo sbagliato")
        XCTAssertEqual(s.original,"Testo sbalgiato"); XCTAssertEqual(s.words,original)
        XCTAssertEqual(s.correctedWords?.last?.alignment,.needsReview)
        let copy = try JSONDecoder().decode(TranscriptSegment.self,from:JSONEncoder().encode(s))
        XCTAssertEqual(copy,s)
        s.restoreOriginal(); XCTAssertNil(s.corrected); XCTAssertEqual(s.words,original)
    }
    func testPartialRevisionsPreserveIDsOnlyAtSameAcousticTime() {
        let old = TimedWord(text:"legge",start:2,end:3)
        let same = TimedWord(text:"Legge",start:2.1,end:3.2)
        let other = TimedWord(text:"legge",start:10,end:11)
        XCTAssertEqual(TextAlignment.preserveIDs(previous:[old],next:[same])[0].id,old.id)
        XCTAssertNotEqual(TextAlignment.preserveIDs(previous:[old],next:[other])[0].id,old.id)
    }
    func testSearchReturnsOnlyActualSources() {
        let lecture = Lecture(title:"Circuiti",subject:"Fisica")
        let a = segment("La legge di Kirchhoff riguarda le correnti nei nodi",start:30)
        let b = segment("La tensione è misurata in volt",start:60)
        let hits = StudyIndex.search("Kirchhoff",corpus:[(lecture,[a,b])])
        XCTAssertEqual(hits.count,1); XCTAssertEqual(hits[0].segment.id,a.id)
        XCTAssertTrue(StudyIndex.search("Dante",corpus:[(lecture,[a,b])]).isEmpty)
    }
    func testExtractiveSummaryNeverChangesSourceText() {
        let sources = [segment("Il limite descrive il comportamento di una funzione"),segment("La continuità collega valore e limite",start:60)]
        let summary = StudyIndex.extractiveSummary(sources,count:1)
        XCTAssertEqual(summary.count,1); XCTAssertTrue(sources.contains(summary[0]))
    }
    func testFlashcardAnswerIsVerbatimAndHasSource() {
        let s = segment("La legge dei nodi esprime la conservazione della carica",start:48)
        let cards = StudyIndex.flashcards([s])
        XCTAssertEqual(cards[0].answer,s.displayText); XCTAssertEqual(cards[0].segmentID,s.id)
        XCTAssertEqual(cards[0].time,48)
    }
    func testSpacedRepetitionAdvancesAndResets() {
        let now = Date(timeIntervalSince1970:100)
        var card = Flashcard(question:"Q",answer:"A",segmentID:UUID(),time:0)
        card.review(remembered:true,now:now)
        XCTAssertEqual(card.level,1); XCTAssertEqual(card.due.timeIntervalSince(now),86400)
        card.review(remembered:true,now:now); XCTAssertEqual(card.level,2)
        card.review(remembered:false,now:now); XCTAssertEqual(card.level,0)
        XCTAssertLessThan(card.due.timeIntervalSince(now),86400)
    }
    func testGoodnotesNewVersionPreservesIdentityButRequiresAnchorReview() {
        var doc = LinkedDocument(title:"Quaderno",filename:"old.pdf",sha256:"abc",pageCount:4)
        doc.anchors = [PageAnchor(page:0,time:25,confirmed:true,source:"manuale"),PageAnchor(page:3,time:80,confirmed:true,source:"manuale")]
        let id = doc.id
        doc.replace(filename:"same.pdf",sha256:"abc",pageCount:4)
        XCTAssertEqual(doc.revision,1); XCTAssertEqual(doc.filename,"old.pdf")
        doc.replace(filename:"new.pdf",sha256:"def",pageCount:2)
        XCTAssertEqual(doc.id,id); XCTAssertEqual(doc.revision,2)
        XCTAssertEqual(doc.anchors.count,1); XCTAssertFalse(doc.anchors[0].confirmed)
    }
    func testLargeEditsAreBoundedAndUnaligned() {
        let text = Array(repeating:"parola",count:700).joined(separator:" ")
        let words = TextAlignment.reconcile(original:[],correctedText:text)
        XCTAssertEqual(words.count,700); XCTAssertTrue(words.allSatisfy { $0.start == nil && $0.alignment == .needsReview })
    }
    func testLongTimelineDoesNotAccumulateWallPauseTime() {
        let chunks = (0..<1200).map { index in chunk(Double(index)*12,12,wall:Date(timeIntervalSince1970:1000+Double(index)*13)) }
        XCTAssertEqual(chunks.last?.end,14_400)
        for i in stride(from:0,to:1200,by:7) {
            let target = Double(i)*12+3.25
            XCTAssertEqual(Timeline.chunk(at:target,in:chunks)?.id,chunks[i].id)
        }
    }
    func testCrossLessonReferencesRetainLectureIdentity() throws {
        let first = Lecture(title:"Limiti",subject:"Matematica")
        let second = Lecture(title:"Continuità",subject:"Matematica")
        let a = segment("Definizione di limite",start:35)
        let b = segment("Definizione di continuità",start:92)
        let refs = [SourceReference(lecture:first,segment:a),SourceReference(lecture:second,segment:b)]
        let artifact = StudyArtifact(title:"Confronto",text:"Fonti",segmentIDs:[a.id,b.id],generated:false,references:refs)
        let restored = try JSONDecoder().decode(StudyArtifact.self,from:JSONEncoder().encode(artifact))
        XCTAssertEqual(restored.references[1].lectureID,second.id)
        XCTAssertEqual(restored.references[0].time,35)
        XCTAssertEqual(Timeline.parse(Timeline.deepLink(lecture:restored.references[0].lectureID,time:restored.references[0].time))?.0,first.id)
    }
}
