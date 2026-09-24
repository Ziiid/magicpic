# PictureApp (magicpic)

En app för att söka efter bilder, ta bort/byta bakgrund med ett klick, och
spara resultatet. Ett Xcode-projekt med två mål som delar affärslogik:

- **PictureApp-macOS** – Mac-appen
- **PictureApp-iOS** – iPhone/iPad-appen

Delad kod (modeller, services, view models, SwiftUI-vyer) ligger i det
lokala Swift-paketet `Packages/PictureAppCore`, som båda apparna beror på.
Endast sådant som faktiskt skiljer sig mellan plattformarna (app-entry,
spara/exportera-flödet) ligger i `App/macOS` respektive `App/iOS`.

## Arbetsregler

- **Bygg och testa aldrig via `xcodebuild`/simulator på egen hand.**
  Användaren har fullständig Xcode och ett betalt Apple Developer-konto och
  sköter all bygge och testning själv. Gör kodändringar, förklara vad som
  ändrats, och låt användaren verifiera i Xcode. Kör bara ett byggkommando
  om användaren uttryckligen ber om det.
- Projektet regenereras från `project.yml` via **XcodeGen**
  (`xcodegen generate`) – redigera `project.yml` för target-inställningar,
  bundle-ID, Info.plist-nycklar osv., inte `.xcodeproj` för hand. Kör
  `xcodegen generate` efter ändringar i `project.yml` eller när nya
  källfiler/mappar läggs till i `App/macOS` eller `App/iOS`.
- UI-text, felmeddelanden och kodkommentarer skrivs på **svenska**, i linje
  med resten av appen.
- Signering: `CODE_SIGN_STYLE: Automatic`, inget hårdkodat `DEVELOPMENT_TEAM`.
  Användaren väljer sitt Team i Xcodes Signing & Capabilities-flik.

## Arkitektur för plattformsdelning

- `PlatformImage` (i `PictureAppCore/Support/PlatformImage.swift`) är en
  typealias till `NSImage`/`UIImage` beroende på plattform, med delade
  extensions (`cgImageRepresentation`, `pngData()`, `Image(platformImage:)`)
  så att Vision-bearbetning och SwiftUI-vyer kan skrivas en gång.
- Att spara/exportera bilden skiljer sig helt mellan plattformarna
  (NSSavePanel på Mac, Foton-biblioteket på iOS) och görs därför bakom
  protokollet `ImageExporter`, med en konkret implementation per apptarget
  (`MacImageExporter`, `IOSImageExporter`) som injiceras i `SearchViewModel`.
- Lägg ny plattformsoberoende logik i `PictureAppCore`. Lägg bara kod i
  `App/macOS` eller `App/iOS` när den verkligen kräver AppKit/UIKit-API:er
  som inte kan abstraheras bort enkelt.
- Interaktiva pinch/dra-gester (bakgrundspositionering, mask-penseln) byggs
  med SwiftUIs inbyggda `DragGesture`/`MagnificationGesture` - de fungerar
  identiskt med styrplatta/mus på Mac och touch på iPhone/iPad utan
  plattformsspecifik kod. Undersökte `Persona`-repot
  (`/Users/tobiasair/Doxtail-projekt/Persona`) som referens, men det är en
  webb-app (React/Capacitor) som handrullar pekar-event-matte eftersom
  webbläsare saknar de gesterna inbyggt - koden går inte att återanvända,
  bara designmönstren (snap-feedback en gång per "snäpp", committa bara vid
  gestens slut - inte per pointermove, skilja tap från manipulation).
- Måla/navigera-lägen (se `MaskEditorView`) hålls som ett uttryckligt
  segmentval, inte en gemensam gest som försöker gissa avsikt - enfingers
  drag betyder olika saker i respektive läge (måla vs. panorera) och att
  låta dem tävla om samma gest är svårt att få pålitligt rätt.

## Kända begränsningar / risker att hålla koll på

- `EditableMask` (penseln i `MaskEditorView`) antar att Visions
  mask-`CVPixelBuffer` är 8-bitars gråskala (`kCVPixelFormatType_OneComponent8`).
  Stämmer det inte skulle `CGContext`-skapandet i `paint(at:radius:adding:)`
  kunna misslyckas tyst (ingen synlig effekt av penseln, inget felmeddelande).
  Inte verifierat på enhet ännu.
- Penseln komponerar om (den dyra CoreImage-renderingen) bara när ett
  penseldrag SLUTAR, inte under själva draget - under draget syns bara en
  ring som markerar penselstorlek/läge, inte den faktiska masken som
  uppdateras live. Medvetet vald avvägning för prestanda.
- `CameraCaptureView`s macOS-gren (`AVCaptureSession` +
  `AVCaptureVideoPreviewLayer` i ett `NSViewRepresentable`) är helt
  otestad på riktig hårdvara - det är egenskriven kod eftersom AppKit
  saknar en färdig "ta en bild"-panel (till skillnad från
  `UIImagePickerController` på iOS). Mest sannolika felkällor: kamera-
  behörighet under App Sandbox (kräver BÅDE
  `com.apple.security.device.camera`-entitlement OCH
  `NSCameraUsageDescription`, redan tillagda) och `AVCaptureDevice.default(for:.video)`
  som kan ge `nil` om Mac:en saknar/blockerar kamera.

## Bakgrund / vägval som redan är tagna

- Webbsökning: **Unsplash API**, inte Google Custom Search (för krångligt
  med Cloud Console) eller Bing (hela Bing Search API-familjen stängdes ner
  2025-08-11).
- Egen bild: valdes bort från en egenbyggd filnamns-/albumsökning i Foton
  (PhotoKits publika API stöder ingen fri innehållsbaserad sökning som
  "hitta bilder med en hund" - det är en intern Foton-appsfunktion) till
  förmån för systemets native bildväljare (`PhotosPicker`/`PhotosUI`), som
  fungerar precis likadant på macOS och iOS, inte kräver full
  Foton-behörighet (bara den valda bilden delas med appen), och matchar
  referens-UX:et i SayFrame-appen (tidigare "Persona"-repot). Kamerafångst
  finns som ett tredje alternativ bredvid webbsökning och Foton.
- Bakgrundsborttagning: helt på enheten med Vision
  (`VNGenerateForegroundInstanceMaskRequest` + `CIBlendWithMask`), inget
  moln/API.
- Unsplash Access Key sparas krypterat i nyckelringen (Keychain), aldrig i
  klartext.
- Projektet var tidigare ett rent SPM-paket (byggt med `swift build` +
  manuellt `build.sh`-skript) eftersom det utvecklades på en Mac mini med
  bara Xcode Command Line Tools. Det är nu ersatt av det riktiga
  Xcode-projektet ovan; den gamla scaffoldingen är borttagen.

## Funktions-roadmap (prioritetsordning)

Klart:
1. ✅ Byta bakgrund (transparent / färg / oskärpa / egen bild, med
   pan/zoom-positionering av den egna bilden).
2. ✅ Dra in egna bildfiler (Finder/Bilder/webbläsare) för bearbetning.
3. ✅ Manuell finjustering av masken (pensel för att lägga till/ta bort,
   med zoom/pan för precision) - `MaskEditorView`.
3b. ✅ Formbeskärning av slutbilden (kvadrat/cirkel/avrundad kvadrat/
   hexagon/oktagon) - `ShapeCropService`. Allt utom rektangel beskär
   automatiskt till kvadrat först.

Kvar:
4. Välja vilket motiv (av flera `VNInstanceMaskObservation`-instanser) som
   ska behållas.
5. Batch-bearbetning av flera markerade sökträffar.
6. Finder Quick Action för "Ta bort bakgrund" utan att öppna appen.
7. Exportförinställningar (produktbild, profilbild, Instagram-kvadrat osv).
8. Innan/efter-jämförelse med skjutreglage.
