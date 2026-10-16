# Stato delle funzionalità

“Implementato” significa che è presente un percorso applicativo con codice e persistenza, non che sia stato verificato su iPad. Soltanto i test del pacchetto portabile sono stati eseguiti. Le limitazioni fanno parte della consegna.

## Nucleo

| Funzione | Stato del codice | Verifica / limite |
| --- | --- | --- |
| Registra, pausa, riprendi, termina | Implementato AVAudioEngine | Microfono reale da provare |
| Timer, livello microfono, forma d’onda | Implementati | Forma d’onda live, non indice di tutta la registrazione |
| Salvataggio di ore | Blocchi PCM e metadati progressivi | Nessuna prova audio lunga eseguita; richiede spazio elevato |
| Recupero dopo interruzione/crash | Journal e scansione dei CAF | Ultimo file recuperabile solo se leggibile; kill test da eseguire |
| Permessi e registrazione visibile | Implementati | Comportamento OS da verificare sul dispositivo |
| Gestione interruzioni/cuffie | Pausa esplicita e avviso | Matrice di dispositivi da provare |
| Riduzione rumore | Opzione voice processing Apple | Miglioramento acustico non misurato |
| Voice Activity Detection | Indicatore energetico euristico | Non è un classificatore neurale VAD; non taglia il silenzio audio |
| Live italiano/inglese | Apple offline o Whisper a blocchi | Supporto Apple condizionale; latenza Whisper ≥ blocco + calcolo |
| Parziali e confermati | Implementati | Grigio per i provvisori; finalizzazione Apple dipende dal servizio locale |
| Confidenza | Conservata se fornita dal motore | Non è una probabilità calibrata; parole basse segnate |
| Timestamp parola/frase | Implementati quando il motore li fornisce | Sono stime acustiche, non timestamp esatti garantiti |
| Tap parola, frase, ricerca e segnalibro | Implementati | Riproduzione reale da verificare |
| Evidenziazione durante playback | Implementata a intervalli di parola | Correzioni prive di tempo richiamano il segmento |
| Velocità, selezione A–B e loop | Implementati | Intervallo definito con due pulsanti |
| Esportazione clip/audio | M4A via composizione AVFoundation | Build/test Apple mancanti |
| Forced alignment di testo corretto | Non implementato | Le parole cambiate vengono marcate non allineate |
| Transizioni audio senza gap | Non garantite | Il player cambia file fra blocchi |

## Quaderno

| Funzione | Stato |
| --- | --- |
| Penna, matita, evidenziatore, gomma, lazo, colori e spessori | Tool picker nativo PencilKit |
| Pagine bianche/rigate/quadrettate, zoom e undo/redo | Implementati |
| Ancoraggi temporali dei tratti in registrazione | Implementati usando clock della sessione e path PencilKit; precisione da misurare |
| Tap sull’inchiostro | Implementato con hit test dei bounds; tratti sovrapposti possono essere ambigui |
| Pagina/evidenziazione durante riascolto | Implementate con ancoraggi locali |
| Salvataggio incrementale | Archivio atomico della sola pagina modificata; nessun journal di delta dei tratti |
| Testo digitato, immagini da Foto/File, scansioni | Implementati; immagini in area dedicata della pagina |
| OCR stampato/scrittura | Vision, avvio esplicito; accuratezza della scrittura non garantita |
| PDF | Importazione, visualizzazione nel pannello documenti, collegamenti pagina-audio ed esportazione |
| Scrivere direttamente sopra un PDF importato | Non implementato come editor PDF sovrapposto; quaderno PencilKit e PDF restano pannelli distinti |
| Formule LaTeX | Editor, anteprima KaTeX locale, inserimento del sorgente nel testo della pagina |
| Formule renderizzate in ogni esportazione | Non ancora: l’anteprima è nell’editor; il testo note conserva LaTeX |
| Formule pronunciate | Conversione limitata di simboli espliciti, da confermare; nessun parser matematico generale |
| OCR matematico/chimico strutturato | Non implementato |
| Riconoscimento di grafici, tabelle editabili, diagrammi vettoriali | Non implementati |

## Goodnotes e documenti

| Funzione | Stato |
| --- | --- |
| PDF verso Goodnotes via Condividi | Implementato con API di sistema; destinazioni effettive da provare |
| PDF Goodnotes verso ClassNote | Import da File, tipi documentali e drop |
| Aggiornamento del PDF senza un nuovo documento | Implementato con ID stabile, checksum e revisione |
| Link pagina-audio e suggerimenti OCR/testo | Implementati; conferma richiesta per proposte e versioni aggiornate |
| Preservare timestamp dei tratti Goodnotes | Non disponibili in questo scambio; non inventati |
| iCloud Drive | Accesso mediato dal selettore File, non sincronizzazione automatica dell’archivio |
| Multitasking | Layout adattivo, nessun obbligo fullscreen |
| Registrazione in background | Configurazione ufficiale presente; continuità non verificata su hardware |
| Trascrizione in background | Non garantita; lavori Whisper sospesi quando la scena non è attiva |
| Sync bidirezionale, watcher del quaderno Goodnotes | Non implementati; manca un’integrazione pubblica documentata identificata |
| Aprire `.goodnotes`, estrarne i tratti o pilotare Goodnotes | Non implementato |

## Studio, archivio e AI

| Funzione | Stato |
| --- | --- |
| Materie, lezioni, date, durata, etichette, stelle | Implementati nell’archivio |
| Vista calendario completa | Non implementata |
| Ricerca globale nella trascrizione | BM25 implementato e testato |
| Ricerca negli appunti | Testo e OCR delle pagine già acquisito |
| Ricerca semantica | Sentence embedding NaturalLanguage, se disponibili; fallback lessicale |
| Ricerca completa nel testo di tutti i PDF | Non ancora; l’OCR PDF è usato per il confronto pagina-trascrizione |
| Riassunti, schemi, definizioni, esempi, domande, compiti | Generazione locale condizionale con Foundation Models; altrimenti estratti etichettati |
| Riassunto esaustivo di più ore | Non implementato; massimo dieci fonti selezionate per generazione |
| Generazione automatica a fine registrazione | Non implementata; azioni manuali nel pannello Studio |
| Correzione intelligente | Foundation Models se disponibile, proposta da accettare; senza modello solo normalizzazione spazi |
| Correzione tramite secondo STT | Ritrascrizione Whisper con proposta, senza sovrascrivere l’originale |
| Assistente per lezione/minuto | Retrieval di fonti, generazione condizionale e link audio |
| Confronto con lezione precedente | Stessa materia, fonti distinte e riferimenti conservati |
| Chat su tutte le lezioni | Ricerca globale quando la richiesta menziona “tutte le lezioni”; non cronologia chat persistente completa |
| Capitoli e cambi argomento | Euristica lessicale con soglie; non classificatore semantico validato |
| Flashcard e ripasso dilazionato | Implementati; risposte estrattive con fonte |
| Quiz a scelta multipla valutati | Non implementati; disponibile autoverifica con flashcard |
| Traduzione automatica | Non implementata |
| Modello LLM open source indipendente da Apple Intelligence | Non integrato |
| PDF, TXT, Markdown, JSON, TSV e M4A | Percorsi di esportazione implementati |
| Backup e ripristino | Pacchetto locale della singola lezione, esportato con File |
| Modalità scura e tastiera | Tema sistema/chiaro/scuro, input nativo, scorciatoia Cmd-R e menu |
| Prestazioni certificate su iPad | Non disponibili; nessuna build hardware eseguita |

## Passaggi necessari prima di affidarsi all’app

1. Prima build con SDK Apple e correzione degli eventuali errori di integrazione emersi dal type checking Apple.
2. Cinque test Apple su simulatore e prove del flusso principale su iPad con microfono e Pencil.
3. Prova lunga con pause, schermo bloccato, Goodnotes in primo piano, cambio cuffie e recupero dopo chiusura.
4. Misura dei timestamp su una registrazione con marcatori noti, WER italiano e consumo di memoria/energia.
5. Solo dopo questa validazione: player gapless, forced aligner, editor PDF/inchiostro unificato e pipeline di riassunto gerarchico.

L’archivio non contiene un binario installabile già firmato né certificazioni App Store.
