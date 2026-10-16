import SwiftUI

@main @MainActor struct ClassNoteAIApp: App {
    @AppStorage("appearance") private var appearance = "system"
    init() { print("[ClassNote 0.3.0] App entry point initialized") }
    var body: some Scene {
        WindowGroup {
            BootstrapView().preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}
@MainActor struct BootstrapView: View {
    @State private var model: AppModel?
    @State private var failure: String?
    @State private var loading = false
    @State private var phase = "Pronto per aprire l’archivio locale"
    var body: some View {
        Group {
            if let model { RootView().environmentObject(model) }
            else { startupScreen }
        }
        .onAppear { print("[ClassNote 0.3.0] Bootstrap appeared") }
        #if !CLASSNOTE_PLAYGROUND
        .task { if model == nil { await load() } }
        #endif
    }
    private var startupScreen: some View {
        VStack(spacing:20) {
            Image(systemName:"waveform.and.mic").font(.system(size:52)).foregroundStyle(.indigo)
            Text("ClassNote AI").font(.largeTitle.bold())
            Text("Versione 0.3.0").font(.caption).foregroundStyle(.secondary)
            Text(phase).multilineTextAlignment(.center)
            if loading { ProgressView() }
            if let failure {
                Text("Archivio non disponibile").font(.headline)
                Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Button(failure == nil ? "Apri ClassNote" : "Riprova") {
                Task { await load() }
            }.buttonStyle(.borderedProminent).disabled(loading)
            Text("Audio e appunti restano sul dispositivo.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background(Color(uiColor:.systemBackground))
    }
    private func load() async {
        guard !loading else { return }
        loading = true; failure = nil
        defer { loading = false }
        phase = "Apertura dell’archivio…"
        print("[ClassNote 0.3.0] Opening persistent store")
        do {
            // Filesystem and SQLite setup must not block drawing the startup screen.
            let store = try await Task.detached(priority:.userInitiated) { try LectureStore() }.value
            phase = "Preparazione delle lezioni…"
            print("[ClassNote 0.3.0] Store ready; initializing app model")
            await Task.yield()
            model = try AppModel(store:store)
            print("[ClassNote 0.3.0] Model ready; opening workspace")
        } catch {
            failure = error.localizedDescription
            phase = "Impossibile aprire l’archivio"
            print("[ClassNote 0.3.0] Startup error: \(error.localizedDescription)")
        }
    }
}
