import SwiftUI
import PDFKit
import ClassNoteCore

@MainActor struct GoodnotesView: View {
    @EnvironmentObject private var model:AppModel
    @State private var importing = false
    @State private var replacing:UUID?
    @State private var selected:UUID?
    @State private var pageIndex = 0
    @State private var pageTime = 0.0
    @State private var suggesting = false
    private var document:LinkedDocument? { model.current?.documents.first(where:{$0.id == selected}) }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Label("Il tuo quaderno, anche in Goodnotes",systemImage:"square.and.arrow.up.on.square").font(.headline)
                    Spacer()
                    Button { replacing = nil; importing = true } label: { Image(systemName:"plus") }.accessibilityLabel("Importa PDF Goodnotes")
                }
                Text("Apri le due app affiancate. Esporta le pagine da Goodnotes in PDF, poi importale qui. I collegamenti all’audio vengono confermati da te.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Invia PDF a Goodnotes",systemImage:"square.and.arrow.up") { Task { await model.export("PDF") } }.buttonStyle(.bordered)
                    Text("Dal menu Condividi scegli Goodnotes o Salva su File.").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
            if let document, let current = model.current, let url = try? model.store.media(current.id,document.filename) {
                HStack {
                    Button { selected = nil } label: { Image(systemName:"chevron.left") }
                    Text(document.title).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Text("v\(document.revision) · p. \(pageIndex+1)/\(document.pageCount)").font(.caption.monospacedDigit())
                    Menu {
                        Button("Aggiorna questo PDF") { replacing = document.id; importing = true }
                        Button("Condividi PDF") { model.share = SharePayload(items:[url]) }
                    } label: { Image(systemName:"ellipsis.circle") }
                }.padding(12)
                PDFViewer(url:url,pageIndex:$pageIndex,onPage:{ _ in }).frame(maxHeight:.infinity)
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text("Collega pagina \(pageIndex+1) a").font(.caption)
                        TextField("Secondi",value:$pageTime,format:.number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width:90)
                        Button("Ora audio") { pageTime = model.capture.recording ? model.capture.duration : model.player.time }.font(.caption)
                        Button("Conferma") { confirm(document) }.font(.caption.bold())
                    }
                    Button(suggesting ? "Confronto pagina e trascrizione…" : "Suggerisci collegamento dal contenuto (OCR)") { suggest(document,url:url) }
                        .font(.caption).disabled(suggesting)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(document.anchors.filter { $0.page == pageIndex }) { anchor in
                                HStack {
                                    Button("\(Timeline.format(anchor.time)) · \(anchor.confirmed ? "confermato" : "da confermare")") {
                                        pageTime = anchor.time
                                        if anchor.confirmed { Task { await model.seek(anchor.time) } }
                                    }
                                    if !anchor.confirmed { Button("✓") { var d = document; if let i = d.anchors.firstIndex(where:{$0.id == anchor.id}) { d.anchors[i].confirmed = true }; model.updateDocument(d) } }
                                    Button { var d = document; d.anchors.removeAll { $0.id == anchor.id }; model.updateDocument(d) } label: { Image(systemName:"xmark") }
                                }.font(.caption2).padding(8).background(.thinMaterial,in:Capsule())
                            }
                        }
                    }
                }.padding(12).background(.bar)
            } else {
                List {
                    ForEach(model.current?.documents ?? []) { document in
                        if let current = model.current, let url = try? model.store.media(current.id,document.filename) {
                            Button { selected = document.id; pageIndex = 0 } label: {
                                HStack {
                                    Image(systemName:"doc.richtext").font(.title2).foregroundStyle(.indigo)
                                    VStack(alignment:.leading,spacing:4) { Text(document.title); Text("\(document.pageCount) pagine · revisione \(document.revision)").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical,6)
                            }.buttonStyle(.plain)
                                .onDrag { NSItemProvider(contentsOf:url) ?? NSItemProvider() }
                        }
                    }
                    if model.current?.documents.isEmpty == true {
                        Text("Nessun PDF collegato. Importane uno da File o trascinalo qui.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Come funziona") {
                        Text("Usa Aggiorna questo PDF per conservare il collegamento alla stessa lezione. Un file identico non crea duplicati; dopo una nuova versione, i collegamenti pagina-audio vanno riconfermati.")
                        Text("I timestamp dei tratti di Goodnotes non sono disponibili tramite questo scambio. Un suggerimento ricavato dal testo è una corrispondenza di contenuto, non l’ora in cui hai scritto.")
                        Text("La registrazione in background può continuare mentre usi Goodnotes. La trascrizione può rallentare o interrompersi: controlla l’indicatore e recupera dai file audio.")
                    }.font(.caption).foregroundStyle(.secondary)
                }.listStyle(.insetGrouped)
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url,replacing:replacing) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
    }
    private func confirm(_ document:LinkedDocument) {
        guard pageTime.isFinite, pageTime >= 0, pageTime <= (model.current?.duration ?? 0) else { model.error = "Il tempo deve essere all’interno della registrazione."; return }
        var updated = document
        updated.anchors.append(PageAnchor(page:pageIndex,time:pageTime,confirmed:true,source:"Associazione manuale"))
        model.updateDocument(updated)
    }
    private func suggest(_ document:LinkedDocument,url:URL) {
        guard let pdf = PDFDocument(url:url), let page = pdf.page(at:pageIndex), let lecture = model.current else { return }
        let targetPage = pageIndex
        suggesting = true
        Task {
            defer { suggesting = false }
            do {
                let text = try await VisionTools.pdfPageText(page)
                let hits = StudyIndex.search(text,corpus:[(lecture,model.segments)],limit:3)
                guard var updated = model.current?.documents.first(where:{$0.id == document.id}) else { return }
                updated.anchors.removeAll { $0.page == targetPage && !$0.confirmed }
                for hit in hits {
                    updated.anchors.append(PageAnchor(page:targetPage,time:hit.segment.start,confirmed:false,source:"Somiglianza lessicale del contenuto, non timestamp originale"))
                }
                model.updateDocument(updated)
                if hits.isEmpty { model.message = "Nessuna corrispondenza affidabile: associa manualmente la pagina all’audio." }
            } catch { model.error = error.localizedDescription }
        }
    }
}
