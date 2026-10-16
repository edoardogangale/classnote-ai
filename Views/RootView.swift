import SwiftUI
import UniformTypeIdentifiers
import ClassNoteCore

@MainActor struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var semantic = false
    @State private var hits: [SearchHit] = []
    @State private var newLesson = false
    @State private var settings = false
    @State private var importing = false
    @State private var restore = false
    @State private var deleteID: UUID?
    @State private var dropTargeted = false
    var body: some View { lifecycleView }

    private var lifecycleView: some View {
        feedbackView
            .onOpenURL { model.openURL($0) }
            .onChange(of:scenePhase) { _, phase in
                model.foreground = phase == .active
                model.persist()
                UIApplication.shared.isIdleTimerDisabled = phase == .active && model.capture.recording
            }
            .task(id:query + (semantic ? "|semantic" : "|text")) {
                try? await Task.sleep(for:.milliseconds(250))
                guard !Task.isCancelled else { return }
                hits = model.searchAll(query,semantic:semantic)
            }
    }
    private var feedbackView: some View {
        importView
            .alert("ClassNote AI",isPresented:errorPresented) {
                Button("OK",role:.cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Eliminare definitivamente questa lezione e tutti i suoi file?",isPresented:deletePresented,titleVisibility:.visible) {
                Button("Elimina definitivamente",role:.destructive) {
                    if let id = deleteID { model.delete(id) }
                    deleteID = nil
                }
            }
    }
    private var errorPresented: Binding<Bool> {
        Binding(get:{model.error != nil},set:{if !$0 { model.error = nil }})
    }
    private var deletePresented: Binding<Bool> {
        Binding(get:{deleteID != nil},set:{if !$0 { deleteID = nil }})
    }
    private var importView: some View {
        presentedView
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image,.audio],allowsMultipleSelection:true,onCompletion:importFiles)
            .fileImporter(isPresented:$restore,allowedContentTypes:[.folder,.package],allowsMultipleSelection:false,onCompletion:restoreFiles)
    }
    private var presentedView: some View {
        navigationView
            .sheet(isPresented:$newLesson) { NewLectureView() }
            .sheet(isPresented:$settings) { SettingsView() }
            .sheet(item:$model.share) { payload in ShareSheet(items:payload.items) }
            .sheet(item:$model.files) { payload in ExportToFiles(urls:payload.urls) }
    }
    private var navigationView: some View {
        NavigationSplitView { sidebar } detail: { detail }
            .tint(.indigo)
            .overlay(alignment:.top) { messageBanner }
            .overlay { dropHighlight }
            .onDrop(of:[UTType.pdf.identifier,UTType.fileURL.identifier,UTType.image.identifier,UTType.audio.identifier],isTargeted:$dropTargeted,perform:receiveDrop)
    }
    private var sidebar: some View {
        VStack(spacing:0) {
            brandHeader
            lessonList
            sidebarControls
        }
        .navigationTitle("Archivio")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"Cerca nelle lezioni")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button("Importa PDF, immagine o audio",systemImage:"square.and.arrow.down") { importing = true }
                    Button("Ripristina backup",systemImage:"externaldrive") { restore = true }
                } label: { Image(systemName:"square.and.arrow.down") }
            }
        }
    }
    private var brandHeader: some View {
        HStack(spacing:12) {
            Image(systemName:"waveform.and.mic").font(.title2).foregroundStyle(.indigo)
            VStack(alignment:.leading,spacing:3) {
                Text("ClassNote AI").font(.title3.bold())
                Text("Ascolta. Scrivi. Ritrova.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding()
    }
    private var sidebarControls: some View {
        HStack {
            Button { settings = true } label: { Label("Impostazioni",systemImage:"gearshape") }
            Spacer()
            Button { newLesson = true } label: {
                Image(systemName:"plus.circle.fill").font(.title2)
            }.accessibilityLabel("Nuova lezione")
        }.padding()
    }
    private var lessonList: some View {
        List {
            if query.isEmpty { archiveSections }
            else { searchSections }
        }.listStyle(.sidebar)
    }
    private var subjects: [String] { Array(Set(model.lectures.map(\.subject))).sorted() }
    private var noteMatches: [Lecture] {
        model.lectures.filter { lecture in
            lecture.pages.contains { ($0.text + " " + $0.ocr).localizedCaseInsensitiveContains(query) }
        }
    }
    @ViewBuilder private var archiveSections: some View {
        ForEach(subjects,id:\.self) { subject in
            Section(subject.isEmpty ? "Lezioni" : subject) {
                ForEach(model.lectures.filter { $0.subject == subject }) { lecture in
                    Button { model.select(lecture.id) } label: {
                        LectureRow(lecture:lecture,selected:model.current?.id == lecture.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Elimina lezione",systemImage:"trash",role:.destructive) { deleteID = lecture.id }
                    }
                }
            }
        }
        if model.lectures.isEmpty {
            Text("Crea la tua prima lezione con +").foregroundStyle(.secondary).listRowSeparator(.hidden)
        }
    }
    @ViewBuilder private var searchSections: some View {
        Section("Nelle trascrizioni") {
            Toggle("Ricerca semantica locale",isOn:$semantic).font(.caption)
            ForEach(hits) { hit in
                Button { openHit(hit) } label: { SearchResultLabel(hit:hit) }.buttonStyle(.plain)
            }
            if hits.isEmpty { Text("Nessun passaggio trovato").foregroundStyle(.secondary) }
        }
        Section("Nei quaderni") {
            ForEach(noteMatches) { lecture in
                Button(lecture.title) { model.select(lecture.id) }
            }
        }
    }
    @ViewBuilder private var detail: some View {
        if model.current != nil { LectureWorkspace() }
        else {
            ContentUnavailableView {
                Label("Ogni lezione, al suo posto.",systemImage:"books.vertical")
            } description: {
                Text("Registra, segui le parole in diretta e scrivi con Apple Pencil. Usa i PDF per continuare a lavorare con Goodnotes.")
            } actions: {
                Button("Crea una lezione",systemImage:"plus") { newLesson = true }.buttonStyle(.borderedProminent)
            }
        }
    }
    @ViewBuilder private var messageBanner: some View {
        if let message = model.message {
            HStack(alignment:.top) {
                Image(systemName:"info.circle.fill")
                Text(message).font(.callout)
                Button { model.message = nil } label: { Image(systemName:"xmark") }
            }
            .padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).shadow(radius:8)
            .padding().frame(maxWidth:750)
        }
    }
    @ViewBuilder private var dropHighlight: some View {
        if dropTargeted {
            RoundedRectangle(cornerRadius:20).stroke(.indigo,lineWidth:5).padding(8).allowsHitTesting(false)
        }
    }
    private func openHit(_ hit:SearchHit) {
        model.select(hit.lectureID)
        if model.current?.id == hit.lectureID { Task { await model.seek(hit.segment.start) } }
    }
    private func importFiles(_ result:Result<[URL],Error>) {
        switch result {
        case .success(let urls): Task { for url in urls { await model.importFile(url) } }
        case .failure(let error): model.error = error.localizedDescription
        }
    }
    private func restoreFiles(_ result:Result<[URL],Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first { Task { await restorePackage(url) } }
        case .failure(let error): model.error = error.localizedDescription
        }
    }
    private func restorePackage(_ url:URL) async {
        await model.restoreBackup(url)
    }
    private func receiveDrop(_ providers:[NSItemProvider]) -> Bool {
        guard model.current != nil else { model.error = "Crea o apri una lezione prima di importare."; return false }
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier:UTType.pdf.identifier) { url,error in
                guard let url else { Task { @MainActor in model.error = error?.localizedDescription }; return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
                do { try FileManager.default.copyItem(at:url,to:copy); Task { @MainActor in await model.importFile(copy) } }
                catch { Task { @MainActor in model.error = error.localizedDescription } }
            }; return true
        }
        if provider.canLoadObject(ofClass:UIImage.self) {
            _ = provider.loadObject(ofClass:UIImage.self) { object,error in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in await model.addImage(image) }
            }; return true
        }
        provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,error in
            var url = item as? URL
            if let data = item as? Data { url = URL(dataRepresentation:data,relativeTo:nil) }
            if let url { Task { @MainActor in await model.importFile(url) } }
        }
        return true
    }
}

@MainActor private struct SearchResultLabel: View {
    var hit: SearchHit
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(hit.lectureTitle).font(.caption.bold()).foregroundStyle(.indigo)
            Text(hit.segment.displayText).lineLimit(3).font(.subheadline)
            Text(Timeline.format(hit.segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

@MainActor private struct LectureRow: View {
    var lecture: Lecture; var selected: Bool
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            Image(systemName:"waveform").foregroundStyle(selected ? Color.white : Color.indigo).padding(9)
                .background(selected ? Color.indigo : Color.indigo.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:5) {
                Text(lecture.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(lecture.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                Text(Timeline.format(lecture.duration)+" · \(lecture.pages.count) pagine").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            if lecture.favorite { Image(systemName:"star.fill").foregroundStyle(.yellow).font(.caption) }
        }.padding(.vertical,6).contentShape(Rectangle())
    }
}

@MainActor struct NewLectureView: View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subject = "Matematica"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titolo della lezione",text:$title)
                Picker("Materia",selection:$subject) {
                    ForEach(["Matematica","Fisica","Chimica","Filosofia","Storia","Italiano","Inglese","Scienze","Arte","Informatica","Altro"],id:\.self) { Text($0) }
                }
                Section { Text("Audio, trascrizione e appunti vengono salvati localmente. Nessun audio viene caricato su un server.").font(.callout).foregroundStyle(.secondary) }
            }
            .navigationTitle("Nuova lezione")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Crea") { model.create(title:title,subject:subject); dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }.presentationDetents([.medium])
    }
}
