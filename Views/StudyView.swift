import SwiftUI
import ClassNoteCore

@MainActor struct StudyView: View {
    @EnvironmentObject private var model:AppModel
    @State private var question = ""
    @State private var revealed:Set<UUID> = []
    @State private var filterDue = true
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:8) {
                    Label("Ritrova il filo della lezione",systemImage:"sparkles").font(.title3.bold())
                    Text(LocalStudyService.generativeAvailable ? "AI locale disponibile. Le risposte generate vanno verificate con le fonti." : "Modalità offline estrattiva: citazioni dalla trascrizione. Per generare spiegazioni serve Apple Intelligence compatibile e attiva.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Cosa ha detto sui limiti?",text:$question,axis:.vertical).textFieldStyle(.roundedBorder)
                        Button { Task { await model.generate(question,query:question) }; question = "" } label: { Image(systemName:"arrow.up.circle.fill").font(.title2) }
                            .disabled(question.isEmpty || model.processing)
                    }
                }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:8) {
                    ForEach(["Riassunto breve","Appunti strutturati","Definizioni","Formule citate","Esempi spiegati","Domande per interrogazione","Punti poco chiari","Schema concettuale"],id:\.self) { task in
                        Button(task) { Task { await model.generate(task) } }.buttonStyle(.bordered).font(.caption).disabled(model.processing)
                    }
                    Button("Compiti assegnati") { Task { await model.generate("Elenca solo i compiti esplicitamente assegnati nelle fonti",query:"compiti esercizi assegnati consegna casa") } }.buttonStyle(.bordered).font(.caption)
                }
                HStack {
                    Button("Crea flashcard",systemImage:"rectangle.on.rectangle") { model.makeCards() }
                    Button("Suggerisci capitoli",systemImage:"list.bullet.indent") { model.makeChapters() }
                }.buttonStyle(.bordered).font(.caption)
                Button("Confronta con la lezione precedente",systemImage:"arrow.left.arrow.right") { Task { await model.generate("Confronta con la lezione precedente: evidenzia riprese e nuovi argomenti citando le fonti") } }
                    .font(.caption).disabled(model.processing)
                if let current = model.current {
                    if !current.bookmarks.isEmpty {
                        VStack(alignment:.leading,spacing:10) {
                            Text("Segnalibri e capitoli").font(.headline)
                            ForEach(current.bookmarks.sorted(by:{$0.time < $1.time})) { bookmark in
                                HStack {
                                    Button { Task { await model.seek(bookmark.time) } } label: {
                                        HStack(alignment:.top) { Text(Timeline.format(bookmark.time)).monospacedDigit(); Text(bookmark.title).lineLimit(2) }
                                    }.font(.caption)
                                    Spacer()
                                    Button { model.current?.bookmarks.removeAll { $0.id == bookmark.id }; model.persist() } label: { Image(systemName:"xmark") }.font(.caption)
                                }
                            }
                        }.padding(14).background(.background,in:RoundedRectangle(cornerRadius:14))
                    }
                    ForEach(current.artifacts.reversed()) { artifact in
                        VStack(alignment:.leading,spacing:10) {
                            HStack(alignment:.top) {
                                VStack(alignment:.leading) {
                                    Text(artifact.title).font(.headline)
                                    Text(artifact.generated ? "Contenuto generato da AI · da verificare" : "Estratti originali · selezione automatica").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { model.share = SharePayload(items:[artifact.title+"\n\n"+artifact.text]) } label: { Image(systemName:"square.and.arrow.up") }
                                Button { model.current?.artifacts.removeAll { $0.id == artifact.id }; model.persist() } label: { Image(systemName:"trash") }
                            }
                            Text(artifact.text).font(.callout).textSelection(.enabled)
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(artifact.references) { ref in
                                        Button("\(ref.lectureTitle) · \(Timeline.format(ref.time))") {
                                            if model.current?.id != ref.lectureID { model.select(ref.lectureID) }
                                            if model.current?.id == ref.lectureID { Task { await model.seek(ref.time) } }
                                        }.buttonStyle(.bordered).font(.caption)
                                    }
                                }
                            }
                        }.padding(14).background(.background,in:RoundedRectangle(cornerRadius:14))
                    }
                    if !current.cards.isEmpty {
                        HStack { Text("Flashcard e autoverifica").font(.headline); Spacer(); Toggle("In scadenza",isOn:$filterDue).font(.caption).fixedSize() }
                        ForEach(current.cards.filter { !filterDue || $0.due <= Date() }) { card in
                            VStack(alignment:.leading,spacing:10) {
                                Text(card.question).font(.subheadline.bold())
                                if revealed.contains(card.id) {
                                    Text(card.answer).font(.callout)
                                    Button("Ascolta fonte · \(Timeline.format(card.time))") { Task { await model.seek(card.time) } }.font(.caption)
                                    HStack {
                                        Button("Da ripassare") { model.reviewCard(card.id,remembered:false); revealed.remove(card.id) }
                                        Button("Ricordavo") { model.reviewCard(card.id,remembered:true); revealed.remove(card.id) }
                                    }.buttonStyle(.bordered).font(.caption)
                                } else { Button("Mostra risposta") { revealed.insert(card.id) }.font(.caption) }
                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:14))
                        }
                    }
                }
            }.padding(16)
        }
    }
}
