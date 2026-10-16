import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import PencilKit
import CoreText
import ClassNoteCore

enum DocumentBridge {
    static func importPDF(url: URL, lecture: inout Lecture, replacing: UUID?, store: LectureStore) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        var updated = lecture
        var coordinationError: NSError?
        var result: Result<Void,Error>?
        NSFileCoordinator().coordinate(readingItemAt:url,options:[],error:&coordinationError) { source in
            result = Result {
                let values = try source.resourceValues(forKeys:[.fileSizeKey])
                guard (values.fileSize ?? 0) < 500*1024*1024 else { throw ClassNoteError.message("PDF oltre 500 MB. Importa poche pagine alla volta.") }
                let data = try Data(contentsOf:source,options:.mappedIfSafe)
                guard let pdf = PDFDocument(data:data), !pdf.isLocked, pdf.pageCount > 0 else { throw ClassNoteError.message("PDF non leggibile o protetto da password.") }
                let checksum = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                if updated.documents.contains(where:{$0.sha256 == checksum && $0.id != replacing}) { return }
                let filename = "document-\(UUID().uuidString).pdf"
                try store.write(data,lecture:updated.id,name:filename)
                if let replacing, let index = updated.documents.firstIndex(where:{$0.id == replacing}) {
                    if updated.documents[index].sha256 == checksum { try? FileManager.default.removeItem(at:store.media(updated.id,filename)); return }
                    // Keep the old file until the new metadata commits. Orphan collection is explicit.
                    updated.documents[index].replace(filename:filename,sha256:checksum,pageCount:pdf.pageCount)
                } else {
                    updated.documents.append(LinkedDocument(title:source.deletingPathExtension().lastPathComponent,
                        filename:filename,sha256:checksum,pageCount:pdf.pageCount))
                }
                try store.save(updated)
            }
        }
        if let coordinationError { throw coordinationError }
        try result?.get()
        lecture = updated
    }
    @MainActor static func exportPDF(lecture: Lecture, segments: [TranscriptSegment], store: LectureStore, to url: URL) throws -> URL {
        let bounds = CGRect(x:0,y:0,width:595,height:842)
        let renderer = UIGraphicsPDFRenderer(bounds:bounds)
        try renderer.writePDF(to:url) { context in
            let titleAttributes: [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize:22),.foregroundColor:UIColor.black]
            let bodyAttributes: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:12),.foregroundColor:UIColor.black]
            let headingAttributes: [NSAttributedString.Key:Any] = [.font:UIFont.monospacedDigitSystemFont(ofSize:10,weight:.medium),.foregroundColor:UIColor.systemBlue]
            context.beginPage()
            lecture.title.draw(in:CGRect(x:38,y:36,width:519,height:50),withAttributes:titleAttributes)
            "\(lecture.subject) · \(lecture.date.formatted(date:.abbreviated,time:.shortened))\nCollegamenti ClassNote: richiedono l’app e la lezione originale sullo stesso dispositivo."
                .draw(in:CGRect(x:38,y:88,width:519,height:52),withAttributes:bodyAttributes)
            var y: CGFloat = 152
            func flow(_ text: String) {
                let attributed = NSAttributedString(string:text,attributes:bodyAttributes)
                let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
                var offset = 0
                while offset < attributed.length {
                    if y > 760 { context.beginPage(); y = 36 }
                    let available = 800-y
                    let path = CGMutablePath()
                    path.addRect(CGRect(x:38,y:42,width:519,height:available))
                    let frame = CTFramesetterCreateFrame(framesetter,CFRange(location:offset,length:0),path,nil)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    guard visible.length > 0 else { context.beginPage(); y = 36; continue }
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x:0,y:842); context.cgContext.scaleBy(x:1,y:-1)
                    CTFrameDraw(frame,context.cgContext); context.cgContext.restoreGState()
                    let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,CFRange(location:offset,length:visible.length),nil,
                        CGSize(width:519,height:available),nil)
                    offset += visible.length; y += ceil(size.height)+12
                    if offset < attributed.length { context.beginPage(); y = 36 }
                }
            }
            for segment in segments {
                if y > 730 { context.beginPage(); y = 36 }
                let linkRect = CGRect(x:38,y:y,width:150,height:16)
                Timeline.format(segment.start).draw(in:linkRect,withAttributes:headingAttributes)
                context.setURL(Timeline.deepLink(lecture:lecture.id,time:segment.start),for:linkRect)
                y += 20; flow(segment.displayText)
            }
            for page in lecture.pages {
                context.beginPage()
                context.cgContext.saveGState()
                context.cgContext.scaleBy(x:bounds.width/1000,y:bounds.height/1400)
                NotebookRenderer.paper(style:page.style,in:context.cgContext,rect:CGRect(origin:.zero,size:NotebookRenderer.pageSize))
                if let filename = page.imageFile, let imageURL = try? store.media(lecture.id,filename), let image = UIImage(contentsOfFile:imageURL.path) {
                    let scale = min(920/image.size.width,760/image.size.height)
                    image.draw(in:CGRect(x:40,y:60,width:image.size.width*scale,height:image.size.height*scale))
                }
                if let dataURL = try? store.media(lecture.id,page.drawingFile), let data = try? Data(contentsOf:dataURL), let drawing = try? PKDrawing(data:data) {
                    drawing.image(from:CGRect(origin:.zero,size:NotebookRenderer.pageSize),scale:1.5).draw(in:CGRect(origin:.zero,size:NotebookRenderer.pageSize))
                }
                context.cgContext.restoreGState()
                for stroke in page.strokes {
                    guard let time = stroke.time else { continue }
                    let r = CGRect(x:stroke.x*595/1000,y:stroke.y*842/1400,width:max(10,stroke.width*595/1000),height:max(10,stroke.height*842/1400))
                    context.setURL(Timeline.deepLink(lecture:lecture.id,time:time),for:r)
                }
                if let time = page.imageTime {
                    let rect = CGRect(x:30,y:810,width:250,height:20)
                    "Foto · \(Timeline.format(time))".draw(in:rect,withAttributes:headingAttributes)
                    context.setURL(Timeline.deepLink(lecture:lecture.id,time:time),for:rect)
                }
                if !page.text.isEmpty { context.beginPage(); y = 36; flow(page.text) }
            }
            for document in lecture.documents {
                guard let path = try? store.media(lecture.id,document.filename), let pdf = PDFDocument(url:path) else { continue }
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at:index) else { continue }
                    context.beginPage()
                    let box = page.bounds(for:.mediaBox)
                    let scale = min(555/box.width,750/box.height)
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x:20,y:790)
                    context.cgContext.scaleBy(x:scale,y:-scale)
                    context.cgContext.translateBy(x:-box.minX,y:-box.minY)
                    page.draw(with:.mediaBox,to:context.cgContext)
                    context.cgContext.restoreGState()
                    if let anchor = document.anchors.first(where:{$0.page == index && $0.confirmed}) {
                        let rect = CGRect(x:24,y:815,width:350,height:18)
                        "Apri audio · \(Timeline.format(anchor.time))".draw(in:rect,withAttributes:headingAttributes)
                        context.setURL(Timeline.deepLink(lecture:lecture.id,time:anchor.time),for:rect)
                    }
                }
            }
            for artifact in lecture.artifacts {
                context.beginPage()
                y = 36; flow(artifact.title); flow(artifact.text)
                for reference in artifact.references {
                    if y > 760 { context.beginPage(); y = 36 }
                    let rect = CGRect(x:38,y:y,width:519,height:20)
                    "\(reference.lectureTitle) · \(Timeline.format(reference.time))".draw(in:rect,withAttributes:headingAttributes)
                    context.setURL(Timeline.deepLink(lecture:reference.lectureID,time:reference.time),for:rect)
                    y += 24
                }
            }
        }
        return url
    }
}

@MainActor struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

@MainActor struct ExportToFiles: UIViewControllerRepresentable {
    var urls: [URL]
    func makeUIViewController(context:Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting:urls,asCopy:true)
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
}

@MainActor struct PDFViewer: UIViewRepresentable {
    var url: URL
    @Binding var pageIndex: Int
    var onPage: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical; view.document = PDFDocument(url:url)
        context.coordinator.view = view
        context.coordinator.observer = NotificationCenter.default.addObserver(forName:.PDFViewPageChanged,object:view,queue:.main) { [weak coordinator = context.coordinator] _ in
            Task { @MainActor [weak coordinator] in
                guard let coordinator, let view = coordinator.view,
                      let page = view.currentPage, let index = view.document?.index(for:page) else { return }
                coordinator.parent.pageIndex = index
                coordinator.parent.onPage(index)
            }
        }
        return view
    }
    func updateUIView(_ view:PDFView,context:Context) {
        context.coordinator.parent = self
        if view.document?.documentURL != url { view.document = PDFDocument(url:url) }
    }
    @MainActor final class Coordinator {
        var parent: PDFViewer; weak var view: PDFView?; var observer: NSObjectProtocol?
        init(_ parent:PDFViewer) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
