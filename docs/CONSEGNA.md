# Consegna e verifica del 16 ottobre 2026

Sono forniti un progetto app playground `.swiftpm` per iPad, due progetti Xcode, i sorgenti dell’app nativa, un pacchetto Swift locale, risorse matematiche offline, test e documentazione. Non sono inclusi pesi AI, certificati, dati di lezioni personali o binari compilati.

Il flusso prioritario è implementato: acquisizione microfono, trascrizione live locale, timestamp, tap sul testo per riascoltare, quaderno PencilKit e collegamenti temporali. Le integrazioni Goodnotes usano lo scambio PDF supportato dal sistema. I percorsi audio/UI/PencilKit sono ancora da compilare e provare con SDK Apple.

## Risultati osservati

- Compilato il pacchetto ClassNoteCore con Swift 6.0.3, modalità linguistica Swift 5.
- Eseguiti 17 XCTest, zero errori, inclusa una timeline sintetica di quattro ore.
- Eseguito parsing sintattico dei sorgenti con il frontend Swift.
- Verificati i due file progetto in formato OpenStep, le risorse riferite, XML degli schemi e plist.
- Verificata la presenza di KaTeX/font/HTML locali e dell’icona RGB 1024×1024.
- Preparati cinque test Apple e una workflow, non eseguiti.

Queste verifiche non equivalgono a una build iPadOS. Non sono stati verificati accuratezza STT, registrazione reale, durata della batteria, latenza parola-audio, Apple Pencil fisica o interazione con Goodnotes installato.

## Primo passo per chi apre il progetto

Con iPad e Windows: leggere `LEGGIMI_IPAD.txt` e aprire `ClassNoteAI.swiftpm` in Swift Playground su iPad. La prima compilazione Apple è ancora da eseguire: non è dichiarato un avvio verificato. Con un Mac: aprire `ClassNoteAI.xcodeproj`, impostare Team e Bundle Identifier, compilare e avviare i test Apple. Dopo una prova breve su dispositivo, eseguire il piano di lunga durata descritto in TESTING. Per Whisper serve la variante Xcode dedicata e la preparazione del modello dalle impostazioni dell’app.

## Adattamento Swift Playground 0.2.0

- Pacchetto senza dipendenze remote, core locale, sorgenti SwiftUI/PencilKit/AVFoundation e risorse matematiche incluse.
- Permessi espliciti per microfono, Speech e fotocamera; plist aggiuntivo per audio e documenti.
- Risorse matematiche cercate nei bundle locali con le API Foundation, senza dipendere dalla generazione di `Bundle.module`.
- Interfaccia che presenta solo i motori di trascrizione effettivamente inclusi.
- Indicazioni specifiche sul background non verificato del contesto Swift Playground e sull’esportazione dei backup.
- Nessuna promessa di installazione autonoma nella Home: è un progetto eseguibile da Swift Playground, da compilare sul dispositivo.

I risultati dei controlli della conversione sono in `verification/ipad-package-checks.log` e `verification/swift-playground-core-tests.log`. Essi verificano struttura, sintassi e core portabile, non i framework Apple né il comportamento sul dispositivo.

L’elenco completo dei limiti e del lavoro ancora da completare è in STATO_FUNZIONI. In particolare, non sono presenti un forced aligner, un editor di inchiostro sovrapposto ai PDF, una sincronizzazione diretta Goodnotes, un riconoscitore strutturato di grafici/formule o un riassunto gerarchico esaustivo di intere lezioni lunghe.

## Correzione 0.2.1 dopo la prima compilazione su iPad

La prova dell’utente ha raggiunto il compilatore Apple e ha mostrato tre gruppi di errori bloccanti: callback del delegate scanner fuori dal MainActor, accessor Bundle.module non generato, espressione SwiftUI RootView troppo complessa. La compilazione non è riuscita: questa prova non costituisce un avvio verificato.

Correzioni: callback scanner che passano esplicitamente al MainActor; ricerca delle risorse con Foundation senza accessor generato; suddivisione di RootView in sottoviste ed eventi con tipi espliciti. Anche l’osservatore PDF passa al MainActor per aggiornare la pagina. Le segnalazioni gialle di deprecazione audio e Sendable dell’esportatore non sono presentate come errori bloccanti risolti.

La compilazione Apple della revisione 0.2.1 e il primo avvio restano da riprovare sul dispositivo. I controlli locali della correzione sono in verification/ipad-021-checks.log; non sono test del microfono, di PencilKit o del compilatore Apple.

## Revisione di diagnosi 0.2.2

La prova dell’utente non mostra più gli errori rossi precedenti, ma la finestra è vuota e la console non contiene messaggi. Era stato inoltre osservato un errore Prewarm su CurrentUser.txt/Documents. Il codice dell’app non crea CurrentUser.txt: la causa del problema di preparazione del contenitore non è stata accertata. Non è dichiarato alcun avvio riuscito.

Questa revisione aggiunge una schermata iniziale esplicita con versione, pulsante Apri ClassNote, fase di caricamento ed errore leggibile. In Swift Playground il caricamento inizia con quel pulsante; la preparazione SQLite viene spostata fuori dal MainActor. Messaggi di console distinguono ingresso nell’app, apparizione della schermata, apertura archivio e creazione del modello. Il pacchetto Apple espone solo il prodotto applicazione e conserva il core come target interno: questo semplifica la configurazione senza presentarlo come causa accertata della schermata vuota.

Se non appare neppure il messaggio App entry point initialized, il passo seguente è confrontare l’avvio di una nuova app vuota creata direttamente in Swift Playground con quello del progetto. La revisione 0.2.2 non è stata compilata con SDK Apple qui e resta da provare su iPad. La verifica locale è descritta in verification/ipad-022-checks.log.

## Percorso nativo gratuito Windows/GitHub 0.3.0

Consegnato un archivio pronto per la radice di un repository, senza il pacchetto Swift Playground generato. La procedura Build iPad IPA usa macOS 15 / Xcode 16.4 e non richiede Secrets o certificati Apple. Esegue controlli, test portabili, build dispositivo senza firma, confezionamento IPA, build e test di integrazione su un simulatore compatibile con l’SDK selezionato. Carica log anche in caso di fallimento e offre l’IPA solo quando i passi richiesti sono passati. Non è un workflow già eseguito.

Per il vincolo di costo, il job macOS viene saltato sui repository privati. La visibilità pubblica rende visibili i sorgenti. La configurazione non contiene lezioni personali o registrazioni. Versione nativa 0.3.0, build 5. Il TEST_HOST punta direttamente al binario nel bundle iPad.

Cinque test portabili aggiunti per confezionamento Payload, permessi eseguibili/symlink, rifiuto di bundle simulatore, validazione del percorso eseguibile e scelta del runtime compatibile. Sono basati su fixture sintetiche e non equivalgono a un IPA eseguibile. Risultati reali e controlli del workflow sono nel log verification/github-delivery-checks.log.

La prima compilazione Xcode su GitHub, i cinque test Apple, la firma gratuita con AltStore e le prove reali su iPad restano da eseguire. AltStore è un componente di terze parti e il provisioning gratuito limita le capacità disponibili; non si promette che tutte le funzioni dell’app siano già compatibili. Il rinnovo della firma deve essere gestito ogni sette giorni. Procedura dettagliata e fonti in INIZIA_QUI_WINDOWS.md.
