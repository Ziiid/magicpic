# PictureApp

En app för att söka efter bilder, ta bort/byta bakgrund med ett klick och
spara resultatet. Xcode-projekt med två mål: **PictureApp-macOS** och
**PictureApp-iOS**, som delar all affärslogik.

## Funktioner

- **Skaffa en bild** – antingen sök på webben (Unsplash), välj en bild från
  Foton via systemets egen bildväljare, ta en ny bild med kameran, eller dra
  in en bildfil direkt (Finder/Bilder/webbläsare).
- **Ta bort/byta bakgrund** – helt på enheten med Apples Vision-ramverk
  (`VNGenerateForegroundInstanceMaskRequest`). Ingen nätuppkoppling eller
  extern tjänst behövs. Bakgrunden kan vara transparent, en färg, en
  oskärpa av originalet, eller en egen bild (som går att panorera/zooma).
- **Finjustera urklippet för hand** – pensel för att lägga till eller ta
  bort delar av masken, med zoom/pan för precision (t.ex. hårstrån Vision
  missade).
- **Formbeskärning** – klipp slutbilden till kvadrat, cirkel, avrundad
  kvadrat, hexagon eller oktagon.
- **Spara** – exportera som PNG (NSSavePanel på Mac, till Foton-biblioteket
  på iOS).

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
   Access Key. Den sparas krypterat i macOS/iOS nyckelring.

_Tidigare användes Google Custom Search, men det krävde en omständlig
uppsättning via Google Cloud Console. Bing Image Search API är inte
längre ett alternativ - Microsoft stängde hela Bing Search API-familjen
den 11 augusti 2025._

## Om "Egen bild"

Att välja en bild från Foton går via systemets inbyggda bildväljare
(`PhotosPicker`), inte en egen sökning i biblioteket – appen ber aldrig om
full åtkomst till Foton-biblioteket, bara till den enskilda bild du själv
väljer. Det ersatte en tidigare egenbyggd filnamns-/albumsökning i Foton,
som togs bort eftersom en riktig bildväljare (som i bilder-appar typ
SayFrame) är både enklare att använda och mer privat.

## Bygga och köra

Kräver fullständig Xcode (inte bara Command Line Tools) och
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
open PictureApp.xcodeproj
```

Välj schemat `PictureApp-macOS` eller `PictureApp-iOS` och kör (⌘R) från
Xcode. Signering sköts automatiskt (`Automatic signing`) – välj ditt Team
under **Signing & Capabilities** första gången.

Projektet genereras från `project.yml` via XcodeGen, inte handredigerat.
Kör om följande efter ändringar i `project.yml`, eller när filer/mappar
läggs till eller tas bort under `App/macOS` eller `App/iOS`:

```bash
xcodegen generate
```

## Projektstruktur

```
project.yml                        – XcodeGen-spec, genererar PictureApp.xcodeproj
Packages/PictureAppCore/           – delad Swift-paket-modul
  Sources/PictureAppCore/
    Models/                        – datamodeller (SearchResultItem, BackgroundOption, OutputShape, CanvasTransform)
    Services/
      UnsplashImageSearchService.swift  – webbsökning via Unsplash
      BackgroundRemovalService.swift    – bakgrundsborttagning/-byte (Vision)
      ShapeCropService.swift            – formbeskärning av slutbilden
    Support/
      SettingsStore.swift          – lagrar inställningar
      KeychainHelper.swift         – säker lagring av API-nyckel i nyckelringen
      PlatformImage.swift          – NSImage/UIImage-brygga för delad kod
      PlatformColor.swift          – NSColor/UIColor-brygga (SwiftUI Color -> CGColor)
      ImageExporter.swift          – protokoll för plattformsspecifikt sparande
      EditableMask.swift           – muterbar mask för penselverktyget
    ViewModels/
      SearchViewModel.swift        – all state och logik
    Views/                         – ContentView, ResultThumbnail, DetailPanel, SettingsView,
                                      BackgroundPositionerView, MaskEditorView, CameraCaptureView
App/
  macOS/                           – app-entry + NSSavePanel-baserad export
  iOS/                             – app-entry + export till Foton-biblioteket
```

Se [CLAUDE.md](CLAUDE.md) för arbetsregler och funktions-roadmap.
