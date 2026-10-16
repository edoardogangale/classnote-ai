# Goodnotes: integrazione supportata

Ricerca su fonti ufficiali aggiornata al 16 ottobre 2026. Le prove con l’app Goodnotes installata non sono state eseguite in questo ambiente.

## Cosa è stato trovato

Goodnotes documenta l’importazione di PDF e immagini dall’app, da File, tramite Condividi/Apri in e con drag and drop. L’esportazione può produrre PDF o immagini. Il formato `.goodnotes` è proprio di Goodnotes e non viene interpretato da ClassNote.

Nelle risorse ufficiali consultate non è stata identificata un’API pubblica documentata che dia a un’app terza accesso a tratti, modifiche dei quaderni e timestamp di scrittura. Questa è la conclusione della ricerca svolta, non una dichiarazione sull’inesistenza di qualsiasi accordo privato o futuro SDK. Non è stato usato alcun protocollo privato, scraping del contenitore Goodnotes o decodifica del suo formato.

Fonti: [Import files into Goodnotes](https://support.goodnotes.com/hc/en-us/articles/7353717816463-Import-files-into-Goodnotes), [Export documents or pages](https://support.goodnotes.com/hc/en-us/articles/7353742824975-Export-documents-or-pages).

## Procedura consigliata

1. Crea la lezione in ClassNote e avvia la registrazione.
2. Affianca Goodnotes usando il multitasking disponibile sul tuo iPad. Il layout di ClassNote si adatta alle finestre strette. Non occorre che ClassNote apra o controlli la finestra di Goodnotes.
3. Scrivi in Goodnotes. Controlla il normale indicatore del microfono di iPadOS. Evita di avviare un secondo registratore che possa prendere il microfono.
4. Termina la registrazione ClassNote.
5. In Goodnotes esporta il quaderno o le pagine in PDF e salvale su File. In ClassNote apri il pannello Goodnotes e importa il PDF.
6. Apri il documento, scegli una pagina e premi Ora audio per usare il cursore corrente oppure inserisci i secondi. Conferma l’associazione.
7. In alternativa premi Suggerisci collegamento dal contenuto. Il testo PDF, o l’OCR se necessario, viene confrontato lessicalmente con la trascrizione. Le prime tre corrispondenze sono suggerimenti da confermare, non timestamp originali di Goodnotes.
8. Dopo ulteriori modifiche esporta nuovamente il PDF e usa Aggiorna questo PDF sul documento esistente.

La sostituzione mantiene il `LinkedDocument.id` e incrementa la revisione. Il checksum SHA-256 impedisce la duplicazione di file identici. I collegamenti delle pagine rimangono come proposte da riconfermare: anche la pagina con lo stesso numero potrebbe avere contenuto diverso. I vecchi file PDF restano nel contenitore fino alla cancellazione della lezione; non vengono distrutti prima del commit della nuova versione.

## Tornare da Goodnotes alla registrazione

Il PDF ClassNote contiene URI del tipo:

```text
classnote://lecture/UUID-DELLA-LEZIONE?t=125.5
```

Questi link aprono una lezione locale e un tempo audio; non contengono né caricano l’audio. Richiedono ClassNote installata e la stessa lezione presente sul dispositivo. Non trasferiscono l’archivio a un compagno e non creano un sito pubblico.

La compatibilità dei link con schema personalizzato deve essere provata in Goodnotes: il codice esporta annotazioni PDF standard, ma non può imporre a un’altra app di aprire ogni schema URI. Per conservare i link già incorporati nei PDF, Goodnotes raccomanda l’esportazione Editable; Flattened può eliminarli. Se il ritorno diretto è bloccato dal lettore PDF, il timestamp rimane leggibile e può essere raggiunto manualmente in ClassNote.

Fonti: [PDF outlines and hyperlinks](https://support.goodnotes.com/hc/en-us/articles/7353742854543-PDF-outlines-and-hyperlinks-are-missing-when-I-export-a-document), [Editable/Flattened](https://support.goodnotes.com/hc/en-us/articles/8537070839183-Choose-Between-Editable-and-Flattened-PDF-Export).

## Registrazione con Goodnotes in primo piano

ClassNote imposta AVAudioSession `playAndRecord`, richiede il microfono e dichiara `UIBackgroundModes = audio`. È il meccanismo ufficiale per un’attività audio avviata dall’utente che continua in background. L’app non si riavvia da sola per registrare e non mantiene un processo nascosto con audio silenzioso.

Interruzioni, cambio di cuffie, pressioni di memoria e decisioni del sistema restano possibili. Una chiusura forzata interrompe la registrazione. Il codice mette in pausa sui cambi di dispositivo audio rilevati e richiede una ripresa esplicita. La trascrizione Apple in background non è garantita. I lavori Whisper vengono sospesi/cancellati quando la scena non è attiva e ripresi in primo piano; l’audio continua a essere il riferimento persistente.

Fonti Apple: [AVAudioSession.record](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record), [playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord), [background modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes).

## Limiti specifici

| Richiesta | Comportamento della versione consegnata |
| --- | --- |
| Leggere in tempo reale i tratti Goodnotes | Non disponibile nell’integrazione implementata |
| Ricevere notifiche dei cambiamenti del quaderno | Non implementato; l’utente reimporta il PDF |
| Sincronizzazione automatica bidirezionale | Non implementata |
| Timestamp esatti di tratti Goodnotes | Non attribuiti |
| Collegare pagine a spiegazioni | Associazioni manuali o proposte di contenuto confermate |
| Aggiornare senza un nuovo documento ClassNote | Comando Aggiorna questo PDF, identità conservata |
| iCloud Drive | Import/export tramite selettore File; nessun accesso al contenitore iCloud privato di Goodnotes |
| Drag and drop | PDF in entrata; PDF già importati trascinabili in uscita; primo provider elaborato per ogni drop |
| Condividi verso Goodnotes | UIActivityViewController standard; le app mostrate sono decise dal sistema |
| Audio Goodnotes dentro il PDF | Il PDF non lo conserva; ClassNote usa la propria registrazione |
| Condivisione verso ClassNote | Apertura di tipi documentali registrati e importazione da File; nessuna Share Extension dedicata |

Altre fonti: [Goodnotes assente da Condividi](https://support.goodnotes.com/hc/en-us/articles/360001187355-Fix-Goodnotes-Missing-From-the-Share-Sheet-on-iPhone-or-iPad), [audio ed esportazione](https://support.goodnotes.com/hc/en-us/articles/7352729730959-Can-I-Share-my-Audio-Recordings).
