# ClassNote AI · iPad

Sorgenti nativi Swift/SwiftUI per registrare una lezione, trascriverla sul dispositivo, riascoltare una parola e scrivere appunti PencilKit collegati all’audio.

**Consegna nativa per GitHub e Windows 0.3.0 — 16 ottobre 2026.** Include una procedura di compilazione nativa con GitHub Actions e confezionamento IPA per la successiva firma personale da Windows. La compilazione dell’app Apple e le prove su iPad restano da eseguire: in questo ambiente sono stati compilati e testati soltanto il pacchetto Swift portabile e la sintassi dei sorgenti. Non è un prodotto già validato per l’uso in produzione e non viene fornito un IPA firmato.

## Inizia da Windows

Leggi **[INIZIA_QUI_WINDOWS.md](INIZIA_QUI_WINDOWS.md)**. Questo archivio va caricato nella radice di un repository GitHub pubblico. La cartella `.github` contiene **Build iPad IPA**, che compila con Xcode sul runner macOS, esegue i test e, soltanto se tutto passa, pubblica l’artifact `ClassNoteAI-IPA`. Anche in caso di errore prova a salvare `ClassNoteAI-logs`.

Non occorrono Secrets o credenziali Apple nella compilazione. Dopo una build verde, la firma personale avviene con AltStore Classic/AltServer sul PC Windows e l’account Apple gratuito. La firma scade dopo sette giorni e va rinnovata. L’IPA reale, la firma e il comportamento sul dispositivo devono ancora essere verificati. Se il repository è privato, il job macOS è impostato per saltare l’esecuzione: usa la visibilità pubblica per questo percorso gratuito.

L’archivio GitHub non include il pacchetto generato per Swift Playground, che ha mostrato problemi di avvio nell’ambiente dell’utente. Conserva i sorgenti e i generatori; questa consegna usa il progetto Xcode nativo e non richiede Playground.

## Parti principali

| Percorso | Contenuto |
| --- | --- |
| `ClassNoteAI.xcodeproj` | App nativa, Apple Speech offline, nessun pacchetto remoto obbligatorio |
| `ClassNoteAIWhisper.xcodeproj` | Stessa app con WhisperKit 0.9.0, dipendenza esplicita e riproducibile |
| `Packages/ClassNoteCore` | Modelli dati, timeline, allineamento delle revisioni, ricerca, flashcard e test Swift |
| `Audio` | Acquisizione AVAudioEngine, journal, riproduzione, importazione ed esportazione M4A |
| `Notebook` | PencilKit, metadati per tratto, editor LaTeX e anteprima KaTeX locale |
| `Documents` | Import/export PDF, File, OCR, scansione e condivisione |
| `Study` | Ricerca semantica opzionale e generazione locale con Foundation Models |
| `docs` | Installazione, limiti, ricerca sui modelli, Goodnotes e verifica |

## Percorso alternativo con Mac e Xcode

1. Estrai l’intera cartella su un **Mac con Xcode compatibile con il tuo iPadOS**. Per il percorso base servono SDK iOS 17 o successivi; per Foundation Models serve un SDK che includa il framework, normalmente Xcode 26 o successivo.
2. Apri `ClassNoteAI.xcodeproj`. Scegli lo schema `ClassNoteAI`.
3. In **Signing & Capabilities** scegli il tuo Team Apple e, se necessario, un Bundle Identifier univoco. Il progetto non contiene certificati o credenziali.
4. Collega l’iPad, autorizza il computer, abilita Developer Mode se richiesto dal sistema e seleziona l’iPad come destinazione. Premi **Run**.
5. Crea una lezione. Premi **Registra**, conferma di avere le autorizzazioni necessarie e concedi microfono e riconoscimento vocale.
6. Parla, attendi il testo e tocca una parola. L’app mette in pausa la registrazione e avvia il riascolto. Con Apple Pencil scrivi nel quaderno; usa il dito per toccare un tratto e richiamare il suo audio.

Xcode può richiedere modifiche di compatibilità rilevate dalla prima compilazione Apple: questa build non è stata eseguita qui. Vedi [INSTALLAZIONE.md](docs/INSTALLAZIONE.md) per i passaggi completi e la verifica sul simulatore.

## Trascrizione

**Apple offline** è l’opzione iniziale: il codice verifica supporto e disponibilità, poi impone `requiresOnDeviceRecognition = true`. Quando manca il supporto, salva l’audio e informa l’utente; non passa automaticamente a un servizio cloud. Una richiesta copre un blocco audio di circa 12 secondi e produce risultati provvisori durante il blocco.

**Whisper** richiede il progetto `ClassNoteAIWhisper.xcodeproj` e il pulsante **Scarica / carica modello selezionato** nelle impostazioni. Include l’adattatore Core ML realmente collegato a WhisperKit, timestamp di parola e lingua italiana, inglese o automatica. Il modello predefinito è `openai_whisper-small`; Large v3 Turbo è selezionabile per iPad più capaci. I pesi non sono inclusi nell’archivio. Modello e tokenizer vanno preparati prima di lavorare offline.

Whisper in questa versione aggiorna il testo a blocchi: la latenza minima è circa 12 secondi, più il calcolo. Non viene presentato come streaming parola per parola. I confini fra blocchi possono ridurre l’accuratezza delle parole spezzate. Prestazioni, consumi e precisione non sono ancora misurati su iPad.

## Quaderno e Goodnotes

PencilKit offre penna, matita, evidenziatore, gomma, lazo, colori e spessori. I fogli sono bianchi, rigati o quadrettati; lo zoom è nativo. I tratti mantengono un collegamento temporale quando sono creati durante la registrazione. In pausa o prima di registrare non viene inventato un timestamp. Immagini, testo, OCR e formule hanno percorsi dedicati; i PDF importati sono consultati nel pannello Goodnotes/documenti.

Il flusso Goodnotes usa **Condividi, PDF, File e drag and drop**. Importando una nuova versione con **Aggiorna questo PDF**, l’identità del documento resta la stessa. Un hash evita duplicazioni identiche. Dopo un aggiornamento le associazioni pagina-audio devono essere riconfermate, perché l’ordine delle pagine potrebbe essere cambiato.

Non è implementata una sincronizzazione diretta dei tratti Goodnotes. Le fonti ufficiali consultate non hanno fornito un’API pubblica documentata da usare per ottenere modifiche e timestamp dei tratti. I PDF non trasferiscono la registrazione Goodnotes. Vedi [GOODNOTES.md](docs/GOODNOTES.md), con fonti e procedura.

## Studio e AI

Senza modelli generativi l’app produce **estratti testuali** con riferimenti all’audio, flashcard, ripasso dilazionato, capitoli euristici e risultati di ricerca. Le risposte delle flashcard rimangono citazioni del testo; non sono definizioni inventate. Il campo chat recupera fonti pertinenti alla domanda, anche per un minuto indicato esplicitamente.

Con Foundation Models e un iPad compatibile con Apple Intelligence attiva, genera riassunti, appunti, schemi e proposte di correzione localmente. L’output resta indicato come generato e da verificare. I riferimenti proposti dal modello vengono validati prima di mostrarli. Il contesto è limitato a un massimo di dieci passaggi selezionati, non all’intera lezione di più ore: il “riassunto completo” esaustivo richiede ancora un’elaborazione gerarchica. È disponibile il confronto con la precedente lezione della stessa materia.

Le correzioni richiedono conferma e conservano sempre l’originale. I token modificati senza corrispondenza perdono il timestamp della parola e rimandano al segmento. **Non è incluso un forced aligner acustico** per riallineare parole nuove.

## Verifica e stato

**17 test Swift del nucleo eseguiti, 0 errori.** Verificati anche sintassi Swift, struttura dei due progetti Xcode, plist, risorse e KaTeX locale. Il log è in `docs/verification/swift-core-tests.log`. Cinque test di integrazione Apple sono forniti ma non eseguiti. Non sono stati effettuati test con microfono, Pencil, Goodnotes, background o registrazioni di ore.

Su Mac:

```bash
python3 scripts/check_project.py
swift test --jobs 1 --package-path Packages/ClassNoteCore
bash scripts/verify_on_mac.sh
```

La workflow GitHub Actions è inclusa come configurazione da attivare nel proprio repository; non è stata eseguita e non costituisce un risultato di verifica.

Consulta [STATO_FUNZIONI.md](docs/STATO_FUNZIONI.md) per la distinzione fra codice implementato, integrazioni condizionali e lavoro ancora necessario. Il prossimo passaggio concreto è la compilazione Xcode su GitHub Actions, seguita dalla firma personale su Windows e da una prova breve su iPad. I test Apple automatizzati sono predisposti per Xcode.
