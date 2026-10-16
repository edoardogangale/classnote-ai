import SwiftUI
import WebKit

/// KaTeX is bundled locally, including fonts. The web view cannot navigate to remote origins.
@MainActor struct MathPreview: UIViewRepresentable {
    var latex: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context:Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear
        context.coordinator.view = view; context.coordinator.latex = latex
        if let url = MathResources.htmlURL {
            view.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<p>Risorse matematiche non trovate. Il sorgente LaTeX resta disponibile nell’editor.</p>",baseURL:nil)
        }
        return view
    }
    func updateUIView(_ view:WKWebView,context:Context) { context.coordinator.latex = latex; context.coordinator.render() }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        weak var view:WKWebView?; var latex = ""; var ready = false
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { ready = true; render() }
        func render() {
            guard ready, let data = try? JSONSerialization.data(withJSONObject:[latex]),
                  let json = String(data:data,encoding:.utf8) else { return }
            view?.evaluateJavaScript("renderFormula(\(json)[0]);")
        }
        func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}

/// Swift Playground may compile resources without generating Bundle.module.
/// Locate the actual bundled files with Foundation APIs instead of relying on that accessor.
enum MathResources {
    static var htmlURL: URL? {
        let manager = FileManager.default
        var bundles = [Bundle.main] + Bundle.allBundles
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for root in roots {
            let children = (try? manager.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
            for child in children where child.pathExtension == "bundle" {
                if let bundle = Bundle(url:child) { bundles.append(bundle) }
            }
        }
        for bundle in bundles {
            for folder in ["Math", "Resources/Math", "App/Resources/Math"] {
                if let url = bundle.url(forResource:"math",withExtension:"html",subdirectory:folder) { return url }
            }
        }
        return nil
    }
}

@MainActor struct FormulaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var latex = "\\lim_{x\\to 0}\\frac{\\sin x}{x}=1"
    @State private var spoken = ""
    var onInsert: (String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Sorgente LaTeX da verificare") { TextEditor(text:$latex).font(.system(.body,design:.monospaced)).frame(height:140) }
                Section("Anteprima locale") { MathPreview(latex:latex).frame(height:180) }
                Section("Conversione guidata di simboli pronunciati") {
                    TextField("es. x al quadrato più y uguale 2",text:$spoken,axis:.vertical)
                    Button("Proponi simboli") { latex = SpokenSymbols.convert(spoken) }
                    Text("Conversione limitata a simboli espliciti. Non interpreta formule ambigue, grafici o stechiometria: confronta sempre con l’audio.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Formula")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Inserisci") { onInsert(latex); dismiss() } }
                }
        }
    }
}
enum SpokenSymbols {
    static func convert(_ text:String) -> String {
        var output = text.lowercased()
        let replacements = [("al quadrato","^{2}"),("al cubo","^{3}"),("uguale","="),("più","+"),("meno","-"),
                            ("moltiplicato per","\\cdot"),("diviso","/"),("alfa","\\alpha"),("beta","\\beta"),
                            ("gamma","\\gamma"),("delta","\\Delta"),("omega","\\omega"),("infinito","\\infty")]
        for (source,target) in replacements {
            guard let expression = try? NSRegularExpression(pattern:"\\b"+NSRegularExpression.escapedPattern(for:source)+"\\b") else { continue }
            output = expression.stringByReplacingMatches(in:output,range:NSRange(output.startIndex...,in:output),
                                                        withTemplate:NSRegularExpression.escapedTemplate(for:target))
        }
        return output
    }
}
