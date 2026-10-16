# Test e verifica

## Eseguiti in questo ambiente

Host Linux x86_64. Toolchain Swift 6.0.3 ufficiale, modalità linguistica Swift 5 del pacchetto. Un primo avvio parallelo del compilatore ha terminato con un errore del runtime dell’ambiente; il comando con un singolo job e sandbox del package disattivata ha poi compilato e completato i test.

```bash
swift test --disable-sandbox --jobs 1 --package-path Packages/ClassNoteCore
```

Risultato: **17 test XCTest, zero errori**, dopo la modifica finale del nucleo. Il log completo è in `verification/swift-core-tests.log`. La riga finale “Testing Library … 0 tests” appartiene al runner Swift Testing, che non contiene test: non sostituisce i 17 XCTest riportati immediatamente sopra.

| Area | Verifica effettiva |
| --- | --- |
| Timeline | Confini fra blocchi, fine registrazione, valori non validi, 1.200 blocchi / 4 ore simulate |
| Pause e inchiostro | Date dentro/fuori dalle finestre di registrazione; nessun tempo assegnato durante la pausa |
| Link | Round trip UUID/tempo e rifiuto di schemi/tempi errati |
| Correzioni | Originale conservato, punteggiatura, parole inserite/sostituite, ripetizioni, revisioni parziali e modifiche grandi |
| Ricerca/estratti | Solo fonti reali, nessun risultato inventato per query assente, risposta flashcard testuale |
| Ripasso | Avanzamento degli intervalli e reset |
| Documenti | Identità stabile dopo nuova versione; associazioni da riconfermare |
| Confronto lezioni | Riferimenti a lezione, segmento e tempo preservati dal salvataggio JSON |

Altri controlli eseguiti: parsing dei sorgenti con il frontend Swift, parsing OpenStep dei progetti, XML degli schemi, plist, presenza dei file e risorse matematiche. `scripts/check_project.py` verifica la struttura in modo portabile. Questi controlli **non** eseguono type checking contro UIKit/SwiftUI/AVFoundation e **non** dimostrano che l’app Apple compili.

## Test forniti ma non eseguiti

`Tests/AppleIntegrationTests.swift` contiene cinque XCTest per persistenza incrementale e cancellazione, round trip PencilKit, recupero da un sidecar con audio sintetico, PDF con link e backup/ripristino con validazione dei path. Anche il test del recupero usa un file sintetico creato dal test: non simula da solo ogni variante di crash del processo.

La workflow `apple-validation.yml` e lo script `verify_on_mac.sh` permettono di compilare e avviare questi test su un ambiente Apple. Non è stata avviata alcuna workflow remota.

## Piano dispositivo ancora da eseguire

| Prova | Procedura / criterio proposto | Risultato |
| --- | --- | --- |
| Live 10 minuti | Italiano e inglese; confronto con annotazione manuale; salvataggio dopo stop/riapertura | Non eseguito |
| Registrazione di 2–4 ore | Controllare durata da frame, assenza di blocchi persi, spazio e temperatura | Non eseguito |
| Parola-audio | Creare impulsi/frasi con riferimenti noti; misurare errore mediano e percentile 95 dei tempi | Non eseguito |
| Finestra ASR | Parlare attraversando i confini dei blocchi; verificare parole tagliate e duplicazioni | Non eseguito |
| Pausa/ripresa ripetuta | Dieci pause di durata diversa; verificare che non appaiano silenzi artificiali | Non eseguito |
| Riproduzione | Tap parola/frase, velocità, A–B, transizioni fra CAF ed export clip | Non eseguito |
| Pencil | Tratti, lazo, gomma parziale, undo/redo, zoom e tap; controllare la corrispondenza dei metadati | Non eseguito |
| Multitasking | Goodnotes accanto e poi a tutto schermo; schermo bloccato; ritorno a ClassNote | Non eseguito |
| Goodnotes PDF | Import, aggiornamento stesso documento, riconferma pagine, share, drop, link custom URI | Non eseguito |
| Interruzioni | Cuffie/Bluetooth, chiamata/allarme, permessi negati e microfono indisponibile | Non eseguito |
| Crash/recovery | Chiudere durante una scrittura, riaprire, confrontare CAF e sidecar e controllare i dati conservati | Non eseguito |
| Spazio insufficiente | Verificare stop sotto soglia, avviso e dati già registrati | Non eseguito |
| Offline | Dopo preparazione modelli/tokenizer, modalità aereo con registrazione e generazione supportata | Non eseguito |
| AI locale | Controllare citazioni, errori/ambiguità, contesto insufficiente e indisponibilità del modello | Non eseguito |
| PDF lungo | Testo e riassunti multipagina senza perdita, immagini, note, pagine importate e link | Non eseguito |
| Backup | Copia su File/iCloud Drive, ripristino in contenitore vuoto, confronto file e metadati | Non eseguito |

Le soglie numeriche di accettazione di WER, memoria e batteria vanno definite dopo una misura iniziale su almeno un iPad reale. Non vengono dichiarate raggiunte in questa consegna.
