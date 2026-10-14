# AirisPlan Rilievo — app iPhone con RoomPlan

App iOS che rileva le stanze con Apple RoomPlan (LiDAR) e produce lo scheletro semantico per AirisPlan.
Tutto lo sviluppo avviene su Windows: il codice qui, la compilazione su un Mac in cloud di GitHub Actions,
l'installazione sull'iPhone dal PC con Sideloadly.

## Cosa produce ogni rilievo

Cartella `File > Su questo iPhone > AirisPlan Rilievo > Rilievi > <data-ora>/`:

| File | Contenuto |
|---|---|
| `skeleton.json` | contratto AirisPlan v1, `source: roomplan-app`, Z up, altezze dal pavimento, non ancora allineato alla nuvola |
| `roomplan.json` | il modello RoomPlan completo (Codable di Apple) |
| `modello.usdz` | modello parametrico (muri, aperture, arredi dal catalogo) |
| `mesh.usdz` | mesh scansionata |
| `traiettoria.csv` | posa della camera a 10 Hz con tempo di sistema e tempo ARKit, per l'allineamento con lo S20 |
| `riepilogo.txt` | conteggi |

Flusso in app: **Nuovo rilievo** → scansiona → **Fine stanza** → **Altra stanza** (stessa ARSession, stesso sistema di coordinate) oppure **Termina rilievo** → salvataggio → **Condividi i file**.

## Struttura

```
app/project.yml          definizione del progetto Xcode (XcodeGen lo genera sul runner)
app/Sources/*.swift      il codice
.github/workflows/       compilazione automatica a ogni push, produce AirisPlanCapture-unsigned.ipa
```

## Prima volta: da fare una sola volta

1. **Repository GitHub** (privato va bene): crealo vuoto su github.com, poi da questa cartella:
   ```
   git remote add origin https://github.com/<utente>/airisplan-capture.git
   git push -u origin master
   ```
2. **GitHub Actions** parte da solo al push. Nella scheda *Actions* del repository, apri l'esecuzione e scarica l'artefatto `AirisPlanCapture-ipa` (uno zip con dentro la IPA). I minuti macOS del piano gratuito bastano per circa 15–20 compilazioni al mese; se non bastano, si passa a Codemagic (500 minuti gratis).
3. **Sul PC Windows**: installa iTunes dal sito Apple (non quello del Microsoft Store) e [Sideloadly](https://sideloadly.io). Collega l'iPhone con il cavo, "Autorizza" sul telefono, apri iTunes una volta.
4. **Sull'iPhone**: dopo la prima installazione, Impostazioni → Privacy e sicurezza → Modalità sviluppatore → attiva (il telefono si riavvia). Poi Impostazioni → Generali → VPN e gestione dispositivi → fidati del tuo Apple ID.

## Ogni versione

1. Modifica il codice, `git commit`, `git push`.
2. Aspetta la compilazione (8–15 minuti), scarica la IPA dagli artefatti.
3. Sideloadly: trascina la IPA, inserisci il tuo Apple ID, Start. Con l'Apple ID gratuito l'app vale 7 giorni e va reinstallata; Sideloadly può rinnovarla da solo se il telefono è raggiungibile.

## Limiti noti

- Serve un iPhone con LiDAR (Pro) e iOS 17 o successivo.
- RoomPlan non misura lo spessore dei muri: `thickness` è `null`, lo misura il motore sulla nuvola.
- `polygonCorners` dei pavimenti: l'app decide da sola se sono in coordinate locali o del mondo e lo scrive in `polygon_frame`. Da verificare sul primo rilievo vero.
- La prima compilazione può fallire per errori di sintassi: il codice è scritto senza Xcode. Il log è nell'artefatto `build-log`.
