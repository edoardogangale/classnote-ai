# Dipendenze e licenze

| Componente | Versione/percorso | Modalità | Licenza/nota |
| --- | --- | --- | --- |
| Swift/SwiftUI, AVFoundation, PencilKit, PDFKit, Vision/VisionKit, Speech, NaturalLanguage, SQLite3, WebKit | SDK Apple usato per compilare | Framework di sistema | Condizioni SDK Apple; nessuna chiave a consumo aggiunta dall’app |
| Foundation Models | Presente solo con SDK compatibile, disponibilità controllata | Generazione locale opzionale | Modello di sistema, non LLM open source redistribuito |
| ClassNoteCore | Locale `Packages/ClassNoteCore` | Entrambi i progetti | Codice della consegna, MIT |
| WhisperKit | 0.9.0, commit `a8a40c9444ae4e7263bd41e5e60b35a92e2cbba3` | Solo progetto Whisper | MIT, avviso in `WHISPERKIT-LICENSE.txt` |
| swift-transformers | 0.1.8, dipendenza fissata da WhisperKit | Risolta da SPM | Apache-2.0; verificare avvisi della versione distribuita |
| swift-argument-parser | 1.3.0, dichiarata nel package upstream | Il prodotto app è WhisperKit, non la CLI | Apache-2.0; condizioni upstream |
| Whisper Small / Large v3 Turbo | Modelli dal repository Argmax/Core ML | Download esplicito sul dispositivo | Pesi Whisper MIT; nessun peso incluso nello ZIP |
| KaTeX | 0.16.22 | JS/CSS/font locali in Resources/Math | MIT, avviso incluso `KATEX-LICENSE.txt` |

Il progetto base non contiene riferimenti SPM remoti. La prima risoluzione del progetto Whisper necessita della rete, poi si può compilare da cache compatibile. Non è incluso un `Package.resolved` inventato: Xcode deve produrlo dopo la risoluzione reale. I pesi Core ML del repository sono una risorsa esterna mutabile e non sono fissati qui con checksum di release.

KaTeX è distribuito con l’app: non usa CDN e non invia formule a un renderer remoto. I font sono quelli del pacchetto KaTeX, con il suo avviso di licenza. L’icona applicativa è un disegno geometrico generato per questo progetto.

Fonti: [WhisperKit 0.9.0 Package.swift](https://github.com/argmaxinc/WhisperKit/blob/v0.9.0/Package.swift), [swift-transformers](https://github.com/huggingface/swift-transformers), [swift-argument-parser](https://github.com/apple/swift-argument-parser), [KaTeX](https://github.com/KaTeX/KaTeX), [uso browser KaTeX](https://katex.org/docs/browser.html).
