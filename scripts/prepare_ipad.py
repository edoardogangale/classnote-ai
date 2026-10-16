#!/usr/bin/env python3
"""Build a self-contained app playground from the same native sources.

No symlinks, external packages, account credentials, or precompiled binaries.
The conditional manifest also lets Linux test the real portable core.
"""
from pathlib import Path
import plistlib
import shutil

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'iPad' / 'ClassNoteAI.swiftpm'
APP_FOLDERS = ('App', 'Audio', 'Transcription', 'Storage', 'Notebook', 'Documents', 'Study', 'Views')

MANIFEST = '''// swift-tools-version: 5.9
import PackageDescription
#if canImport(AppleProductTypes)
import AppleProductTypes
#endif

let package = Package(
    name: "ClassNoteAI",
    defaultLocalization: "it",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ClassNoteCore", targets: ["ClassNoteCore"])],
    targets: [
        .target(name: "ClassNoteCore", path: "Core"),
        .testTarget(name: "ClassNoteCoreTests", dependencies: ["ClassNoteCore"], path: "CoreTests")
    ],
    swiftLanguageVersions: [.v5]
)

// AppleProductTypes is supplied by Swift Playground and Xcode for app playgrounds.
// On Linux only the portable core and its tests are built.
#if canImport(AppleProductTypes)
// App playgrounds expose a single application product. Core remains an internal target.
package.products.removeAll()
package.products.append(
    .iOSApplication(
        name: "ClassNote AI",
        targets: ["AppModule"],
        bundleIdentifier: "it.classnote.ai.playground",
        displayVersion: "0.2.2",
        bundleVersion: "4",
        appIcon: .placeholder(icon: .mic),
        accentColor: .presetColor(.blue),
        supportedDeviceFamilies: [.pad],
        supportedInterfaceOrientations: [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight],
        capabilities: [
            .microphone(purposeString: "Registra le lezioni solo quando premi Registra. L’audio rimane sul tuo iPad."),
            .speechRecognition(purposeString: "Trascrive le lezioni sul dispositivo quando la lingua offline è supportata. Non invia audio a server."),
            .camera(purposeString: "Scansiona lavagna e documenti da aggiungere agli appunti.")
        ],
        additionalInfoPlistContentFilePath: "AppInfo.plist"
    )
)
package.targets.append(
    .executableTarget(
        name: "AppModule",
        dependencies: ["ClassNoteCore"],
        path: "App",
        resources: [.copy("Resources/Math"), .copy("Resources/PrivacyInfo.xcprivacy")],
        swiftSettings: [.define("CLASSNOTE_PLAYGROUND")],
        linkerSettings: [.linkedLibrary("sqlite3")]
    )
)
#endif
'''

GUIDE = '''CLASSNOTE AI — APRI QUESTO PROGETTO SULL’IPAD

1. Su iPad installa/aggiorna Swift Playground dall’App Store.
2. Salva ClassNoteAI_Sorgenti.zip nell’app File e tocca lo ZIP per estrarlo.
3. Apri la cartella estratta. Tocca ClassNoteAI.swiftpm e aprilo con Swift Playground.
   Se vedi una cartella normale, controlla che il nome termini con .swiftpm:
   usa Condividi > Swift Playground oppure il selettore Apri/Sfoglia dell’app.
4. Non aprire Package.swift da solo e non copiare a mano i singoli sorgenti.
5. Premi ▶ Esegui app sopra l’area del codice. Attendi la compilazione.
   Usa la finestra dell’app per registrare, non la sola anteprima del codice.
6. Nella schermata Versione 0.2.2 premi Apri ClassNote. Poi crea una lezione,
   conferma le autorizzazioni alla registrazione,
   premi Registra e consenti microfono e riconoscimento vocale.
7. Parla per 20–30 secondi. Se l’italiano offline è disponibile sull’iPad,
   compariranno le parole. Termina la registrazione e tocca una parola:
   deve partire il riascolto da quel punto. Poi prova Apple Pencil nel quaderno.

Per questa prova non serve Windows. Il progetto contiene già i file necessari:
non devi scrivere o modificare codice e non devi scaricare modelli Whisper.
Serve Swift Playground compatibile con iPadOS 17 o successivo.

PRIMA PROVA E LIMITI
Il progetto è stato convertito per Swift Playground; non è stato compilato
con SDK Apple o eseguito su un iPad in questo ambiente. Nel pacchetto trovi
i risultati reali dei controlli eseguiti. Un errore di compilazione deve essere
risolto prima di usare il registratore: apri l’elenco degli errori e invia
uno screenshot del PRIMO messaggio rosso, con il nome del file visibile.

Se non compaiono parole, controlla in Impostazioni lingua e permessi.
Il riconoscimento offline Apple dipende dal dispositivo e dalle risorse
linguistiche disponibili: in assenza di supporto l’app conserva solo l’audio.
Questa edizione non include Whisper né attiva un servizio cloud alternativo.

AVVIO E INSTALLAZIONE SONO PASSAGGI DIVERSI
Qui avvii l’app da Swift Playground. Il file non è un IPA firmato e non installa
da solo un’icona autonoma nella schermata Home. Per una distribuzione tramite
App Store/TestFlight occorrono compilazione valida e configurazione Apple per
la pubblicazione. Condividere il progetto richiede Swift Playground a chi lo apre.

GOODNOTES
Prima verifica il nucleo con ClassNote visibile. Puoi scambiare PDF tramite
Condividi e File. In questa edizione il funzionamento con Goodnotes in primo
piano e a schermo bloccato non è stato verificato: non affidarti al background
per una lezione finché non avrai fatto una prova sul tuo iPad. I collegamenti
tra pagine PDF e audio vengono confermati manualmente; nessun timestamp dei
tratti Goodnotes viene inventato. Anche l’apertura di link classnote:// da altre
app deve essere verificata nel contesto Swift Playground.

DATI
Prima di aggiornare o cancellare il progetto, termina la registrazione ed
esporta un Backup da ClassNote in una posizione scelta nell’app File.
Conserva il progetto, il backup e i documenti originali. Copiare questo sorgente
non copia automaticamente le lezioni già create sul dispositivo.

ALTRI SORGENTI
La cartella ClassNoteAI contiene anche i progetti Xcode e la documentazione
tecnica completa per una futura compilazione su Mac, inclusa la variante Whisper.
Non occorre aprirla per la prima prova su iPad.

Guida Apple: https://support.apple.com/guide/playgrounds-ipad/itc650868b1f/ipados
'''


def prepare():
    DEST.mkdir(parents=True, exist_ok=True)
    # Replace generated source folders; keep incremental .build only for local QA.
    for folder in ('App', 'Core', 'CoreTests'):
        path = DEST / folder
        if path.exists():
            shutil.rmtree(path)
    for folder in APP_FOLDERS:
        target = DEST / 'App' / folder
        target.mkdir(parents=True, exist_ok=True)
        for source in (ROOT / folder).glob('*.swift'):
            shutil.copy2(source, target / source.name)
    shutil.copytree(ROOT / 'Packages/ClassNoteCore/Sources/ClassNoteCore', DEST / 'Core')
    shutil.copytree(ROOT / 'Packages/ClassNoteCore/Tests/ClassNoteCoreTests', DEST / 'CoreTests')
    resources = DEST / 'App/Resources'
    resources.mkdir()
    shutil.copytree(ROOT / 'Resources/Math', resources / 'Math')
    shutil.copy2(ROOT / 'Resources/PrivacyInfo.xcprivacy', resources / 'PrivacyInfo.xcprivacy')
    (DEST / 'Package.swift').write_text(MANIFEST, encoding='utf-8')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    # App identity, launch screen and scene metadata belong to AppleProductTypes.
    excluded = {'CFBundleExecutable', 'CFBundleIdentifier', 'CFBundleName',
                'CFBundleInfoDictionaryVersion', 'CFBundlePackageType', 'CFBundleDisplayName',
                'CFBundleShortVersionString', 'CFBundleVersion', 'LSRequiresIPhoneOS',
                'UIApplicationSceneManifest', 'UILaunchScreen', 'UISupportedInterfaceOrientations'}
    info = {key: value for key, value in info.items() if key not in excluded}
    (DEST / 'AppInfo.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
    (DEST.parent / 'LEGGIMI_IPAD.txt').write_text(GUIDE, encoding='utf-8')
    (DEST / 'README.md').write_text(GUIDE, encoding='utf-8')
    shutil.copy2(ROOT / 'LICENSE', DEST / 'LICENSE')
    print('Prepared:', DEST)


if __name__ == '__main__':
    prepare()
