import SwiftUI
import ClassNoteCore

@MainActor struct LectureWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane = "Quaderno"
    @State private var compactPane = "Trascrizione"
    @State private var importing = false
    @State private var consent = false
    @State private var renaming = false
    var body: some View {
        VStack(spacing:0) {
            header
            Divider()
            GeometryReader { proxy in
                if proxy.size.width >= 780 {
                    HStack(spacing:0) {
                        TranscriptView().frame(width:proxy.size.width*0.43)
                        Divider()
                        VStack(spacing:0) {
                            Picker("Spazio di lavoro",selection:$pane) {
                                ForEach(["Quaderno","Goodnotes","Studio"],id:\.self) { Text($0) }
                            }.pickerStyle(.segmented).padding(12)
                            rightPane
                        }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                } else {
                    VStack(spacing:0) {
                        Picker("Spazio di lavoro",selection:$compactPane) {
                            ForEach(["Trascrizione","Quaderno","Goodnotes","Studio"],id:\.self) { Text($0).font(.caption) }
                        }.pickerStyle(.segmented).padding(8)
                        switch compactPane {
                        case "Quaderno": NotebookView().disabled(model.processing).allowsHitTesting(!model.processing)
                        case "Goodnotes": GoodnotesView().disabled(model.processing)
                        case "Studio": StudyView().disabled(model.processing)
                        default: TranscriptView()
                        }
                    }
                }
            }
            Divider()
            TransportBar(capture:model.capture,player:model.player,onRecord:{ record() })
        }
        .background(Color(uiColor:.systemGroupedBackground))
        .navigationTitle(model.current?.title ?? "ClassNote AI").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement:.topBarTrailing) {
                Button { model.favorite() } label: { Image(systemName:model.current?.favorite == true ? "star.fill" : "star") }.accessibilityLabel("Preferita").disabled(model.processing)
                Menu {
                    Button("Modifica titolo e materia",systemImage:"pencil") { renaming = true }.disabled(model.processing)
                    Button("Importa PDF, immagine o audio",systemImage:"square.and.arrow.down") { importing = true }
                    ForEach(["PDF","TXT","Markdown","JSON","Audio","Clip","Flashcard TSV","Backup"],id:\.self) { format in
                        Button("Esporta \(format)") { Task { await model.export(format) } }
                    }
                } label: { Image(systemName:"square.and.arrow.up") }
            }
        }
        .sheet(isPresented:$consent) {
            RecordingConsentView { model.confirmConsent(); Task { await model.toggleRecording() } }
        }
        .sheet(isPresented:$renaming) { EditLectureView() }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image,.audio],allowsMultipleSelection:true) { result in
            switch result {
            case .success(let urls): Task { for url in urls { await model.importFile(url) } }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .overlay(alignment:.bottomTrailing) {
            if model.processing {
                HStack { ProgressView(); Text(model.progressText).font(.caption) }
                    .padding(12).background(.regularMaterial,in:Capsule()).padding(.bottom,160).padding(.trailing)
            }
        }
    }
    private var header: some View {
        HStack(alignment:.center,spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                Text(model.current?.subject.uppercased() ?? "LEZIONE").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.indigo)
                Text(model.current?.title ?? "").font(.title2.weight(.bold)).lineLimit(2)
            }
            Spacer()
            VStack(alignment:.trailing,spacing:5) {
                Label("Sul tuo iPad",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                Text(model.engine.rawValue).font(.caption2).foregroundStyle(.secondary)
                if model.pendingCount > 0 { Text("\(model.pendingCount) blocchi da trascrivere").font(.caption2).foregroundStyle(.orange) }
            }
        }.padding(.horizontal,20).padding(.vertical,14)
    }
    @ViewBuilder private var rightPane: some View {
        switch pane {
        case "Goodnotes": GoodnotesView().disabled(model.processing)
        case "Studio": StudyView().disabled(model.processing)
        default: NotebookView().disabled(model.processing).allowsHitTesting(!model.processing)
        }
    }
    private func record() {
        if model.consent { Task { await model.toggleRecording() } }
        else { consent = true }
    }
}

@MainActor struct TransportBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var capture: AudioCapture
    @ObservedObject var player: LecturePlayer
    var onRecord: () -> Void
    var body: some View {
        VStack(spacing:10) {
            HStack(spacing:12) {
                Circle().fill(capture.recording ? Color.red : .secondary.opacity(0.3)).frame(width:8,height:8)
                Text(capture.recording ? "REGISTRAZIONE" : capture.paused ? "IN PAUSA" : "AUDIO")
                    .font(.caption2.weight(.bold)).tracking(1)
                Text(Timeline.format(capture.recording ? capture.duration : model.current?.duration ?? 0)).font(.system(.caption,design:.monospaced))
                Waveform(levels:capture.levels,active:capture.recording).frame(maxWidth:180).frame(height:22)
                Spacer(minLength:4)
                if capture.recording { Label(capture.voiceActive ? "Voce" : "Silenzio",systemImage:"mic.fill").font(.caption).foregroundStyle(.secondary) }
                Button { model.bookmark() } label: { Image(systemName:"bookmark.badge.plus") }.help("Segnalibro")
            }
            HStack(spacing:14) {
                Button(action:onRecord) {
                    Label(capture.recording ? "Pausa" : capture.paused ? "Riprendi" : "Registra",systemImage:capture.recording ? "pause.fill" : "record.circle")
                        .font(.subheadline.weight(.semibold))
                }.buttonStyle(.borderedProminent).tint(.red).keyboardShortcut("r",modifiers:.command)
                if capture.recording || capture.paused {
                    Button { Task { await model.stopRecording() } } label: { Image(systemName:"stop.fill") }.accessibilityLabel("Termina registrazione")
                }
                Divider().frame(height:24)
                Button { Task { await model.seek(max(0,player.time-10)) } } label: { Image(systemName:"gobackward.10") }.accessibilityLabel("Indietro 10 secondi")
                Button {
                    if capture.recording { Task { await model.seek(player.time) } }
                    else { model.configurePlayer(); player.toggle() }
                } label: { Image(systemName:player.playing ? "pause.circle.fill" : "play.circle.fill").font(.title) }
                    .accessibilityLabel(player.playing ? "Pausa riproduzione" : "Riproduci")
                Text(Timeline.format(player.time)).font(.system(.caption,design:.monospaced)).frame(minWidth:44)
                Slider(value:Binding(get:{min(player.time,max(0.01,model.current?.duration ?? 0))},set:{ value in
                    Task { await model.seek(value) }
                }),in:0...max(0.01,model.current?.duration ?? 0)).accessibilityLabel("Posizione audio")
                Menu {
                    ForEach([Float(0.5),0.75,1,1.25,1.5,2],id:\.self) { rate in Button("\(rate.formatted())×") { player.rate = rate } }
                } label: { Text("\(player.rate.formatted())×").font(.caption.bold()) }
            }
            HStack(spacing:12) {
                Button("A: \(player.loopStart.map(Timeline.format) ?? "—")") { player.loopStart = player.time }
                Button("B: \(player.loopEnd.map(Timeline.format) ?? "—")") { player.loopEnd = player.time }
                if player.loopStart != nil { Button("Azzera intervallo") { player.loopStart = nil; player.loopEnd = nil } }
                Spacer()
                Text(capture.recording ? "Tocca testo o inchiostro per mettere in pausa e riascoltare." : "A–B ripete il passaggio; dal menu puoi esportare la clip.")
                    .lineLimit(1).foregroundStyle(.secondary)
            }.font(.caption2)
        }.padding(.horizontal,18).padding(.vertical,12).background(.bar)
    }
}
@MainActor private struct Waveform: View {
    var levels: [Float]; var active: Bool
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for (i,level) in levels.enumerated() {
                    let x = CGFloat(i)*proxy.size.width/CGFloat(max(1,levels.count))
                    let height = CGFloat(max(0.06,level))*proxy.size.height
                    path.move(to:CGPoint(x:x,y:(proxy.size.height-height)/2)); path.addLine(to:CGPoint(x:x,y:(proxy.size.height+height)/2))
                }
            }.stroke(active ? Color.red : Color.secondary.opacity(0.35),style:StrokeStyle(lineWidth:2,lineCap:.round))
        }.accessibilityHidden(true)
    }
}

@MainActor struct RecordingConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false
    var onAccept: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Registrazione visibile e locale",systemImage:"mic.badge.plus").font(.headline)
                    Text("Registra soltanto quando le regole scolastiche e le autorizzazioni applicabili lo consentono. Informati prima di registrare altre persone.")
                    #if CLASSNOTE_PLAYGROUND
                    Text("Prima prova ClassNote visibile. La registrazione passando a Goodnotes o bloccando lo schermo non è stata verificata nell’esecuzione da Swift Playground.")
                    #else
                    Text("La registrazione in background richiede il supporto di iPadOS. Telefonate, altre app o cambi di dispositivo audio possono interromperla: verifica il comportamento sul tuo dispositivo.")
                    #endif
                    Text("Nessun audio viene inviato a servizi di trascrizione remoti. Il riconoscimento automatico può contenere errori: verifica i passaggi importanti.")
                }
                Toggle("Confermo di avere le autorizzazioni necessarie",isOn:$accepted)
                Button("Conferma e registra") { dismiss(); onAccept() }.disabled(!accepted)
            }.navigationTitle("Prima di registrare").toolbar { Button("Chiudi") { dismiss() } }
        }.presentationDetents([.medium,.large])
    }
}

@MainActor private struct EditLectureView: View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var subject = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Titolo",text:$title); TextField("Materia",text:$subject)
                TextField("Etichette separate da virgole",text:Binding(get:{model.current?.tags.joined(separator:", ") ?? ""},set:{model.current?.tags = $0.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }; model.persist()}))
            }.navigationTitle("Dettagli lezione")
                .toolbar { Button("Salva") { model.rename(title,subject:subject); dismiss() } }
                .onAppear { title = model.current?.title ?? ""; subject = model.current?.subject ?? "" }
        }.presentationDetents([.medium])
    }
}
