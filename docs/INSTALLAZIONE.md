# Compilazione e installazione

## Percorso attuale: Windows, GitHub Actions e AltStore Classic

Leggi prima [INIZIA_QUI_WINDOWS.md](../INIZIA_QUI_WINDOWS.md). L’archivio GitHub 0.3.0 contiene i sorgenti alla radice e la procedura `.github/workflows/build-ipad.yml`. Non include il pacchetto generato Swift Playground: quel percorso non ha prodotto un avvio funzionante nelle prove dell’utente e non è il metodo scelto per questa consegna.

Compilazione e test si svolgono sul runner macOS del repository pubblico, senza firma Apple. Solo dopo una build verde l’IPA viene firmato localmente con AltStore Classic e un account Apple gratuito. L’installazione e le capacità di questa app sotto provisioning gratuito restano da verificare. La firma ha durata di sette giorni e va rinnovata. Le sezioni Swift Playground seguenti documentano il percorso precedente, non i passi da eseguire adesso.

## Con Windows e iPad: Swift Playground

L’archivio include `ClassNoteAI.swiftpm`, un progetto da aprire con Swift Playground sull’iPad. Per questo percorso non serve Windows né un Mac. Usa Swift Playground aggiornato e un iPad con iPadOS 17 o successivo compatibile con l’app.

1. Salva lo ZIP nell’app File e toccalo per decomprimerlo.
2. Nella cartella estratta apri **ClassNoteAI.swiftpm** con Swift Playground. Apri il pacchetto intero, non il solo `Package.swift`. Se necessario usa Condividi o il selettore file di Swift Playground.
3. Premi **▶ Esegui app** sopra l’area del codice e attendi la prima compilazione. L’app si apre in una propria finestra: usa quella per la prova.
4. Crea una lezione, premi Registra, conferma di avere le autorizzazioni e concedi microfono e riconoscimento vocale. Se i permessi sono stati rifiutati, gestiscili dalle Impostazioni di iPadOS.
5. Fai una prova di 20–30 secondi, termina la registrazione e tocca le parole per il riascolto. Verifica anche Apple Pencil. Se l’italiano offline non è disponibile, viene conservato l’audio senza trascrizione; non viene attivato un servizio remoto.

Il pacchetto riusa gli stessi sorgenti dell’app Xcode. Dichiara microfono, riconoscimento vocale, fotocamera, risorse matematiche locali e impostazioni audio. WhisperKit non è collegato in questa edizione: non occorre scaricare modelli. Foundation Models resta condizionale al framework nell’SDK e al supporto del dispositivo.

**Prima compilazione Apple ancora da eseguire.** I controlli eseguiti qui non sostituiscono l’avvio in Swift Playground. Se la compilazione si ferma, apri l’elenco dei problemi e fornisci il primo errore rosso con il nome del file. La registrazione mentre Goodnotes è in primo piano, a schermo bloccato, le associazioni URL e l’accesso dai menu di altre app non sono stati verificati nel contesto Swift Playground. Per il primo test tieni ClassNote visibile.

L’avvio da Swift Playground non installa automaticamente un’app indipendente nella schermata Home. Il sorgente `.swiftpm` può essere condiviso con chi usa Swift Playground; la distribuzione App Store/TestFlight richiede la configurazione di pubblicazione Apple e una build valida. Prima di sostituire il progetto esporta un backup delle lezioni.

Guida ufficiale per l’avvio: https://support.apple.com/guide/playgrounds-ipad/itc650868b1f/ipados
Permessi ufficiali: https://developer.apple.com/documentation/swift-playgrounds/project-capabilities

## Requisiti per il percorso Xcode su Mac

- Mac con Xcode e SDK compatibili con la versione iPadOS del dispositivo. iPadOS minimo del progetto: 17.0.
- Apple Pencil compatibile con l’iPad per il quaderno a mano. La sola riproduzione e l’archivio funzionano senza Pencil.
- Account Apple da selezionare in Xcode per la firma sul dispositivo. Le disponibilità di provisioning del proprio account sono gestite da Apple.
- Per generazione Foundation Models: framework presente nell’SDK, sistema compatibile e Apple Intelligence disponibile/attiva sul dispositivo. L’app verifica questa condizione a runtime; non presume che tutti gli iPad la soddisfino.
- Per Whisper: rete per scaricare la dipendenza di sviluppo e poi i pesi/tokenizer. L’inferenza successiva è locale; non richiede chiavi API o un server personale.

## Prima compilazione

1. Estrai l’archivio senza spostare separatamente `Packages`, `Resources` o le cartelle dei sorgenti.
2. Apri un solo progetto: `ClassNoteAI.xcodeproj` per iniziare; `ClassNoteAIWhisper.xcodeproj` per includere il motore open source.
3. Seleziona il progetto nel navigatore, il target dell’app e la scheda Signing & Capabilities.
4. Mantieni Automatically manage signing, scegli il tuo Team e imposta un identificatore libero, per esempio `it.tuonome.classnote`. L’identificatore di test deve essere distinto.
5. I due progetti usano di default lo stesso Bundle Identifier: installando una variante sopra l’altra puoi conservare il contenitore dati se la firma è compatibile. Non installare contemporaneamente due varianti con identità di firma diverse aspettandoti un archivio condiviso.
6. Per Whisper attendi Resolve Package Dependencies. La versione diretta è fissata a 0.9.0 e le sue dipendenze principali sono fissate dall’autore. Il prodotto collegato è soltanto `WhisperKit`.
7. Esegui Product → Build. Eventuali errori della prima build Apple devono essere risolti prima di distribuire: non è stata disponibile una compilazione Xcode in questa consegna.

I progetti sono già presenti, senza bisogno di XcodeGen. Per rigenerarli dopo aver aggiunto file Swift alle cartelle previste:

```bash
python3 scripts/generate_project.py
```

Il generatore non imposta Team, certificati o password. Se avevi cambiato le impostazioni di firma direttamente nel progetto, annotale prima di rigenerare.

## Simulatore

```bash
xcodebuild -project ClassNoteAI.xcodeproj -scheme ClassNoteAI \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
```

Scegli un iPad installato e usa il suo UUID:

```bash
CLASSNOTE_TEST_DESTINATION='platform=iOS Simulator,id=UUID_DEL_SIMULATORE' \
  bash scripts/verify_on_mac.sh
```

`UUID_DEL_SIMULATORE` è un segnaposto da sostituire. Non serve modificare il codice dell’app. Un simulatore non verifica Apple Pencil fisica, microfoni reali, consumi, registrazione bloccata o integrazione con la copia Goodnotes del proprio iPad.

## Dispositivo

Collega l’iPad con un cavo, autorizza il Mac e selezionalo come destinazione. Segui l’eventuale richiesta di Developer Mode del sistema. Premi Run. Xcode si occupa di costruire, firmare e trasferire l’app con le credenziali del tuo Team.

All’interno dell’app crea una lezione e fai una registrazione di prova. Per Apple Speech concedi anche il permesso di riconoscimento. Se manca il supporto offline, l’app registra soltanto audio e lo comunica. Per Whisper apri Impostazioni, seleziona Small e premi Scarica / carica; attendi lo stato Pronto. Prova poi in modalità aereo prima di affidarti all’uso senza rete.

Questa consegna non contiene un IPA, perché non è stato compilato né firmato per un account Apple. I progetti `.xcodeproj` richiedono Xcode su Mac; il pacchetto `.swiftpm` fornito separatamente nello stesso ZIP è il percorso per avviare il sorgente da Swift Playground su iPad.

## Backup prima di aggiornare

Termina la registrazione, apri il menu di esportazione e scegli Backup. Il selettore di File permette di salvare una cartella `.classnotepackage`, anche su iCloud Drive. Contiene manifest, trascrizione e media della singola lezione. Il backup non è cifrato con una password dall’app; la destinazione viene scelta dall’utente.

Per ripristinare usa Ripristina backup nell’archivio. Il ripristino rifiuta di sovrascrivere una lezione con la stessa identità. Verifica una copia in un contenitore di test prima di eliminare l’originale.

## Risoluzione problemi

| Problema | Controllo |
| --- | --- |
| Nessun testo live | Motore selezionato, permesso Speech, lingua e supporto offline; l’audio può comunque essere presente |
| Whisper non incluso | Aprire il progetto e schema `ClassNoteAIWhisper`, non quello base |
| Whisper non pronto senza rete | Completare prima il download e la preparazione, inclusa la cache tokenizer |
| Timestamp apparentemente spostati | Misurare su hardware; i timestamp ASR sono stime e i tratti usano il clock della sessione |
| Registrazione in pausa dopo cambio cuffie | È intenzionale: verificare il microfono e premere Riprendi |
| Goodnotes non nel menu Condividi | Aprire Altro → Modifica e controllare le app abilitate dal sistema |
| Poco spazio | I CAF PCM occupano circa 346 MB per ora per canale a 48 kHz/16 bit; l’app ferma nuove scritture sotto circa 200 MB liberi |
| Backup già esistente | Il ripristino non sovrascrive; scegliere un contenitore senza quella lezione |
