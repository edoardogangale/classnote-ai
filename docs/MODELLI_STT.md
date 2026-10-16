# Modelli e motori speech-to-text

Valutazione delle fonti al 16 ottobre 2026. Non sono stati eseguiti benchmark su un iPad o su registrazioni italiane di aula. Nessun WER, ritardo o consumo di batteria misurato viene inventato. I confronti qualitativi sotto sono scelte progettuali da convalidare sul dispositivo.

## Confronto

| Soluzione | Tipo e licenza | Italiano e accuratezza | Latenza, memoria ed energia su iPad | Decisione |
| --- | --- | --- | --- | --- |
| Whisper Large v3 | Pesi/modello multilingue, MIT, circa 1,55 miliardi di parametri | Candidato accurato multilingue; resta da misurare su voce lontana e lessico scolastico | Molto impegnativo rispetto ai modelli piccoli; memoria del runtime e precisione numerica cambiano il risultato | Studio per affinamento successivo; non default live |
| Whisper Large v3 Turbo | Pesi/modello multilingue, MIT, circa 809 milioni | Variante che riduce il costo del decoder; il compromesso dipende dalla lingua | Meno calcolo nel decoder di Large v3; può comunque gravare su iPad poco capienti | Opzione Core ML selezionabile, previa prova |
| Whisper Small multilingue | Pesi/modello MIT, circa 244 milioni | Più leggero ma potenzialmente meno accurato su rumore/termini difficili | Scelto per un primo compromesso locale sostenibile, senza assumere un tempo reale universale | Default del percorso Whisper implementato |
| Whisper italiano fine-tuned, es. fsicoli/whisper-large-v3-it-cv16 | Fine-tuning su italiano; nella scheda consultata i termini di licenza non sono sufficientemente chiari | Dati Common Voice non provano superiorità su lezioni reali | Mantiene il costo della famiglia Large; richiede conversione e verifica dei timestamp | Non redistribuito e non incluso |
| whisper.cpp | Runtime C/C++, MIT; la licenza dei pesi resta separata | Dipende dal modello caricato | Ha percorsi Apple, Metal/Core ML e quantizzazione; build nativa fattibile | Alternativa valida, non un secondo runtime duplicato in questa consegna |
| faster-whisper | Runtime Python/CTranslate2, MIT | Dipende dai pesi e dai parametri di decodifica | Benchmark ufficiali CPU/CUDA non equivalgono a iPad/ANE; non è una libreria Swift pronta per questo target | Non incluso; nessun server obbligatorio |
| sherpa-onnx | Runtime ONNX con percorso iOS; codice Apache-2.0, licenza di ogni modello separata | Offre varie famiglie, incluse opzioni multilingue | iOS è supportato, ma memoria e prestazioni vanno misurate per ciascun modello | Possibile evoluzione; non integrato |
| NVIDIA Parakeet TDT 0.6B v3 | Modello da circa 600 milioni, CC BY 4.0 | La scheda include italiano e timestamp | Gli esempi e i risultati pubblicati non certificano una pipeline iPad pronta | Alternativa recente valutata, non inclusa |
| Qwen3-ASR 0.6B / 1.7B | Famiglia multilingue, Apache-2.0 | Italiano presente fra le lingue supportate | Esistono conversioni ONNX documentate per sherpa; manca qui un benchmark/adapter Apple validato | Alternativa 2026 valutata, non inclusa |
| Apple Speech on-device | Motore di sistema, non open source | Verificato a runtime per lingua/dispositivo; glossario di fino a 100 voci | Evita il download di pesi gestito dall’app quando il sistema è già pronto; richieste brevi con parziali | Default operativo iniziale, senza fallback cloud |
| Apple SpeechAnalyzer / SpeechTranscriber | API di sistema più recenti | Candidati per dettatura lunga sui sistemi supportati | Asset, SDK e disponibilità richiedono una matrice hardware dedicata | Evoluzione da implementare; non dichiarata presente |

Le stime di VRAM nel README PyTorch di Whisper sono misure del suo contesto di esecuzione, non requisiti minimi di RAM di iPadOS. Per questo non vengono trasformate in una falsa tabella di compatibilità iPad.

## Scelta concretamente implementata

Il progetto base usa Apple Speech solo locale per rendere disponibile il live con parziali senza dipendenze remote di sviluppo. Il progetto Whisper aggiunge un’alternativa gratuita/open source reale, tramite WhisperKit/Core ML. Small è la scelta prudente iniziale per la variante open source, Turbo è un’opzione da misurare. Non viene dichiarato “migliore modello italiano attuale” in assenza di un confronto sullo stesso corpus e hardware.

Perché WhisperKit: API Swift, modelli Core ML e timestamp di parola già esposti. L’adattatore è scritto contro il tag ufficiale **0.9.0**, revision `a8a40c9444ae4e7263bd41e5e60b35a92e2cbba3`, controllato durante lo sviluppo. È una versione fissata per l’API usata, non una dichiarazione che sia l’ultima release. Il repository attuale è presentato come Argmax Open-Source SDK; la dipendenza del progetto resta al percorso storico compatibile.

Modelli selezionabili:

```text
argmaxinc/whisperkit-coreml/openai_whisper-small
argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo
```

Il bottone di preparazione scarica i file necessari, inclusa la cache tokenizer, senza caricare registrazioni. La disponibilità dei repository può cambiare. In caso di cache incompleta l’app richiede di completare la preparazione; una cache corrotta può comunque richiedere il ripristino delle risorse. Il test in modalità aereo resta necessario.

## Come misurare prima della scelta definitiva

Usare lo stesso audio, la stessa trascrizione di riferimento umana e lo stesso iPad. Includere italiano, inglese, cambi di lingua, rumore e termini delle dieci materie. Misurare WER, errori sui nomi/formule, tempo al primo testo, ritardo dei token confermati, errore temporale delle parole, memoria massima, stato termico e batteria per ora.

Separare le misure in primo piano da quelle in multitasking. Provare almeno Small e Turbo e mantenere un profilo più leggero se compaiono accumulo della coda o pressioni di memoria. Nessuna percentuale di accuratezza o compatibilità hardware è stata dedotta soltanto dal nome del modello.

## Fonti primarie

- [OpenAI Whisper](https://github.com/openai/whisper) e [rilascio Turbo](https://github.com/openai/whisper/discussions/2363).
- [WhisperKit attuale](https://github.com/argmaxinc/argmax-oss-swift), [tag utilizzato](https://github.com/argmaxinc/WhisperKit/tree/v0.9.0), [modelli Core ML](https://huggingface.co/argmaxinc/whisperkit-coreml).
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [faster-whisper](https://github.com/SYSTRAN/faster-whisper).
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), [build iOS](https://k2-fsa.github.io/sherpa/onnx/ios/build-sherpa-onnx-swift.html), [Qwen ONNX](https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/pretrained.html).
- [Fine-tuning italiano esaminato](https://huggingface.co/fsicoli/whisper-large-v3-it-cv16).
- [NVIDIA Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B).
- [SpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer), [requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer).
