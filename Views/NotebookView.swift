import SwiftUI
import PhotosUI
import VisionKit
import ClassNoteCore

@MainActor struct NotebookView: View {
    @EnvironmentObject private var model:AppModel
    @StateObject private var actions = NotebookActions()
    @State private var selectedID:UUID?
    @State private var scanner = false
    @State private var photo:PhotosPickerItem?
    @State private var showText = false
    @State private var showFormula = false
    @State private var ocrBusy = false
    private var page:NotebookPage? {
        model.current?.pages.first(where:{$0.id == selectedID}) ?? model.current?.pages.first
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                if let page {
                    Picker("Pagina",selection:Binding(get:{page.id},set:{selectedID = $0})) {
                        ForEach(Array((model.current?.pages ?? []).enumerated()),id:\.element.id) { index,p in Text("Pagina \(index+1)").tag(p.id) }
                    }.labelsHidden().frame(maxWidth:150)
                    Menu {
                        ForEach(PaperStyle.allCases,id:\.self) { style in
                            Button(style == .blank ? "Bianca" : style == .ruled ? "Rigata" : "Quadrettata") {
                                var p = page; p.style = style; model.updatePage(p)
                            }
                        }
                    } label: { Image(systemName:"square.grid.3x3") }
                }
                Spacer(minLength:0)
                Button { actions.undo() } label: { Image(systemName:"arrow.uturn.backward") }.accessibilityLabel("Annulla tratto")
                Button { actions.redo() } label: { Image(systemName:"arrow.uturn.forward") }.accessibilityLabel("Ripristina tratto")
                Menu {
                    Button("Nuova pagina",systemImage:"plus") { selectedID = model.addPage() }
                    Button("Testo e OCR",systemImage:"text.cursor") { showText.toggle() }
                    Button("Formula LaTeX",systemImage:"function") { showFormula = true }
                    Button("Scansiona lavagna",systemImage:"camera.viewfinder") {
                        if VNDocumentCameraViewController.isSupported { scanner = true }
                        else { model.message = "La scansione richiede un dispositivo con fotocamera supportata. Importa un’immagine da File o Foto." }
                    }
                    Button("Riconosci scrittura della pagina",systemImage:"text.viewfinder") { recognizeInk() }.disabled(ocrBusy)
                } label: { Image(systemName:"plus.circle") }
                PhotosPicker(selection:$photo,matching:.images) { Image(systemName:"photo") }
            }.padding(.horizontal,14).padding(.vertical,8)
            Divider()
            if let page, let current = model.current {
                if let filename = page.imageFile, let url = try? model.store.media(current.id,filename), let image = UIImage(contentsOfFile:url.path) {
                    VStack(alignment:.leading,spacing:4) {
                        Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:170)
                        if let time = page.imageTime { Button("Foto · \(Timeline.format(time))") { Task { await model.seek(time) } }.font(.caption) }
                    }.padding(8)
                }
                NotebookSurface(page:page,lecture:current,player:model.player,capture:model.capture,actions:actions)
                    .id(page.id)
                    .overlay(alignment:.topTrailing) { Text("Apple Pencil · dito per ascoltare").font(.caption2).padding(7).background(.thinMaterial,in:Capsule()).padding(8).allowsHitTesting(false) }
                if showText {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Testo della pagina").font(.caption.bold())
                        TextEditor(text:Binding(get:{self.page?.text ?? ""},set:{ value in
                            guard var p = self.page else { return }; p.text = value; model.updatePage(p)
                        })).frame(height:90)
                        if !page.ocr.isEmpty { Text("OCR: \(page.ocr)").font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled) }
                    }.padding(12).background(.regularMaterial)
                }
                StrokeTimeline(page:page,player:model.player)
            }
        }
        .background(Color(uiColor:.secondarySystemGroupedBackground))
        .onChange(of:model.current?.id) { _,_ in selectedID = model.current?.pages.first?.id }
        .onReceive(model.player.$time) { time in
            guard model.player.playing else { return }
            if let p = model.current?.pages.first(where:{ page in
                page.strokes.contains { anchor in anchor.time.map { time >= $0 && time < $0 + max(1.5,anchor.duration) } ?? false }
            }) { selectedID = p.id }
        }
        .sheet(isPresented:$scanner) { BoardScanner(onImages:{ images in Task { for image in images { await model.addImage(image) }; selectedID = model.current?.pages.last?.id } },onError:{model.error = $0}) }
        .sheet(isPresented:$showFormula) { FormulaEditor(onInsert:{ formula in
            guard var p = page else { return }; p.text += "\n$$\(formula)$$\n"; model.updatePage(p); showText = true
        }) }
        .task(id:photo) {
            guard let photo, let data = try? await photo.loadTransferable(type:Data.self), let image = UIImage(data:data) else { return }
            await model.addImage(image); selectedID = model.current?.pages.last?.id
        }
    }
    private func recognizeInk() {
        guard let image = actions.image(), let pageID = page?.id else { return }
        ocrBusy = true
        Task {
            defer { ocrBusy = false }
            do {
                let text = try await VisionTools.recognize(image)
                guard var p = model.current?.pages.first(where:{$0.id == pageID}) else { return }
                p.ocr = text; model.updatePage(p); showText = true
                if text.isEmpty { model.message = "Nessun testo riconosciuto. L’OCR della scrittura dipende dalla leggibilità e dal dispositivo." }
            } catch { model.error = error.localizedDescription }
        }
    }
}

@MainActor private struct NotebookSurface: View {
    @EnvironmentObject private var model:AppModel
    var page:NotebookPage; var lecture:Lecture
    @ObservedObject var player:LecturePlayer
    @ObservedObject var capture:AudioCapture
    var actions:NotebookActions
    var body: some View {
        NotebookCanvas(page:page,drawingURL:try? model.store.media(lecture.id,page.drawingFile),chunks:lecture.chunks,
            liveChunks:{
                var chunks = model.current?.chunks ?? lecture.chunks
                if let live = capture.latestChunk {
                    if let i = chunks.firstIndex(where:{$0.id == live.id}) { chunks[i] = live } else { chunks.append(live) }
                }
                return chunks
            },playbackTime:player.time,recording:capture.recording,replaying:player.playing,actions:actions,
            onChange:{ data,anchors in model.saveDrawing(pageID:page.id,data:data,strokes:anchors) },
            onTap:{ time in Task { await model.seek(time) } })
    }
}

@MainActor private struct StrokeTimeline: View {
    @EnvironmentObject private var model:AppModel
    var page:NotebookPage
    @ObservedObject var player:LecturePlayer
    var body: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                Label("Inchiostro",systemImage:"pencil.tip").font(.caption).foregroundStyle(.secondary)
                let grouped = Array(Set(page.strokes.compactMap(\.time).map { Int($0/10)*10 })).sorted()
                ForEach(grouped,id:\.self) { time in
                    Button(Timeline.format(Double(time))) { Task { await model.seek(Double(time)) } }
                        .font(.caption.monospacedDigit()).buttonStyle(.bordered)
                }
                if grouped.isEmpty { Text("Scrivi durante la registrazione per collegare i tratti all’audio.").font(.caption2).foregroundStyle(.secondary) }
            }.padding(10)
        }.background(.bar)
    }
}
