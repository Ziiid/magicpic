# PictureApp (magicpic)

Appens SYNLIGA namn (appikonens text, fönstertitel, behörighetsdialoger) är
**XtraPic** sedan 2026-09-28 (hette kort "Pixxikon" 2026-09-26 innan dess) -
bara `INFOPLIST_KEY_CFBundleDisplayName` och användarsynliga strängar
bytta, på uttrycklig begäran. Projektnamnet, target-namnen och
mappstrukturen nedan är MEDVETET kvar som "PictureApp"/magicpic - inte
bytta ännu, inte ett misstag. Fråga användaren innan du byter någon av dem
också.

Bundle-ID är **`com.tobias.pictureapp` för BÅDA målen** (Mac och iOS) sedan
2026-09-28 - medvetet ändrat från det tidigare `.ios`-suffixet på
iOS-målet, så att appen kan ha EN gemensam app-post i App Store Connect
("one app, multiple platforms") istället för två separata. Ändra INTE
tillbaka till skilda bundle-ID:n utan att fråga - det stänger av den
gemensamma app-posten.

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
bakgrund/form-pipelinen, så samma misstag inte görs igen. Se även
`roadmap.md` för vad som är klart och kvar, i prioritetsordning.

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
- UI-text, felmeddelanden och kodkommentarer skrivs på **svenska** i
  KÄLLKODEN (kodkommentarer alltid, och varje sträng skrivs som sin
  svenska text - det är NYCKELN i String Catalog, se nedan) - i linje med
  resten av appen. Detta är oberoende av att appen sedan 2026-09-28 visas
  på ENGELSKA som standard för slutanvändaren (se "Lokalisering
  (svenska/engelska)" nedan) - dev-språket och appens default visningsspråk
  är alltså medvetet olika saker.
- Signering: `CODE_SIGN_STYLE: Automatic`, inget hårdkodat `DEVELOPMENT_TEAM`.
  Användaren väljer sitt Team i Xcodes Signing & Capabilities-flik.
  OBS: `xcodegen generate` RADERAR det valda Teamet ur `.xcodeproj` (det ligger
  bara där, inte i `project.yml`) - kontrollera/välj Team igen efter varje körning
  (Team-ID `3873522W2D` lades senast tillbaka för hand i pbxproj 2026-10-14).

## Lokalisering (svenska/engelska)

Appen har en egen språkväxel i Inställningar (kugghjulet i sökfältet,
`SettingsView`/`ContentView.appLanguage`) - HELT oberoende av enhetens
systemspråk. **Default är ENGELSKA**, inte svenska (uttryckligen begärt
2026-09-28 - appens namn/filterstilar är redan engelska, och App
Store-distribution är global).

- **Källan för allt** är EN String Catalog:
  `Packages/PictureAppCore/Sources/PictureAppCore/Localizable.xcstrings`
  (`sourceLanguage: sv`, nyckeln ÄR den svenska källtexten). `Package.swift`
  deklarerar den som en resurs (`resources: [.process("Localizable.xcstrings")]`)
  och sätter `defaultLocalization: "sv"`.
- **`AppLanguage`** (`Models/AppLanguage.swift`) är modellen - `.current`
  läser UserDefaults-nyckeln `"appLanguage"` DIREKT (samma nyckel som
  `ContentView`s `@AppStorage`) för kod UTAN tillgång till SwiftUI-miljön
  (modeller/services, t.ex. `PhotoFilter.label`).
- **UPPDATERAT 2026-10-14:** `L(...)` slår numera upp mot RÄTT SPRÅKS egen
  `.lproj` (`AppLanguage.bundle`) för engelska, och mot en obefintlig tabell
  för svenska (nyckeln ÄR då texten) - `String(localized:locale:)`s
  `locale`-parameter väljer INTE pålitligt språk (den faller tillbaka på
  enhetens språk). Skriv därför ALDRIG `String(localized:..., bundle:
  .module, locale:...)` direkt - använd `L(...)`. `DetailPanel` bygger om
  sig vid språkbyte via `.id(appLanguage)` i `ContentView` (texter slås upp
  vid rendering, inte via miljön). Se `buggs.md` 2026-10-14.
- **EN enda lokaliseringsväg - `L("Svensk text")`** (`Models/Localized.swift`,
  bara en kort stavning av `String(localized:bundle:.module,locale:
  AppLanguage.current.locale)`). Detta gäller BOKSTAVLIGEN VARJE
  användarsynlig sträng, inklusive vanliga `Text(...)`/`Label(...)`/
  `Button(...)`/`.help(...)`/`Picker(...)`/`Toggle(...)`-anrop i en View -
  skriv alltså `Text(L("Svensk text"))`, INTE `Text("Svensk text")`.
  **VIKTIGT, felaktigt antaget första gången (2026-09-28) och korrigerat
  efter att användaren visade en skärmdump där översättningen tyst
  uteblev:** SwiftUI slår INTE automatiskt upp en bokstavlig
  `Text("...")`/`LocalizedStringKey` mot paketets EGNA String Catalog -
  utan en uttrycklig `bundle:`-parameter letar den bara i `Bundle.main`
  (app-targetens egen bundle, inte `PictureAppCore`s), och `.environment(
  \.locale, ...)` löser INTE det problemet (den styr bara VILKET språk
  som väljs UR en redan hittad bundle, inte VILKEN bundle som söks).
  `Text` har visserligen en `bundle:`-parameter man kan sätta manuellt,
  men `Label`/`Button`/`.help`/`Picker`/`Toggle`/`TextField`/`ProgressView`/
  `ColorPicker`/`confirmationDialog`/`navigationTitle`s enkla
  bekvämlighets-initierare exponerar OFTA ingen sådan parameter alls - så
  den enda mönstret som fungerar ÖVERALLT, konsekvent, är att förresolva
  till en vanlig `String` via `L(...)` VID ANROPSSTÄLLET och skicka den
  strängen vidare (varje sådan SwiftUI-API har en `String`/`StringProtocol`-
  baserad överlagring som bara visar texten rakt av, vilket är korrekt när
  texten redan är lokaliserad).
- **Samma fälla gäller en `String`-parameter till en ÅTERANVÄNDBAR vy**
  (t.ex. `ImagePositionerView(title: String, ...)`,
  `ImageAdjustmentsView.slider(_ title: String, ...)`,
  `BackgroundStylePickerView.Option.label: String?`) som sedan visas via
  `Text(title)`/`Label(title, ...)` INUTI vyn - lös INTE detta genom att
  byta parametertypen till `LocalizedStringKey` (provat och backat 2026-09-28,
  se ovan - `LocalizedStringKey` har SAMMA `Bundle.main`-problem, och många
  SwiftUI-API:er saknar en `bundle:`-parameter att sätta på den ändå).
  Rätt fix: låt parametern förbli `String`, och lös upp texten med
  `L(...)` VID ANROPSSTÄLLET (t.ex. `ImagePositionerView(title: L("Justera
  bakgrundsbilden"), ...)` i `DetailPanel.swift`) - vyn själv visar sedan
  bara den redan färdiga strängen.
- En ternary DIREKT inuti `Text(...)`/`.help(...)` (t.ex.
  `Text(a ? "X" : "Y")`) tvingar Swift att slå ihop båda grenarna till EN
  gemensam typ INNAN `Text`s överlagringar väljs - skriv om som `if/else`
  med var sin `Text(L("..."))`, eller lös upp båda grenarna explicit med
  `L(...)`/tomsträng före modifiern (se `SubjectPickerView`s `.help(...)`).
- En sträng med INTERPOLERAD data (t.ex. `\(error.localizedDescription)`
  eller `\(selected.count)`) kan INTE vara nyckeln direkt i en
  `String(localized:)`/`L(...)`-anrop om datan varierar per anrop (då
  matchar den aldrig en fast katalogpost) - UNDANTAGET är räkne-
  interpolationer (`Int`, via `LocalizedStringKey`/`String.LocalizationValue`s
  egen interpolationshantering, extraherad som `%lld`-platshållare i
  katalogen, se `SubjectPickerView`s "X av Y motiv valda") - de fungerar
  fint eftersom "plats + antal" är EN stabil mening. För fri text (ett
  felmeddelande, ett filternamn) - dela istället upp i en FAST, lokaliserad
  prefix-sträng + rådata konkatenerad EFTER lokaliseringen (se
  `SearchViewModel`s felmeddelanden och `PhotoFilterService.runFilter`).
- **Servicefelen** (`RemovalError`/`FilterError`/`ShapeError`/`AdjustmentError`,
  alla `{ let message: String }`) lokaliseras CENTRALT i respektive
  `errorDescription` via `String(localized: String.LocalizationValue(message), ...)`
  - en runtime-nyckel, INTE en bokstavlig sträng - så inget enskilt
    `throw ...(message: "...")`-ställe (över 40 stycken) behövde skrivas om
    för hand. Undantag: meddelanden som redan innehåller INTERPOLERAD data
    (t.ex. ett filternamn) kan inte matcha en fast katalogpost - dela då upp
    i en lokaliserad, FAST prefix-sträng + rådata konkatenerad EFTER
    lokaliseringen (se `PhotoFilterService.runFilter`).
- **App-target-undantag**: `App/macOS/MacImageExporter.swift`/
  `App/iOS/IOSImageExporter.swift` ligger i ANDRA moduler än
  `PictureAppCore`, så `bundle: .module` där skulle peka fel katalog. Deras
  få felmeddelanden hämtas istället från `Support/ExporterMessages.swift`
  (delad, `PictureAppCore`-lokaliserad).
- **Uttryckligt UNDANTAG, INTE i scope**: `NSCameraUsageDescription`,
  `NSPhotoLibraryAddUsageDescription` och `CFBundleDisplayName` i
  `project.yml` visas av OS:ET (behörighetsdialoger, appnamnet på
  Hemskärmen/Dock) INNAN appens egen UI ens körs, och följer ENHETENS
  systemspråk - INTE vår egen in-app-växel. De förblir alltid svenska/
  "XtraPic" oavsett vad `AppLanguage` är satt till, om inte en riktig
  Info.plist-lokalisering (ett separat, mindre projekt) läggs till senare.
- Ett par väldigt sällsynta, aldrig-observerade felvägar (bl.a.
  `"Kunde inte skapa filtret \(name)."` om ett hårdkodat CIFilter-namn
  skulle sluta finnas - se `CLAUDE.md`s regel om att alltid verifiera
  CIFilter-namn) och den interpolerade "X av Y motiv valda"-texten i
  `SubjectPickerView` byggdes/verifierades utan möjlighet att köra Xcodes
  egen extraktion - flaggade som extra värda att dubbelkolla vid första
  riktiga testet av engelskt läge.

## Verifiering just nu: bara Mac

Användaren verifierar SEDAN 2026-09-29 ENDAST på Mac ("vi har inte ens börjat
med mobil"). Allt måste därför gå att göra med bara en mus - trackpad-gester
(nyp/vrid) får aldrig vara den enda vägen (därav +/−/↺/↻-knapparna och
enfingershandtaget på text/logotyp). Koden hålls plattformsoberoende SwiftUI,
men iOS-beteende (t.ex. gester i `ScrollView`) är otestat.

Text och logotyp (`TextOverlay`/`LogoOverlay`, lager i `Views/OverlayLayers.swift`)
är relativa till kanvasen och ritas i `applyPipeline` FÖRE formens siluett
(logotyp först, text överst). Förhandsvisning (SwiftUI) och export
(`TextOverlayService`/`LogoOverlayService`, CoreText/CoreGraphics) MÅSTE ge
samma placering - ändra alltid båda. `SearchViewModel` är `@MainActor`:
statiska hjälpare som körs i `Task.detached` måste vara `nonisolated`.

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

- Motivväljaren (flera motiv i `removeBackground()`, se `roadmap.md` 3g)
  frågar bara när `VNGenerateForegroundInstanceMaskRequest` SJÄLV
  rapporterar fler än en instans - bekräftat 2026-09-26 med diagnostik
  (tillfällig `[SubjectDetection]`-loggning i `SearchViewModel.
  removeBackground()`, `#if DEBUG`): Vision separerar instanser genom
  VISUELL särskiljbarhet, inte personmedveten förståelse, så två personer
  som står tätt ihop/fyller bilden kant till kant (det vanligaste sättet
  att fotografera två personer tillsammans!) slås ofta ihop till EN
  instans redan i Visions egen analys - väljaren visas då aldrig, precis
  som för en bild med bara ett motiv, fast det egentligen är två. Fungerar
  pålitligt för TYDLIGT fysiskt separerade motiv (en hund bredvid, inte
  lutad mot, en person). Ingen känd fix - `VNGeneratePersonSegmentationRequest`
  ger bara en enda sammanslagen mask, inte per person. Se `buggs.md`
  ("Motivväljaren frågar inte om två personer som står nära varandra") för
  hela undersökningen.
- Drag-and-drop av en bild FRÅN chatgpt.com (webbläsaren, inte den
  fristående Mac-appen) in i appen fungerar INTE, och går inte att fixa
  klientsidan - bekräftat 2026-09-26 med diagnostik
  (`provider.registeredTypeIdentifiers`): sidan annonserar bara en
  `dyn.xxx`-UTI och `com.apple.WebKit.custom-pasteboard-data`, WebKits
  typ för en sidas EGEN, JavaScript-byggda dragpayload
  (`dataTransfer.setData(...)`) - ett opakt format ingen app utanför
  sidan kan tolka. Använd "Klistra in bild"-knappen under Webb/AI istället (Urklipp-fliken togs bort) (högerklick →
  "Kopiera bild" i webbläsaren går via den riktiga bildbufferten, inte
  sidans dragkod) - det är den avsedda, permanenta lösningen för den här
  sortens sida, inte en tillfällig reservväg. Se `buggs.md`
  ("Går inte att dra in en ChatGPT-genererad bild") för hela
  diagnosresan. Om andra webbkällor senare rapporteras ha samma problem,
  kolla samma sak (diagnostikloggen i `handleDrop` finns kvar i
  `#if DEBUG`) innan du antar att det är samma orsak.
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
- `EditableMask` (penseln i `MaskEditorView`) antog tidigare att Visions
  mask-`CVPixelBuffer` redan var 8-bitars gråskala
  (`kCVPixelFormatType_OneComponent8`) och memcpy:ade de råa bytesen rakt
  av - stämde det inte kunde `CGContext`-skapandet i
  `paint(at:radius:adding:)` misslyckas tyst eller tolka fel sorts bytes
  som gråskale-pixlar (penseln träffade fel plats, "lägg till"/"ta bort"
  blev oskiljbara). Fixat 2026-09-25: kopian görs nu alltid om till
  `kCVPixelFormatType_OneComponent8` via `CIContext.render`, som
  konverterar från källans faktiska format oavsett vilket det är - se
  `buggs.md`. Inte omtestad på enhet ännu.
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

- **Appens enda accentfärg är Doxtail-grön, `#6aab8a` (`AppTheme.accent` i
  `PictureAppCore/Support/AppTheme.swift`)** - SAMMA salvia-gröna som
  redan används genomgående i övriga Doxtail-appar (dog-id/Dogish/
  Persona/doxtail-web, dokumenterat som "Primär (salvia-grön)" i deras
  egna CLAUDE.md/AGENTS.md) - inte en ny färg uppfunnen för just den här
  appen (en tidigare session gjorde precis det misstaget, se
  `buggs.md` 2026-09-26). Grönt signalerar ALLTID "aktivt/valt/primärt"
  (hero-knappar, valt filter, valt motiv, drop-target-highlight, vald
  bakgrundsfärgs markering) - `Color.accentColor` (systemets egen,
  användarberoende accentfärg) ska ALDRIG användas, exakt av det skälet.
  `AppTheme.onAccent` är den varma off-white:en (`#faf9f7`, INTE rent
  vitt) att lägga OVANPÅ `accent`. Hitta INTE på en ny ton om en annan
  session/uppgift vill ändra något visuellt - fråga användaren istället
  om det verkligen är tänkt att avvika från den etablerade paletten.
  Den faktiska app-ikonen (`AppIcon.appiconset`/`AppLogo.imageset`) bytt
  2026-09-28 till en ny logga - ett glansigt 3D-"X" (blått→lila på ena
  diagonalen, orange→gult på den andra) med en vit bildram-ikon (berg + sol)
  ovanpå, som matchar appnamnet XtraPic. INTE grön - ett MEDVETET avsteg
  från syskonapparnas gröna ikonfärg (den gamla ikonen var ändå en egen,
  ljusare neon-lime `#cdfc3a`, så appens ikon har ALDRIG delat exakt samma
  ton som UI-accentfärgen ovan) - användarens eget val av ny logga, inte
  något en session hittade på. UI-accentfärgen (`AppTheme.accent`,
  salvia-grönt) är OFÖRÄNDRAD och används fortfarande i hela appen som
  förut - bara själva ikonen/loggan är blå/lila/orange nu.
- **Verktygsradens knappar följer ett "80/20"-designspråk** (`ToolbarChrome`
  i `PictureAppCore/Support/`): de flesta kontrollerna är diskreta,
  konturerade `.nativeToolbar`-knappar, men EXAKT EN kontroll - Exportera
  (Spara+Dela, `exportCluster` i `DetailPanel.swift`) - får en rundad pill i
  accentfärgen (`ToolbarChrome(tier: .hero)`). Bakgrund var tidigare också
  hero (motiverat med appens enderadsbeskrivning - "ta bort/byta
  bakgrund... och spara resultatet") men flyttades till native 2026-09-26
  på uttrycklig begäran - användaren vill BARA ha Spara/Dela gröna, allt
  annat (Bakgrund, Form, Filter, Justera, Motiv, Finjustera/pensel) ska se
  ut precis som Filter/Justera. Utöka INTE hero-listan till mer än
  Exportera utan att uttryckligen fråga användaren först - se `buggs.md`
  2026-09-26 för hur listan redan krympt två gånger (tre → två → en) efter
  granskning/begäran.
- Webbsökning: appen anropar INGEN bildsöks-API längre (Unsplash togs
  bort 2026-09-25). Istället öppnas en riktig webbkälla
  (`WebSearchEngine`: Google/Pinterest för att SÖKA, ChatGPT - via
  `chatgpt.com/?q=...`, som förifyller promptrutan - för att SKAPA en ny
  bild) i systemets webbläsare med användarens sökterm/prompt - ingen
  API-nyckel, inga stockbilds-begränsningar, riktiga sökresultat eller en
  riktig AI-genererad bild. Användaren drar in bilden den hittar/skapar
  direkt i appen (`ContentView`s `.onDrop` hanterar redan fjärr-URL:er
  och rå bilddata från en webbläsare, inte bara lokala filer) - UTOM för
  ChatGPT (se "Kända begränsningar" nedan, dess sida stödjer inte native
  drag för bilder, klistra in behövs där). Anledning till bytet: Unsplash
  Access Key krävde att VARJE slutanvändare skaffade en egen nyckel
  (opraktiskt för en app som ska säljas) och gav bara begränsade
  stockbilder, inte riktiga sökresultat eller AI-generering. Övervägde
  men valde bort: Google Custom Search API (kräver Cloud
  Console-uppsättning + nyckel per installation eller en egen
  backend-proxy för att hemlighålla nyckeln - mer att bygga/drifta än
  bara en deep-link).
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
- Projektet var tidigare ett rent SPM-paket (byggt med `swift build` +
  manuellt `build.sh`-skript) eftersom det utvecklades på en Mac mini med
  bara Xcode Command Line Tools. Det är nu ersatt av det riktiga
  Xcode-projektet ovan; den gamla scaffoldingen är borttagen.

Se `roadmap.md` för funktions-roadmapen (klart/kvar, i prioritetsordning).
