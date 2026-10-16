import SwiftUI
import ClassNoteCore

@MainActor struct TranscriptView: View {
    @EnvironmentObject private var model:AppModel
    @State private var query = ""
    @State private var editing: TranscriptSegment?
    @State private var follow = true
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Label("Trascrizione",systemImage:"text.alignleft").font(.headline)
                Spacer()
                Toggle("Segui",isOn:$follow).font(.caption).fixedSize()
            }.padding(16)
            HStack {
                Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                TextField("Trova una parola…",text:$query).textInputAutocapitalization(.never)
            }.padding(10).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:10)).padding(.horizontal,12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:16) {
                        if model.segments.isEmpty {
                            ContentUnavailableView("Le parole appariranno qui",systemImage:"waveform",description:Text("Avvia la registrazione. In grigio trovi le parole provvisorie; sottolineate in arancione quelle incerte."))
                                .padding(.top,40)
                        }
                        ForEach(model.segments.filter { query.isEmpty || $0.displayText.localizedCaseInsensitiveContains(query) }) { segment in
                            TranscriptRow(segment:segment,player:model.player,onEdit:{editing = segment})
                                .id(segment.id)
                        }
                    }.padding(16)
                }.onChange(of:model.segments.last?.displayText) { _,_ in
                    if follow, query.isEmpty, let id = model.segments.last?.id { withAnimation { proxy.scrollTo(id,anchor:.bottom) } }
                }
            }
            Text("I timestamp sono stime del riconoscitore. Le correzioni non allineate aprono l’inizio del segmento.")
                .font(.caption2).foregroundStyle(.secondary).padding(12)
        }
        .background(Color(uiColor:.systemBackground))
        .sheet(item:$editing) { CorrectionEditor(segment:$0) }
    }
}

@MainActor private struct TranscriptRow: View {
    @EnvironmentObject private var model:AppModel
    var segment: TranscriptSegment
    @ObservedObject var player:LecturePlayer
    var onEdit: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Button { Task { await model.seek(segment.start) } } label: {
                    Label(Timeline.format(segment.start),systemImage:"play.fill").font(.system(.caption,design:.monospaced))
                }.buttonStyle(.plain).foregroundStyle(.indigo)
                if !segment.finalized { Text("provvisorio").font(.caption2).foregroundStyle(.secondary) }
                if segment.corrected != nil { Text("corretto").font(.caption2).foregroundStyle(.teal) }
                if segment.correctionProposal != nil { Text("proposta").font(.caption2).foregroundStyle(.orange) }
                Spacer()
                Menu {
                    Button("Ascolta frase") { Task { await model.seek(segment.start) } }
                    Button("Modifica / confronta originale",action:onEdit)
                    Button("Ripeti questo segmento") { player.loopStart = segment.start; player.loopEnd = segment.end; Task { await model.seek(segment.start) } }
                    Button("Segnalibro") { model.current?.bookmarks.append(TimeBookmark(title:String(segment.displayText.prefix(60)),time:segment.start)); model.persist() }
                } label: { Image(systemName:"ellipsis").padding(4) }
            }
            if segment.displayWords.isEmpty {
                Button(segment.displayText) { Task { await model.seek(segment.start) } }.buttonStyle(.plain).multilineTextAlignment(.leading)
            } else {
                WordFlow(spacing:4) {
                    ForEach(segment.displayWords) { word in
                        let active = player.playing && word.contains(player.time)
                        let uncertain = word.alignment == .needsReview || (word.confidence.map { $0 < 0.55 } ?? false)
                        Button { Task { await model.seek(word.start ?? segment.start) } } label: {
                            Text(word.text)
                                .foregroundStyle(word.state == .provisional ? Color.secondary : Color.primary)
                                .underline(uncertain,color:.orange)
                                .padding(.vertical,3).padding(.horizontal,2)
                                .background(active ? Color.yellow.opacity(0.45) : .clear,in:RoundedRectangle(cornerRadius:4))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(word.text), \(Timeline.format(word.start ?? segment.start))\(uncertain ? ", da verificare" : "")")
                    }
                }
            }
        }.padding(14)
            .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
            .overlay(alignment:.leading) {
                if player.playing, player.time >= segment.start, player.time < segment.end {
                    RoundedRectangle(cornerRadius:2).fill(.indigo).frame(width:3).padding(.vertical,12)
                }
            }
    }
}

struct WordFlow: Layout {
    var spacing:CGFloat = 4
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        arrange(width:proposal.width ?? 350,subviews:subviews).size
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let layout = arrange(width:bounds.width,subviews:subviews)
        for (index,point) in layout.points.enumerated() {
            subviews[index].place(at:CGPoint(x:bounds.minX+point.x,y:bounds.minY+point.y),proposal:.unspecified)
        }
    }
    private func arrange(width:CGFloat,subviews:Subviews) -> (size:CGSize,points:[CGPoint]) {
        var x:CGFloat = 0; var y:CGFloat = 0; var line:CGFloat = 0; var points:[CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x+size.width > width { x = 0; y += line+spacing; line = 0 }
            points.append(CGPoint(x:x,y:y)); x += size.width+spacing; line = max(line,size.height)
        }
        return (CGSize(width:width,height:y+line),points)
    }
}

@MainActor struct CorrectionEditor: View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    var segment:TranscriptSegment
    @State private var text = ""
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Originale conservato") { Text(segment.original).textSelection(.enabled) }
                Section("Versione corretta / proposta") { TextEditor(text:$text).frame(minHeight:220) }
                Section {
                    Button(working ? "Elaborazione…" : LocalStudyService.generativeAvailable ? "Proponi correzione con AI locale" : "Normalizza spazi (offline)") {
                        working = true
                        Task {
                            do { text = try await LocalStudyService.correction(segment,subject:model.current?.subject ?? "") }
                            catch { model.error = error.localizedDescription }; working = false
                        }
                    }.disabled(working)
                    Text("Le parole cambiate perdono l’allineamento preciso. Puoi sempre riascoltare l’intero segmento e confrontare l’originale.").font(.caption).foregroundStyle(.secondary)
                    Button("Rifiuta proposta / ripristina originale",role:.destructive) {
                        var s = segment; s.restoreOriginal(); model.updateSegment(s); dismiss()
                    }
                }
            }.navigationTitle("Correzione da verificare")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Accetta") { var s = segment; s.acceptCorrection(text); model.updateSegment(s); dismiss() }.disabled(working || text.isEmpty) }
                }
                .onAppear { text = segment.correctionProposal ?? segment.displayText }
        }
    }
}
