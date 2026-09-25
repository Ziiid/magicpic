# Buggar - hittade och fixade

Logg över buggar som upptäckts under utveckling, med symptom, rotorsak och
fix, så att liknande misstag inte upprepas. Nyast överst.

## 2026-09-25: Enbart panorering triggade riktig bakgrundsborttagning

**Symptom:** Bakgrunden "försvann" (blev genomskinlig) bara av att dra i
bilden för att positionera/rama in den - INNAN man någonsin bett om
bakgrundsborttagning via knapp eller meny.

**Rotorsak:** Föregående fix av "bakgrundsval gör inget"-buggen (se nedan)
gjorde `commitOutputShapeTransform()` - som körs varje gång en dra-/nyp-/
rotationsgest släpps i den inbäddade formramningen - ovillkorat anropande
av `removeBackground()`. Det innebar att en RENT KOMPOSITIONELL åtgärd
(bara flytta/zooma/rotera bilden för att rama in den) tyst startade en
riktig Vision-körning med standardbakgrunden (genomskinlig), trots att
användaren aldrig bett om att ta bort bakgrunden än.

**Fix:** `commitOutputShapeTransform()` kör bara om bearbetningen villkorat
- `if processedImage != nil` - till skillnad från `setBackgroundStyle`/
`setOutputShape`, som ÄR explicita "gör det här nu"-val och därför alltid
ska köra om. Se `SearchViewModel.swift`. Lade samtidigt till en
"Återställ"-knapp (`restoreOriginal()`) som kastar bort alla val och går
tillbaka till originalbilden.

**Lärdom:** Skilj på "ren komposition/positionering" (bör vara billigt och
overksamt tills användaren uttryckligen bett om bearbetning) och
"explicit val av bakgrund/form" (bör alltid tillämpas direkt) - att
behandla dem likadant (båda ovillkorat, eller båda villkorat) missar den
ena eller andra sidan av samma UX-problem. Den här bytte plats med
föregående bugg nedan - läs båda för att se hur pendeln svängde för långt
åt andra hållet.

## 2026-09-25: EXIF-orientering tappades bort vid bearbetning

**Symptom:** En stående bild (t.ex. från kameran eller webben) hamnade
plötsligt liggande så fort den bearbetats en gång (bakgrund borttagen/
formbeskuren). Märktes först som "bilden lägger sig horisontellt när jag
drar" - men drag-gesten var oskyldig, det var bearbetningen som triggades
av draget som avslöjade buggen.

**Rotorsak:** `UIImage`/`NSImage` visar bilder rättvända själva (de
respekterar EXIF-orienteringstaggen när de ritas), men `.cgImage`/
`cgImage(forProposedRect:...)` - som hela Vision-/CoreImage-kedjan
(`BackgroundRemovalService`, `ShapeCropService`) går via - returnerar
bildens RÅA sensororientering utan hänsyn till den taggen. En `CGImage` i
sig har ingen uppfattning om EXIF-rotation. Bearbetningen körde alltså
tyst om bilden i sin råa orientering.

**Fix:** Normalisera (baka in rotationen i pixeldatan) EN gång, vid
inläsning, innan bilden når bearbetningskedjan -
`PlatformImage.normalizedOrientation(from:)` / `.normalizedOrientation()`
i `Packages/PictureAppCore/Sources/PictureAppCore/Support/PlatformImage.swift`,
via ImageIO (`CGImageSourceCopyPropertiesAtIndex` + `kCGImagePropertyOrientation`)
och CoreImage (`CIImage.oriented(_:)`). Alla inläsningsvägar uppdaterade:
sökresultat, fil-import/drag-and-drop, `PhotosPicker`, kamerafångst på
både Mac och iOS.

**Lärdom:** Varje gång en bild går från `UIImage`/`NSImage` till `CGImage`
(eller `CIImage`) för bearbetning, kontrollera om orienteringsmetadata kan
tappas bort på vägen - särskilt i kod som fungerat "bra hittills" bara för
att den råkat testas med redan rättvända bilder.

---

## 2026-09-25: Panorering "hoppade" tillbaka vid gestens slut

**Symptom:** Ville visa absolut översta delen av en (särskilt stående)
bild genom att dra den dit - under själva draget hamnade den rätt, men vid
släpp hoppade bilden tillbaka mot mitten istället för att stanna kvar.

**Rotorsak:** `CanvasTransform.clampedOffset` räknade den tillåtna
pan-gränsen bara utifrån zoomnivån (`containerSize * (scale-1) / 2`),
INTE utifrån att bilden redan svämmar över den kvadratiska/formade ramen
olika mycket beroende på sin EGEN bildproportion (en stående bild i en
kvadratisk ram fyller ut höjden mer än bredden redan vid scale=1). Gränsen
blev därför för snäv jämfört med vad som faktiskt syntes under det
oklampade, levande draget.

**Fix:** `clampedOffset` tar nu även `imageSize` och räknar ut bildens
faktiska "cover"-storlek (samma logik som `scaledToFill` använder för
slutbilden) innan gränsen sätts. Se
`Packages/PictureAppCore/Sources/PictureAppCore/Models/CanvasTransform.swift`.

**Lärdom:** En klampningsgräns för en "aspect fill"-yta måste alltid
räkna med källbildens EGEN proportion, inte bara med användarens zoom -
annars stämmer inte gränsen överens med vad som faktiskt renderas.

---

## 2026-09-25: Nyp/rotation reagerade inte alls på riktig hårdvara

**Symptom:** Zoom (nyp) och rotation fungerade inte varken med pekplatta
på Mac eller tvåfingersnyp på iPhone/iPad, trots att koden "borde"
fungera och kompilerade utan fel.

**Rotorsak:** Gesterna sattes med SEPARATA `.gesture(...)`- och
`.simultaneousGesture(...)`-anrop (`DragGesture` via `.gesture`,
`MagnificationGesture` via `.simultaneousGesture`) - det mönstret levererar
inte pålitligt nyp-/rotationshändelser i praktiken, trots att det ser ut
som en rimlig SwiftUI-idiom.

**Fix:** Slå ihop alla tre gesterna (`DragGesture`, `MagnifyGesture`,
`RotateGesture` - de moderna iOS17/macOS14-ersättarna för
`MagnificationGesture`/`RotationGesture`) till EN sammansatt gest med
`.simultaneously(with:)`, satt via ETT enda `.gesture(...)`-anrop. Se
`Packages/PictureAppCore/Sources/PictureAppCore/Views/ManipulableImageView.swift`.
Skjutreglage för zoom/rotation lades också till som en garanterat
fungerande reserv i `ImagePositionerView`, ifall gestigenkänningen ändå
strular på en viss enhet.

**Lärdom:** "Kompilerar och ser rimligt ut" är inte samma sak som
"fungerar på riktig hårdvara" för SwiftUI-gester - flera samtidiga
tvåfingersgester (nyp + rotation) bör kedjas ihop till EN gest istället
för att sättas som separata `.gesture`/`.simultaneousGesture`-modifiers.

---

## 2026-09-25: Bakgrundsval "gjorde inget" förrän man redan bearbetat en gång

**Symptom:** Valde man färg/oskärpa/transparent som bakgrund INNAN man
tryckt "Ta bort bakgrund" en första gång hände ingenting synligt - valet
sparades bara tyst. Tryckte man "Ta bort bakgrund" EFTERÅT dök det valda
läget upp, vilket kändes som att appen krävde en dold, specifik
klicksekvens för att fungera.

**Rotorsak:** `setBackgroundStyle`/`setOutputShape` körde bara om
bearbetningen (`removeBackground()`) villkorat av `if processedImage !=
nil` - dvs. bara om ett urklipp redan fanns sedan tidigare.

**Fix:** Ta bort villkoret - `removeBackground()` körs numera alltid
(den no-opar redan ofarligt om ingen bild är inläst). Se
`Packages/PictureAppCore/Sources/PictureAppCore/ViewModels/SearchViewModel.swift`.

**Lärdom:** En kontroll som "uppdaterar om ett resultat redan finns" är
lätt att glömma bort gäller även det ALLRA FÖRSTA valet, innan något
resultat någonsin producerats - fundera på om villkoret borde vara
"finns det en bild att bearbeta" istället för "finns det redan ett
resultat".

---

## 2026-09-25: "Justera position" fick bakgrunden att se bortklippt/återställd ut

**Symptom:** Ett separat "Justera position…"-läge växlade huvudvyn
tillbaka till den OBEHANDLADE originalbilden (med sin ursprungliga
bakgrund kvar) för att kunna positionera om motivet - vilket visuellt såg
ut som att den borttagna bakgrunden "kom tillbaka".

**Rotorsak:** Positioneringsytan visade `originalImage` (bilden FÖRE
bakgrundsborttagning), inte den bakgrundskompositerade versionen, eftersom
ingen mellanbild (komposit men inte ännu formbeskuren) fanns tillgänglig
att visa istället.

**Fix:** Lade till `SearchViewModel.compositedImage` - motivet mot vald
bakgrund men INTE formbeskuret än - och gjorde positioneringsytan
permanent inbäddad (inget separat läge/knapp att växla till) som alltid
visar `compositedImage ?? originalImage`. Se `DetailPanel.swift` och
`SearchViewModel.swift`.

**Lärdom:** En "positionera om"-vy ska visa samma visuella resultat som
användaren redan sett (med rätt bakgrund), inte hoppa tillbaka till ett
tidigare bearbetningssteg - annars tolkas det som att en åtgärd
"ångrades" även om inget faktiskt gick förlorat.
