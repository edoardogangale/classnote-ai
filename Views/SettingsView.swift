import SwiftUI

@MainActor struct SettingsView: View {
    @EnvironmentObject private var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section("Trascrizione locale") {
                    Picker("Motore",selection:$model.engine) {
                        Text(SpeechEngine.apple.rawValue).tag(SpeechEngine.apple)
                        if WhisperTranscriber.included { Text(SpeechEngine.whisper.rawValue).tag(SpeechEngine.whisper) }
                    }
                        .disabled(model.capture.recording || model.capture.paused)
                    Picker("Lingua",selection:$model.locale) {
                        Text("Italiano").tag("it-IT"); Text("English").tag("en-US")
                        if model.engine == .whisper { Text("Automatica multilingue").tag("auto") }
                    }
                        .disabled(model.capture.recording || model.capture.paused)
                    Text("Apple offline funziona solo se lingua e dispositivo lo supportano. Non viene attivato un servizio remoto in caso di indisponibilità.").font(.caption).foregroundStyle(.secondary)
                    if WhisperTranscriber.included {
                        Text("Whisper aggiorna il testo dopo ogni blocco di circa 12 secondi, più il tempo di calcolo. La latenza dipende dall’iPad.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if WhisperTranscriber.included { WhisperSettings(whisper:model.whisper) }
                Section("Termini tecnici · uno per riga") { TextEditor(text:$model.glossary).frame(height:140) }
                Section("Audio") {
                    Toggle("Riduzione rumore / voce",isOn:Binding(get:{model.capture.noiseReduction},set:{model.capture.noiseReduction = $0}))
                        .disabled(model.capture.recording || model.capture.paused)
                    Text("Il trattamento vocale può cambiare il timbro e non migliora tutte le aule. Effettua una prova con il microfono che userai.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Aspetto") {
                    Picker("Tema",selection:$appearance) { Text("Sistema").tag("system"); Text("Chiaro").tag("light"); Text("Scuro").tag("dark") }
                }
                Section("Dati e privacy") {
                    Label("Audio e appunti sul dispositivo",systemImage:"lock.shield")
                    Text("Non ci sono account, analytics, pubblicità o invii a server di trascrizione. Il download di Whisper contatta il repository del modello. Salva i backup da te, anche su iCloud Drive, con Esporta Backup.")
                    Text("La cancellazione dall’app rimuove i file locali; copie esportate o backup vanno gestiti separatamente.")
                    if WhisperTranscriber.included {
                        Button("Trascrivi blocchi mancanti con Whisper") { Task { await model.transcribeMissing() } }
                        .disabled(model.current == nil || model.capture.recording || model.capture.paused)
                        Button("Ritrascrivi con Whisper e proponi correzioni") { Task { await model.transcribeMissing(includeConfirmed:true) } }
                        .disabled(model.current == nil || model.capture.recording || model.capture.paused || model.pendingCount > 0)
                    }
                    Text("Apple Intelligence locale: \(LocalStudyService.generativeAvailable ? "disponibile" : "non disponibile")").font(.caption)
                }.font(.callout)
                #if CLASSNOTE_PLAYGROUND
                Section("Avvio da Swift Playground") {
                    Text("Avvia con ▶ Esegui app, nella finestra dell’app. Questa edizione usa Apple Speech offline e non richiede pacchetti o modelli da scaricare nel progetto.")
                    Text("Prima di una lezione prova microfono, parole toccabili e Apple Pencil. Registrazione e trascrizione mentre Goodnotes è in primo piano o a schermo bloccato non sono state verificate in Swift Playground. Per la prova iniziale tieni ClassNote visibile.")
                    Text("Esporta un backup prima di sostituire o cancellare il progetto. L’avvio da Swift Playground non equivale alla distribuzione di un’app autonoma dall’App Store.")
                }.font(.caption)
                #endif
                Section("Installazione di sviluppo") { Text("Questa versione deve superare i test su iPad prima di essere usata come unica registrazione di una lezione. Consulta README e docs/TESTING.md nel progetto.").font(.caption) }
            }.navigationTitle("Impostazioni").toolbar { Button("Fine") { dismiss() } }
        }
    }
}
@MainActor private struct WhisperSettings: View {
    @EnvironmentObject private var model:AppModel
    @ObservedObject var whisper:WhisperTranscriber
    var body: some View {
        Section("Whisper · modelli gratuiti") {
            Picker("Modello",selection:$model.modelName) {
                Text("Small multilingue · più leggero").tag("openai_whisper-small")
                Text("Large v3 Turbo · più impegnativo").tag("openai_whisper-large-v3-v20240930_turbo")
            }.disabled(whisper.busy || model.capture.recording || model.pendingCount > 0)
            Text(whisper.status).font(.caption)
            if whisper.busy { ProgressView(value:whisper.progress) }
            Button("Scarica / carica modello selezionato") {
                Task { do { try await whisper.prepare(model:model.modelName,allowDownload:true) } catch { model.error = error.localizedDescription } }
            }.disabled(!WhisperTranscriber.included || whisper.busy || model.capture.recording || model.pendingCount > 0)
            if !WhisperTranscriber.included { Text("WhisperKit è nello schema Xcode ClassNoteAIWhisper. Questa build usa Apple Speech.").font(.caption).foregroundStyle(.secondary) }
            Text("Download iniziale di centinaia di MB o più, a seconda della variante. Nessun audio viene caricato. Per usare l’app senza rete prepara prima il modello e fai una prova in modalità aereo.").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of:model.modelName) { _,_ in whisper.clearModel() }
    }
}
