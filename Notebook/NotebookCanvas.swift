import SwiftUI
import PencilKit
import CryptoKit
import ClassNoteCore

@MainActor final class NotebookActions: ObservableObject {
    weak var canvas: PKCanvasView?
    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    func image() -> UIImage? {
        guard let ink = canvas?.drawing.image(from:CGRect(x:0,y:0,width:1000,height:1400),scale:1.5) else { return nil }
        return UIGraphicsImageRenderer(size:ink.size).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:ink.size)); ink.draw(at:.zero)
        }
    }
}

enum NotebookRenderer {
    static let pageSize = CGSize(width:1000,height:1400)
    static func paper(style: PaperStyle, in context: CGContext, rect: CGRect) {
        context.setFillColor(UIColor.white.cgColor); context.fill(rect)
        guard style != .blank else { return }
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.14).cgColor); context.setLineWidth(0.7)
        for y in stride(from:CGFloat(0),through:rect.height,by:32) {
            context.move(to:CGPoint(x:0,y:y)); context.addLine(to:CGPoint(x:rect.width,y:y))
        }
        if style == .grid {
            for x in stride(from:CGFloat(0),through:rect.width,by:32) {
                context.move(to:CGPoint(x:x,y:0)); context.addLine(to:CGPoint(x:x,y:rect.height))
            }
        }
        context.strokePath()
    }
    static func pattern(_ style: PaperStyle) -> UIImage {
        UIGraphicsImageRenderer(size:CGSize(width:32,height:32)).image { ctx in
            paper(style:style,in:ctx.cgContext,rect:CGRect(x:0,y:0,width:32,height:32))
        }
    }
    static func strokeID(_ stroke: PKStroke) -> String {
        let path = stroke.path
        let first = path.first; let last = path.last
        let key = "\(path.creationDate.timeIntervalSince1970)|\(path.count)|\(first?.location.x ?? 0)|\(first?.location.y ?? 0)|\(last?.location.x ?? 0)|\(last?.location.y ?? 0)|\(last?.timeOffset ?? 0)"
        return SHA256.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
    }
}

@MainActor struct NotebookCanvas: UIViewRepresentable {
    var page: NotebookPage
    var drawingURL: URL?
    var chunks: [AudioChunk]
    var liveChunks: () -> [AudioChunk]
    var playbackTime: Double
    var recording: Bool
    var replaying: Bool
    var actions: NotebookActions
    var onChange: (Data,[StrokeAnchor]) -> Void
    var onTap: (Double) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator; canvas.drawingPolicy = .pencilOnly
        canvas.contentSize = NotebookRenderer.pageSize; canvas.minimumZoomScale = 0.35; canvas.maximumZoomScale = 3
        canvas.alwaysBounceVertical = true; canvas.isOpaque = false
        canvas.accessibilityLabel = "Quaderno Apple Pencil. Tocca un tratto con il dito per ascoltarlo."
        canvas.tool = PKInkingTool(.pen,color:.black,width:3)
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:)))
        tap.allowedTouchTypes = [NSNumber(value:UITouch.TouchType.direct.rawValue)]; tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)
        context.coordinator.canvas = canvas; actions.canvas = canvas
        let picker = PKToolPicker()
        context.coordinator.picker = picker; picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder(); picker.setVisible(true,forFirstResponder:canvas) }
        return canvas
    }
    func updateUIView(_ canvas:PKCanvasView,context:Context) {
        context.coordinator.parent = self
        if context.coordinator.pageID != page.id {
            context.coordinator.loading = true
            let data = drawingURL.flatMap { try? Data(contentsOf:$0) }
            canvas.drawing = data.flatMap { try? PKDrawing(data:$0) } ?? PKDrawing()
            canvas.undoManager?.removeAllActions()
            context.coordinator.pageID = page.id; context.coordinator.loading = false
            canvas.zoomScale = max(canvas.minimumZoomScale,min(1,canvas.bounds.width/1000))
        }
        if context.coordinator.style != page.style {
            canvas.backgroundColor = UIColor(patternImage:NotebookRenderer.pattern(page.style))
            context.coordinator.style = page.style
        }
        context.coordinator.highlight()
    }
    static func dismantleUIView(_ uiView:PKCanvasView,coordinator:Coordinator) {
        coordinator.saveWork?.cancel(); coordinator.save()
        coordinator.picker?.setVisible(false,forFirstResponder:uiView)
        if let picker = coordinator.picker { picker.removeObserver(uiView) }
    }
    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: NotebookCanvas
        weak var canvas: PKCanvasView?
        var picker: PKToolPicker?
        var pageID: UUID?
        var style: PaperStyle?
        var loading = false
        var saveWork: DispatchWorkItem?
        var strokeSessionStart: Date?
        var replayAnchorTime: Double?
        private var highlightLayers: [CAShapeLayer] = []
        init(_ parent:NotebookCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView:PKCanvasView) {
            guard !loading else { return }
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.save() }
            saveWork = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:work)
        }
        func canvasViewDidBeginUsingTool(_ canvasView:PKCanvasView) {
            strokeSessionStart = Date(); replayAnchorTime = parent.replaying ? parent.playbackTime : nil
        }
        func canvasViewDidEndUsingTool(_ canvasView:PKCanvasView) {
            saveWork?.cancel(); save(); strokeSessionStart = nil; replayAnchorTime = nil
        }
        func save() {
            guard !loading, let canvas, pageID == parent.page.id else { return }
            let previous = Dictionary(parent.page.strokes.map { ($0.id,$0) },uniquingKeysWith: { a,_ in a })
            let anchors = canvas.drawing.strokes.map { stroke -> StrokeAnchor in
                let id = NotebookRenderer.strokeID(stroke)
                let rect = stroke.renderBounds
                var time = previous[id]?.time
                if time == nil {
                    time = Timeline.recordingTime(for:stroke.path.creationDate,chunks:parent.liveChunks())
                    if time == nil, previous[id] == nil, let sessionStart = strokeSessionStart,
                       stroke.path.creationDate >= sessionStart.addingTimeInterval(-0.25) {
                        time = replayAnchorTime
                    }
                }
                return StrokeAnchor(id:id,time:time,duration:stroke.path.last?.timeOffset ?? 0,
                    x:Double(rect.minX),y:Double(rect.minY),width:Double(rect.width),height:Double(rect.height))
            }
            parent.onChange(canvas.drawing.dataRepresentation(),anchors)
        }
        @objc func tap(_ recognizer:UITapGestureRecognizer) {
            guard let canvas else { return }
            let point = recognizer.location(in:canvas)
            let drawingPoint = CGPoint(x:point.x/canvas.zoomScale,y:point.y/canvas.zoomScale)
            if let hit = parent.page.strokes.reversed().first(where: {
                CGRect(x:$0.x,y:$0.y,width:$0.width,height:$0.height).insetBy(dx:-12,dy:-12).contains(drawingPoint) && $0.time != nil
            }), let time = hit.time { parent.onTap(time) }
        }
        func scrollViewDidScroll(_ scrollView:UIScrollView) { highlight() }
        func scrollViewDidZoom(_ scrollView:UIScrollView) { highlight() }
        func highlight() {
            guard let canvas else { return }
            highlightLayers.forEach { $0.removeFromSuperlayer() }; highlightLayers.removeAll(keepingCapacity:true)
            guard parent.replaying else { return }
            for anchor in parent.page.strokes {
                guard let time = anchor.time, parent.playbackTime >= time,
                      parent.playbackTime < time + max(1.5,anchor.duration) else { continue }
                let rect = CGRect(x:anchor.x,y:anchor.y,width:anchor.width,height:anchor.height)
                    .insetBy(dx:-4,dy:-4).applying(CGAffineTransform(scaleX:canvas.zoomScale,y:canvas.zoomScale))
                let layer = CAShapeLayer(); layer.path = UIBezierPath(roundedRect:rect,cornerRadius:6).cgPath
                layer.fillColor = UIColor.systemYellow.withAlphaComponent(0.25).cgColor
                layer.strokeColor = UIColor.systemOrange.cgColor; layer.lineWidth = 1.5
                canvas.layer.addSublayer(layer); highlightLayers.append(layer)
            }
        }
    }
}
