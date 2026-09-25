# PictureApp (magicpic)

En app för att söka efter bilder, ta bort/byta bakgrund med ett klick, och
spara resultatet. Ett Xcode-projekt med två mål som delar affärslogik:

- **PictureApp-macOS** – Mac-appen
- **PictureApp-iOS** – iPhone/iPad-appen

Delad kod (modeller, services, view models, SwiftUI-vyer) ligger i det
lokala Swift-paketet `Packages/PictureAppCore`, som båda apparna beror på.
Endast sådant som faktiskt skiljer sig mellan plattformarna (app-entry,
spara/exportera-flödet) ligger i `App/macOS` respektive `App/iOS`.

Se även `buggs.md` - en logg över hittade buggar med rotorsak och fix.
Läs den innan du ändrar bildinläsning, gester eller
bakgrund/form-pipelinen, så samma misstag inte görs igen.

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
- Interaktiva pinch/dra/vrid-gester (motivets formramning, bakgrunds-
  positionering, mask-penseln) byggs med SwiftUIs inbyggda `DragGesture`/
  `MagnifyGesture`/`RotateGesture` (se `ManipulableImageView`) - de
  fungerar identiskt med styrplatta/mus på Mac och touch på iPhone/iPad
  utan plattformsspecifik kod. De tre slås ihop till EN sammansatt gest med
  `.simultaneously(with:)` och sätts med ETT `.gesture(...)`-anrop -
  separata `.gesture`/`.simultaneousGesture`-anrop (tidigare mönster,
  användes för `MagnificationGesture`) levererade inte nyp-/
  rotationshändelser pålitligt i praktiken. Skjutreglage för zoom/rotation
  finns som reserv i `ImagePositionerView` ifall gestigenkänningen ändå
  strular på en viss enhet. Undersökte `Persona`-repot
  (`/Users/tobiasair/Doxtail-projekt/Persona`, `useDraggableTransform.js`)
  som referens - det är en webb-app (React/Capacitor) som handrullar
  pekar-event-matte eftersom webbläsare saknar de gesterna inbyggt, så
  koden går inte att återanvända, bara designmönstren (en gest ger både
  skala och rotation från samma två pekpunkter, snap-feedback en gång per
  "snäpp", committa bara vid gestens slut - inte per pointermove, skilja
  tap från manipulation).
- Motivets formramning (dra/zooma/vrida för att passa en form) är verksam
  DIREKT när en bild laddats in - inte gated bakom att trycka "Ta bort
  bakgrund" eller byta bakgrund. `SearchViewModel.outputShape` är därför
  `.square` som standard, inte `.rectangle` - annars finns ingen ram att
  positionera bilden inom förrän man aktivt valt en form. Se
  `SubjectFramingCanvas` i `DetailPanel.swift`.
- Måla/navigera-lägen (se `MaskEditorView`) hålls som ett uttryckligt
  segmentval, inte en gemensam gest som försöker gissa avsikt - enfingers
  drag betyder olika saker i respektive läge (måla vs. panorera) och att
  låta dem tävla om samma gest är svårt att få pålitligt rätt.

## Kända begränsningar / risker att hålla koll på

- Alla bilder normaliseras till upprätt EXIF-orientering vid inläsning
  (`PlatformImage.normalizedOrientation(from:)`/`.normalizedOrientation()`
  i `PlatformImage.swift`) INNAN de når Vision/CoreImage-pipelinen.
  `cgImage`/`cgImage(forProposedRect:...)` returnerar bildens RÅA
  sensor-orientering utan hänsyn till EXIF-taggen - `UIImage`/`NSImage`
  visar bilden rätt själva (de respekterar taggen vid ritning), men
  `BackgroundRemovalService`/`ShapeCropService` går via
  `cgImageRepresentation`, som tappar den. En stående bild kunde därför
  plötsligt hamna liggande så fort den bearbetats en gång (upptäckt
  2026-09-25). Alla inläsningsvägar (sökresultat, filimport/drag-and-drop,
  `PhotosPicker`, kamerafångst på båda plattformarna) går nu igenom
  normaliseringen - lägg till nya bildkällor där också.
- `EditableMask` (penseln i `MaskEditorView`) antar att Visions
  mask-`CVPixelBuffer` är 8-bitars gråskala (`kCVPixelFormatType_OneComponent8`).
  Stämmer det inte skulle `CGContext`-skapandet i `paint(at:radius:adding:)`
  kunna misslyckas tyst (ingen synlig effekt av penseln, inget felmeddelande).
  Inte verifierat på enhet ännu.
- Den sammansatta dra/nyp/vrid-gesten i `ManipulableImageView` (se ovan)
  ersatte ett tidigare mönster (separata `.gesture`/`.simultaneousGesture`-
  anrop med `MagnificationGesture`) som rapporterades inte reagera alls på
  varken pekplatta på Mac eller nyp på iPhone/iPad. Nyp (zoom) och vridning
  bekräftat fungerande på riktig hårdvara 2026-09-25. `CanvasTransform.
  clampedOffset` hade dessutom en bugg som fick panoreringen att "hoppa"
  tillbaka vid gestens slut (klampen räknade bara med zoomnivån, inte med
  att bilden redan svämmar över containern olika mycket beroende på sin
  egen proportion) - fixad samma dag, inte omtestad på enhet ännu.
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
3c. ✅ Bildkorrigeringar (ljusstyrka, kontrast, mättnad, temperatur,
   highlights/shadows, skärpa, brusreducering, vinjett) -
   `ImageAdjustmentService`/`ImageAdjustmentsView`. Tillämpas på
   originalbilden INNAN Vision-analysen/bakgrundsborttagningen (se
   `SearchViewModel.removeBackground()`), så de blir en del av fotot
   självt - Vision-masken cachas ändå mot den OJUSTERADE originalbilden,
   eftersom en färgjustering inte ändrar motivets kontur.
3d. ✅ Färdiga bildstilar/filter (svartvitt, sepia, röntgen, krom, blekt,
   serietidning, värmekamera, poster, polaroid) - `PhotoFilterService`/
   `PhotoFilterPickerView`, byggda uteslutande på Apples inbyggda
   CIFilter-namn (samma filter Bilder-appens eget filterval använder).
   Körs FÖRE bildkorrigeringarna i samma pre-Vision-steg som 3c.

Kvar:
4. Välja vilket motiv (av flera `VNInstanceMaskObservation`-instanser) som
   ska behållas.
5. Batch-bearbetning av flera markerade sökträffar.
6. Finder Quick Action för "Ta bort bakgrund" utan att öppna appen.
7. Exportförinställningar (produktbild, profilbild, Instagram-kvadrat osv).
8. Innan/efter-jämförelse med skjutreglage.
