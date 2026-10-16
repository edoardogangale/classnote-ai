# Architettura e invarianti

## Acquisizione e tempo

AVAudioEngine acquisisce un solo flusso microfonico. Il tap copia i buffer in una coda limitata a 96 elementi; scrittura su disco e alimentazione di Speech avvengono fuori dal callback audio. Un ritardo di scrittura eccessivo o un errore ferma la registrazione, invece di continuare con perdite silenziose.

I CAF sono PCM a 16 bit, con sample rate e canali del percorso audio. Si ruotano dopo almeno 12 secondi, al limite di un buffer, e il tempo globale è:

```text
tempo = offset iniziale del blocco + frame scritti / sample rate
```

Le pause non aggiungono tempo audio. Il timer mostrato viene aggiornato al checkpoint; il quaderno può leggere una fotografia più recente dei frame per collegare i tratti senza attendere il successivo checkpoint. La conversione fra clock della penna e audio resta soggetta a latenza del dispositivo e deve essere misurata.

Ogni blocco ha un file `.chunkmeta`, scritto prima del primo buffer e aggiornato circa ogni secondo. Alla chiusura il file audio viene finalizzato prima di affidarlo a Whisper. Al riavvio si confrontano i sidecar con il database e si legge la durata effettiva dei CAF aperti. Il recupero dell’ultimo blocco dipende dalla leggibilità del file: non è una promessa di perdita zero dopo ogni tipo di crash.

## Trascrizione e revisioni

Un blocco corrisponde a un segmento persistente. Apple Speech riceve gli stessi buffer del file e usa l’offset del blocco per convertire i tempi del riconoscitore. L’ID del segmento è quello del blocco. Le parole hanno UUID, tempi iniziale/finale opzionali, blocco, stato e confidenza se disponibile.

Gli aggiornamenti provvisori sostituiscono una sola riga SQLite. L’ID di una parola viene conservato quando il token nella stessa posizione rimane uguale e il tempo è vicino; le parole provvisorie non vengono spacciate per confermate. Le richieste terminate hanno fino a otto secondi per produrre un risultato finale prima della cancellazione.

Un secondo riconoscitore non sovrascrive silenziosamente un originale già presente: produce una proposta di correzione. Dopo l’accettazione una LCS conserva gli ancoraggi dei token rimasti riconoscibili, mentre le nuove parole hanno `start/end = nil` e `needsReview`. È riconciliazione testuale, non forced alignment. L’originale e i suoi token rimangono disponibili.

## Riproduzione

LecturePlayer apre solo blocchi chiusi. Toccare testo o inchiostro mette in pausa una registrazione attiva prima di riprodurre, così non si registra l’altoparlante. Il cursore viene aggiornato a circa 20 Hz; la ricerca del token evidenziato usa l’intervallo `[inizio, fine)`.

AVAudioPlayer viene riaperto al cambio di blocco. La transizione non è garantita gapless; può esserci una piccola discontinuità. Un futuro player AVAudioEngine con buffer programmati è appropriato se i test richiedono continuità al campione. Esportazione M4A e clip A–B usano una composizione AVFoundation e rispettano gli intervalli globali.

## Quaderno

PencilKit gestisce gli strumenti nativi. Ogni pagina è un archivio PKDrawing separato, scritto atomicamente dopo il tratto o con debounce di 250 ms. L’incrementalità è per pagina: non viene riscritto l’intero quaderno, ma la singola pagina viene serializzata per intero. Non esiste ancora un journal binario di delta dei tratti.

L’identità dei tratti deriva da creazione e geometria del path, evitando indici che cambierebbero con una gomma. Il transform non entra nell’identità, così uno spostamento con lazo può conservarne il collegamento. Splitting/cancellazione e comportamento dei path PencilKit vanno validati su hardware. I tratti scritti fuori da registrazione o riproduzione rimangono senza collegamento temporale.

Il tap con il dito esegue un hit test sui bounds del tratto, con tolleranza. Può selezionare un tratto sovrapposto senza distinguere la forma esatta: il test geometrico punto-path è un miglioramento ancora necessario. Durante il riascolto si evidenziano i bounds e si passa alla pagina con tratti pertinenti.

## Persistenza e documenti

SQLite in WAL con `synchronous=FULL`, chiavi esterne e `secure_delete=ON` contiene manifest delle lezioni e segmenti. Un lock serializza l’accesso. Audio, disegni, immagini e PDF sono file separati protetti nel contenitore dell’app. Le correzioni non richiedono una riscrittura dell’audio.

I file esterni sono acquisiti con permessi security-scoped; i PDF usano coordinamento di File. Le copie locali non restano collegate automaticamente al provider originario. Il backup copia soltanto una lezione ferma con il suo manifest, segmenti e media; non copia a caldo un database WAL. Il ripristino valida identità, schema, nomi, symlink e timeline e rifiuta sovrascritture.

## AI e ricerca

La ricerca lessicale BM25 e gli estratti sono nel pacchetto portabile. Le sentence embedding NaturalLanguage sono opzionali e dipendono dalla disponibilità del sistema; se mancano, rimangono i risultati lessicali. I quaderni sono ricercabili per testo scritto e OCR già eseguito.

Foundation Models viene importato solo con un SDK che lo includa e usato dopo il controllo di disponibilità. Il prompt usa fino a dieci fonti brevi; la risposta deve citare identificatori validi. Le citazioni con ID inesistenti sono rifiutate. Non è una verifica semantica della veridicità: l’utente deve ascoltare la fonte. Una risposta a corpus intero esaustiva richiede ancora riduzione gerarchica e verifica di copertura.

Non sono previsti account, backend obbligatorio, notifiche di marketing, telemetria o servizi speech remoti.
