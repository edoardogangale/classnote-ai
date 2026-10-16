# Dati, permessi e sicurezza

## Percorsi dei dati

Audio, trascrizioni, pagine e documenti vengono salvati nel contenitore Application Support dell’app. Il codice non implementa upload audio, account, pubblicità, tracking o analytics. Le due vie speech sono Apple con requisito on-device e WhisperKit locale. Foundation Models usa il modello di sistema on-device dopo un controllo di disponibilità; non è configurato un modello server.

Il download esplicito di Whisper contatta Hugging Face per modelli e tokenizer. Dopo la preparazione sono previste risorse locali. Cache incomplete/corrotte o cambi del repository possono richiedere un nuovo download; la prova offline non è stata eseguita. Nessuna chiave API commerciale è richiesta.

L’esportazione Condividi/File è un’azione dell’utente: può trasferire PDF, testo, audio o backup alla destinazione scelta, inclusa un’app/cloud. I link PDF trasportano UUID e posizione audio, non la registrazione.

## Protezione locale

I file usano `completeUntilFirstUserAuthentication`: dopo il primo sblocco possono essere scritti anche a schermo bloccato, compatibilmente con iPadOS. È un compromesso necessario per registrazioni lunghe in background. Non è una cifratura aggiuntiva con password applicativa. Il contenitore è escluso dal normale backup automatico del dispositivo dal codice; i backup dell’app sono azioni esplicite.

SQLite usa chiavi esterne, WAL, sincronizzazione completa e cancellazione sicura dei record. Eliminare una lezione rimuove anche l’intera sua directory locale e tronca il WAL. Non si promette una cancellazione forense dei blocchi flash, delle copie già esportate o dei backup esterni.

Il ripristino rifiuta identità già presenti, schema sconosciuto, symlink dei file principali/media, nomi con percorsi, file non regolari, timeline non valida e riferimenti necessari assenti. Non esegue script contenuti nel backup. L’esportazione del backup non applica una password: la riservatezza della destinazione scelta resta da valutare dall’utente.

## Permessi e ciclo di vita

Il microfono viene richiesto dopo Registra. Speech è richiesto per Apple Speech. La fotocamera serve alla scansione richiesta dall’utente; Foto usa PhotosPicker. La registrazione non viene avviata all’apertura, da un URL o da un evento in background. Dopo un’interruzione la ripresa richiede un comando esplicito.

La conferma iniziale ricorda di rispettare regole scolastiche e autorizzazioni. Non sostituisce la verifica delle regole applicabili nel proprio contesto. Non viene proposta una funzione di registrazione nascosta.

## Rendering matematico

KaTeX, CSS e font sono inclusi localmente. La WKWebView usa archivio non persistente, Content Security Policy senza connessioni remote e navigazione limitata ai file locali. `trust=false`, limiti di espansione e dati passati tramite JSON riducono l’esecuzione di comandi non previsti dalle formule.

## Manifest e audit da completare

`PrivacyInfo.xcprivacy` dichiara assenza di tracking/raccolta implementata dall’app e le ragioni per UserDefaults e controllo dello spazio. Prima di una distribuzione App Store serve verificare anche i manifest e il comportamento delle versioni effettivamente risolte delle dipendenze. Non è stato eseguito un audit di rete/hardware né un processo di review App Store.

Fonti Apple: [API e motivazioni richieste](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [manifest privacy](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
