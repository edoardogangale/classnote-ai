# ClassNote AI: Windows → GitHub → iPad

Questo archivio è predisposto per compilare l’app nativa con Xcode su GitHub Actions. Non richiede Swift Playground, un Mac personale, certificati Apple o credenziali Apple nella compilazione. Non è già un IPA: la prima compilazione su GitHub potrebbe rilevare problemi da correggere.

## 1. Crea il repository dal browser Windows

1. Scarica questo ZIP sul PC Windows, tasto destro → **Estrai tutto**.
2. Apri la cartella estratta. Devi vedere direttamente `App`, `Resources`, `.github`, `ClassNoteAI.xcodeproj` e questo documento.
3. Accedi al tuo account su https://github.com/new.
4. Repository name: **classnote-ai**. Visibilità: **Public**. Il codice sarà visibile pubblicamente.
5. Seleziona **Add a README file** e premi **Create repository**. Non servono carta, abbonamenti o Secrets.

Le macchine macOS standard di GitHub Actions sono gratuite per repository pubblici. Non scegliere runner di dimensioni maggiorate. Per evitare esecuzioni macOS su un repository privato, il job incluso è configurato per essere saltato se la visibilità non è pubblica. Le lezioni e le registrazioni non fanno parte del codice e non vanno caricate nel repository.

## 2. Carica il contenuto estratto, in tre passaggi

Il sito permette fino a 100 file per caricamento. La cartella Resources contiene molti font: usa questi tre caricamenti separati.

1. Nel repository premi **Add file → Upload files**. Dalla cartella estratta trascina TUTTI gli elementi **eccetto Resources e .github**. Carica il contenuto, non la cartella esterna né lo ZIP. Premi **Commit changes** sul ramo `main`.
2. Torna a **Add file → Upload files**. Trascina soltanto la cartella **Resources**, quindi **Commit changes**.
3. Ripeti con la cartella **.github**, per ultima. Poi **Commit changes**. Contiene la procedura automatica: caricarla per ultima evita compilazioni con sorgenti mancanti.

Se GitHub chiede di sovrascrivere il README iniziale, usa quello incluso in questo archivio. Non modificare i sorgenti. Se hai già un repository con lo stesso nome, creane uno nuovo dedicato per non sovrascrivere altri progetti.

Nel repository devono risultare direttamente `App/`, `Resources/`, `Packages/`, `ClassNoteAI.xcodeproj/` e `.github/workflows/build-ipad.yml`. Se c’è un’ulteriore cartella che li contiene tutti, la compilazione non troverà il progetto.

## 3. Avvia la compilazione e mandami il risultato

1. Apri la scheda **Actions**. Se GitHub richiede di abilitare i workflow, abilitali per questo repository.
2. Apri **Build iPad IPA**. Normalmente parte dopo il caricamento di `.github`. In alternativa premi **Run workflow → Run workflow** sul ramo `main`.
3. Attendi la conclusione del processo. Non occorre tenere il PC acceso: la compilazione gira su GitHub.
4. Apri il risultato della singola esecuzione. Nella sezione **Artifacts**, scarica **ClassNoteAI-logs**. Il download richiede l’accesso al tuo account GitHub.
5. Mandami **il link del repository** e **lo ZIP ClassNoteAI-logs**. Se non trovi i log, manda uno screenshot della pagina Actions con il passaggio rosso aperto.

Non mandarmi password GitHub/Apple, codici di verifica, cookie o token. Questa procedura non richiede Secrets né pagamenti. Il link del repository pubblico e gli errori della build bastano per lavorare sul codice.

Il workflow esegue: controlli del progetto, test del nucleo, compilazione per dispositivo iPad, confezionamento IPA, compilazione e cinque test di integrazione Apple su un simulatore iPad. La compilazione seleziona Xcode 16.4 sul runner macOS 15; non usa servizi di inferenza remoti. Foundation Models è disponibile solo nelle build realizzate con un SDK che lo include: con questo SDK si usa il percorso di studio estrattivo locale.

## 4. Soltanto dopo una compilazione riuscita: AltStore Classic

Quando **Build iPad IPA** è verde, scarica **ClassNoteAI-IPA** da Artifacts ed estrai il file **ClassNoteAI-unsigned.ipa**. È una build per dispositivo, ancora da firmare. Se manca questo artifact o il workflow è rosso, invia i log prima di tentare l’installazione.

1. Sul PC Windows segui la guida ufficiale di **AltStore Classic**, scaricando AltServer dal sito ufficiale: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows.
2. La guida richiede iTunes e iCloud per Windows nelle versioni indicate, il collegamento USB iniziale, l’autorizzazione del computer e l’attivazione di Developer Mode sull’iPad quando richiesta.
3. Installa AltStore Classic tramite AltServer. Inserisci il tuo account Apple soltanto nel software ufficiale sul tuo PC, mai nella chat o nei Secrets GitHub.
4. Trasferisci l’IPA nell’app File sull’iPad. In AltStore Classic apri **My Apps**, premi **+** e scegli l’IPA. AltStore applica la firma personale e tenta l’installazione. Le capacità disponibili dipendono dal provisioning gratuito: l’installazione di questa app deve ancora essere verificata.
5. Apri ClassNote dalla Home. Prima prova: crea una lezione, registra 20–30 secondi, controlla trascrizione, riascolto tramite parola e quaderno Apple Pencil.

Con l’account gratuito la firma scade dopo sette giorni e sono consentite fino a tre app sideloaded attive. Rinnova in AltStore con **Refresh All** mentre AltServer è raggiungibile; non presumere che il rinnovo automatico sia sempre riuscito. Se scade, l’app non si apre finché non viene rinnovata. Prima di cancellare o reinstallare esporta un backup delle lezioni.

Il provisioning gratuito e AltStore non equivalgono alla distribuzione App Store/TestFlight, e non garantiscono tutte le capacità di una firma a pagamento. Non sono ancora stati testati l’IPA reale, la firma tramite AltStore, il microfono fisico, Apple Pencil o la registrazione con Goodnotes in primo piano. Una build verde verifica compilazione e test automatici predisposti, non queste prove hardware.

## Fonti ufficiali consultate il 16 ottobre 2026

- Runner e gratuità sui repository pubblici: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Caricamento via browser e limite dei 100 file: https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository
- Download artifact: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts
- AltStore su Windows: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- Firma gratuita e limiti: https://developer.altstore.io/ e https://faq.altstore.io/altstore-classic/your-altstore
