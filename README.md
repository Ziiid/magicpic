# PictureApp

En enkel macOS-app för att söka efter bilder, ta bort bakgrunden med ett
klick och spara resultatet.

## Funktioner

- **Sökning** – växla mellan "Webb" (bildsökning via Unsplash) och "Foton"
  (ditt lokala Foton-bibliotek). Sökningen visar flera alternativa
  träffar i ett rutnät.
- **Ta bort bakgrund** – helt på enheten med Apples Vision-ramverk
  (`VNGenerateForegroundInstanceMaskRequest`). Ingen nätuppkoppling eller
  extern tjänst behövs, och det är normalt klart på under en sekund.
- **Spara** – spara vald bild (med eller utan bakgrund) som PNG var du vill
  på datorn.

## Krav för webbsökning: Unsplash Access Key

Webbsökningen använder Unsplash (unsplash.com/developers) för bildsökning.
Gratisnivån ger 50 sökningar/timme, vilket räcker gott för vanligt bruk.
Ingen kreditkorts- eller Cloud Console-uppsättning krävs, bara ett konto.

1. Gå till https://unsplash.com/developers och logga in eller skapa ett
   gratiskonto.
2. Klicka **"Your apps"** → **"New Application"**, godkänn villkoren och
   ge appen ett namn (t.ex. "PictureApp").
3. Kopiera värdet **"Access Key"** som visas på appens sida.
4. Starta PictureApp, klicka på kugghjulet bredvid sökfältet och klistra in
   Access Key. Den sparas krypterat i macOS nyckelring.

_Tidigare användes Google Custom Search, men det krävde en omständlig
uppsättning via Google Cloud Console. Bing Image Search API är inte
längre ett alternativ - Microsoft stängde hela Bing Search API-familjen
den 11 augusti 2025._

## Om den lokala Foton-sökningen

Apples publika ramverk för Foton (PhotoKit) erbjuder inte fri
innehållsbaserad sökning som "hitta bilder med en hund" – den funktionen
är intern i Foton-appen och inte tillgänglig för tredjepartsappar. Den
lokala sökningen i PictureApp matchar istället mot **filnamn** och
**albumnamn**. En tom sökning visar dina senaste bilder.

Första gången du söker i Foton frågar macOS om behörighet – godkänn det
för att appen ska kunna visa dina bilder.

## Bygga och köra

Kräver Xcode Command Line Tools (redan installerat) – ingen fullständig
Xcode-installation behövs.

### Snabb utveckling

```bash
./run.sh
```

Bygger och startar appen direkt via Swift Package Manager. Bra för snabb
iteration under utveckling.

### Skapa en riktig .app att dubbelklicka på

```bash
./build.sh
open PictureApp.app
```

Detta bygger en release-version, paketerar den som `PictureApp.app` och
signerar den ad-hoc (lokalt, utan Apple-utvecklarkonto) så att den kan
begära Foton-behörighet korrekt. Du kan dra `PictureApp.app` till din
`Program`-mapp eller Dock.

**Obs:** eftersom appen är ad-hoc-signerad (inte med ett riktigt
utvecklarcertifikat) kan macOS be om Foton-behörighet på nytt varje gång
du bygger om appen. Det är en engångsklickning per bygge, inget att oroa
sig för.

## Projektstruktur

```
Sources/PictureApp/
  PictureAppApp.swift        – app-startpunkt
  ContentView.swift          – huvudvy: sökfält + rutnät + detaljpanel
  ResultThumbnail.swift      – en bildruta i sökresultaten
  DetailPanel.swift          – förhandsvisning + knappar för bakgrund/spara
  SettingsView.swift         – inställningar för Unsplash Access Key
  SearchViewModel.swift      – all state och logik
  Models/                    – datamodeller
  Services/
    UnsplashImageSearchService.swift  – webbsökning via Unsplash
    PhotosSearchService.swift         – sökning i Foton-biblioteket
    BackgroundRemovalService.swift    – bakgrundsborttagning (Vision)
  Support/
    SettingsStore.swift      – lagrar inställningar
    KeychainHelper.swift     – säker lagring av API-nyckel i nyckelringen
    NSImage+PNG.swift        – hjälpfunktion för att exportera PNG
```
