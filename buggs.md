# Buggar - hittade och fixade

Logg över buggar som upptäckts under utveckling, med symptom, rotorsak och
fix, så att liknande misstag inte upprepas. Nyast överst.

## 2026-09-26: Uppfann en egen accentfärg istället för att kolla den etablerade

**Symptom:** Byggde ett nytt "80/20"-designspråk för Mac-appen (verktygsrad
med diskreta nativa knappar + ett fåtal "hero"-actions i en accentfärg) och
valde en egen varm terrakotta (`#c96a4a`) som accentfärg, uppfunnen på
plats utan att fråga eller undersöka om användaren redan hade en
etablerad varumärkesidentitet. Användaren fick sedan uttryckligen peka ut
det: "kolla runt i repona! du har ju byggt tre appar åt mig och alla har
samma grön."

**Rotorsak:** Letade aldrig utanför `magicpic`-repot efter en etablerad
varumärkesfärg, trots att projektmappen ligger under `~/Doxtail-projekt/`
tillsammans med flera andra appar för samma användare/varumärke (Persona,
dog-id, dogish, doxtail-web m.fl.) - en enkel `grep` efter hex-koder/
"accent"/"primary" i systerprojekten hade hittat `#6aab8a` ("Primär
(salvia-grön)", uttryckligen dokumenterat i flera av de andra projektens
egna CLAUDE.md/AGENTS.md) på under en minut. Antog istället att en ny,
fristående app "får" en helt egen färg utan att det uttryckligen
efterfrågats.

**Fix:** `AppTheme.accent` bytt till `#6aab8a` (verifierat mot
`doxtail-web/src/App.css` och flera andra repons `--green`/"Primär"-
deklarationer). Passade även på att göra ALLA "aktivt/valt"-indikatorer
i appen konsekventa med samma gröna istället för `Color.accentColor`
(systemets egen, användarberoende accentfärg) - se `CLAUDE.md`s "Bakgrund
/ vägval som redan är tagna" för den fullständiga listan över vad som
ändrades och varför.

**Lärdom:** för EN användare som redan har flera egna produkter/appar i
angränsande projektmappar, anta ALDRIG att en ny app får en helt fri,
egen visuell identitet - sök igenom syskonprojekten (särskilt
`CLAUDE.md`/`AGENTS.md`/CSS-variabler/design-tokens-filer) efter en
redan etablerad varumärkespalett INNAN en accentfärg/logotyp/typsnitt
väljs, precis som man skulle läsa `buggs.md` innan man rör en riskfylld
del av EN app. "Vilken färg känns snygg" är fel fråga att ställa sig
själv när svaret redan finns dokumenterat någon annanstans.

## 2026-09-26: Att ändra motivval en andra gång ("Motiv…") gjorde ingenting

**Symptom:** Hittades INTE via manuell testning utan genom kodgranskning
när undo/redo-historiken byggdes och `cachedMask`-flödet spårades i
detalj. Scenario: användaren kör "Ta bort bakgrund" på en bild med flera
motiv, väljer t.ex. bara person 1 i motivväljaren - fungerar. Öppnar sedan
"Motiv…" igen och väljer istället bara person 2 (eller båda) - resultatet
hade INTE ändrats, den gamla (person 1-bara) bilden hade blivit kvar trots
ett nytt, bekräftat val.

**Rotorsak:** `confirmSubjectSelection(_:)` satte `selectedSubjectIDs`
till det nya valet och anropade `removeBackground()`, men rörde ALDRIG
`cachedMask`/`cachedMaskSource` - som sedan FÖRRA bekräftelsen redan
pekade på en giltig, ihopslagen mask för samma bild.
`removeBackground()`s egen snabbväg
(`if cachedMaskSource === original, let mask = cachedMask`) är designad
för att slippa köra om Vision när man bara byter bakgrundsstil/form/
filter - men den kollar bara "är det samma BILD", inte "är masken
fortfarande giltig för det AKTUELLA motivvalet". Den tolkade alltså det
nya motivvalet som "inget att göra, återanvänd cachad mask" och
komponerade om med FÖRRA valets mask.

**Fix:** `confirmSubjectSelection(_:)` nollställer nu explicit
`cachedMask`/`cachedMaskSource` INNAN `removeBackground()` anropas, så
snabbvägen aldrig kan slå till felaktigt - tvingar fram en riktig
omberäkning av den kombinerade masken (`combinedMask(selecting:from:)`,
billig - ingen ny Vision-analys behövs) för det nya valet.

**Lärdom:** en cache-nyckel baserad på "samma KÄLLA" (här: samma bild)
räcker inte om resultatet också beror på ett SEPARAT, föränderligt val
(här: vilka instanser som är valda) - varje plats som skriver till en
sådan cache måste själv ogiltigförklara den när just DEN datan ändras,
annars littar en annan käll-baserad snabbväg på fel data. Upptäcktes bara
för att en helt annan funktion (undo/redo) krävde att spåra exakt när och
var `cachedMask` faktiskt ändras - ett skäl att läsa igenom hela
dataflödet för ett fält när man bygger något som beror på det, inte bara
de ställen man TROR är relevanta.

## 2026-09-26: Motivväljaren frågar inte om två personer som står nära varandra

**Symptom:** Testade den nya motivväljaren (se `roadmap.md` 3g) på en bild
med två personer - väljaren dök aldrig upp, "Ta bort bakgrund" behöll bara
båda som vanligt, precis som innan funktionen fanns. Inte en synlig krasch
eller ett felmeddelande, bara tyst avsaknad av valet.

**Rotorsak:** INTE en bugg i `SubjectPickerView`/`SearchViewModel` - lade
till en tillfällig diagnostikutskrift (`[SubjectDetection]`, samma mönster
som `handleDrop`s `#if DEBUG`-loggning nedan) i
`SearchViewModel.removeBackground()` och bekräftade att
`VNGenerateForegroundInstanceMaskRequest` (Visions egen analys, INNAN vår
kod ens ser resultatet) själv bara rapporterade **EN** instans för den
testbilden, med en bounding box som täckte nästan hela bilden
(`(0.025, 0.025, 0.975, 0.975)`, dvs. ~2,5% marginal runt om). De två
personerna stod tätt ihop och fyllde bilden kant till kant - det absolut
vanligaste sättet att fotografera två personer tillsammans - och Vision
slog ihop dem till EN sammanhängande förgrundsyta. `detectSubjects`/
`removeBackground()` gjorde exakt vad som begärts ("Om bara ett motiv
hittas ska nuvarande flöde fortsätta utan extra steg") - problemet är att
Vision själv inte alltid RÄKNAR två tätt sammanslagna personer som två
motiv.

**Lärdom:** `VNGenerateForegroundInstanceMaskRequest` separerar
"instanser" genom VISUELL särskiljbarhet (kantdetektion/saliency), inte
person-medveten förståelse av "det här är två olika människor". Fungerar
pålitligt för tydligt fysiskt SEPARERADE motiv (en hund bredvid, inte
lutad mot, en person; två föremål med synligt mellanrum) men inte för
motiv som överlappar eller står i fysisk kontakt med varandra - oavsett om
de är semantiskt olika saker (två personer) eller ej. Det finns ingen
annan on-device Vision-API som gör personmedveten instanssegmentering
(`VNGeneratePersonSegmentationRequest` ger en enda sammanslagen
"alla-människor"-mask, inte per-person; `VNDetectHumanRectanglesRequest`
ger bara rektanglar, ingen pixelexakt mask). Se `CLAUDE.md` för en kort
notis om samma sak i "Kända begränsningar". Inte fixat, och sannolikt
inte fixbart utan en betydligt större, experimentell lösning (se
`roadmap.md`) - dokumenterat här så att samma undersökning inte görs om.

## 2026-09-25: Går inte att dra in en ChatGPT-genererad bild

**Symptom:** Efter att ha bytt webbsökning mot att öppna en riktig
sökmotor/ChatGPT i webbläsaren (se roadmap-anteckningen i `CLAUDE.md`)
gick det inte att dra bilden från ChatGPTs svar in i appen - draget gav
inget synligt fel, det verkade bara inte "ta" alls. Avgörande ledtråd:
SAMMA bild gick fint att dra till macOS Bilder-appen, vilket uteslöt den
första hypotesen (att ChatGPTs sida skulle blockera native HTML5-drag
med t.ex. `-webkit-user-drag: none`) - webbläsaren startade uppenbarligen
ett giltigt drag, så felet måste ligga i hur VÅR app tog emot det.

**Rotorsak:** `ContentView.handleDrop` provade bara EN representations-
typ och antog att den alltid gick att ladda - den kollade
`hasItemConformingToTypeIdentifier(.fileURL)`, och om det var sant
returnerade den `true` (= "hanterat") direkt, UTAN att vänta på att
`loadItem`s asynkrona callback faktiskt gav ett giltigt resultat. Ett
Safari-drag av en bild annonserar ofta en fil-URL som ett asynkront
"fil-löfte" (`NSFilePromiseReceiver`-protokollet) - den enkla
`loadItem`-vägen förhandlar inte det protokollet, så `Self.url(from:)`
kunde ge `nil` TYST. Koden gav då aldrig bildobjekt- eller URL-
representationen en chans, trots att de fanns kvar som alternativ och
troligen hade fungerat. Bilder-appen (en fullständig AppKit-app som
implementerar löftesprotokollet fullt ut) lyckades därför med samma
drag som vår förenklade `.onDrop`-hantering misslyckades med.

**Fix, försök 1 (otillräckligt):** Fick `handleDrop` att falla igenom
till nästa representationstyp (fil-URL → bildobjekt → vanlig URL) OM en
tidigare typ annonserades men gav ett tomt/nil-resultat vid den faktiska
laddningen. Löste INTE problemet - fortfarande omöjligt att dra in
ChatGPT-bilden. Diagnosticerade vidare: "Kopiera bild" i webbläsaren +
"Klistra in bild" (`PlatformImage.fromPasteboard()`) fungerade PERFEKT,
vilket visade att bilddata/mottagningskoden i övrigt var helt OK - felet
satt isolerat i just fil-URL-vägen. Insikten: en sekventiell
fallback-kedja hjälper bara om den tidigare typens callback FAKTISKT
KALLAS (även med `nil`) - ett Safari-drag av en bild annonserar ofta en
fil-URL som ett asynkront "fil-löfte" (`NSFilePromiseReceiver`-
protokollet), och provar man den via den enkla `loadItem`-vägen kan den
i värsta fall HÄNGA SIG HELT utan att någonsin kalla sin callback - då
når exekveringen aldrig fram till nästa steg i en sekventiell kedja,
hur många fallbacks man än lägger till efteråt.

**Fix, försök 2 (löste det):** Byggde om `handleDrop` till att starta
ALLA tillgängliga representationstyper (bildobjekt, fil-URL, vanlig URL)
SAMTIDIGT/parallellt istället för i tur och ordning, med en liten
`DropClaim`-hjälpklass (låst med `NSLock`, eftersom callbacken för varje
typ kan komma tillbaka på olika bakgrundstrådar) som ser till att bara
DEN FÖRSTA som faktiskt svarar med ett giltigt resultat vinner och
importerar bilden. En hängande fil-URL-callback blockerar då inte längre
de andra, snabbare vägarna. Behöll även "Klistra in bild"
(`SearchViewModel.pasteFromClipboard()`) som en helt oberoende reservväg
för de fall INGEN representation alls går att ladda.

**Lärdom (försök 1-2):** En sekventiell fallback-kedja ("prova A, faller
den igenom till B") antar implicit att A:s callback ALLTID kallas, om än
med `nil` vid fel - det stämmer inte för asynkrona "löftes"-baserade
representationer, som kan hänga sig helt istället för att misslyckas
tydligt. När en åtgärd kan HÄNGA SIG (inte bara lyckas/misslyckas), kör
alternativen PARALLELLT och låt den snabbaste vinna, istället för
sekventiellt. En jämförelsepunkt som "det funkar till EN annan app (t.ex.
Bilder) men inte hit" är ett starkt tecken på att problemet sitter i
mottagarens hantering, inte i avsändarens sida. Och: när en första fix
INTE löser ett rapporterat problem, fråga efter ett konkret, isolerande
test (här: "fungerar klistra in, som går via en helt annan kodväg?")
innan man gissar en andra gång - det avgjorde exakt var felet satt.

**Bekräftad slutgiltig orsak (2026-09-26):** trots att bildobjekt/
fil-URL/URL/rå-bilddata NU provades parallellt (och `.onDrop` breddades
till att acceptera vilken typ som helst), gick det FORTFARANDE inte att
dra in bilden - och avgörande: det gick att dra samma bild från den
fristående ChatGPT Mac-appen, bara inte från webbläsaren. Lade till en
2-sekunders diagnostisk timeout som visar `provider.
registeredTypeIdentifiers` i UI:t om inget lyckas - den avslöjade att
ChatGPTs webbsida bara annonserar en `dyn.xxx`-identifierare (en
"dynamisk" UTI - macOS eget substitut när ingen riktig UTI är
registrerad) och `com.apple.WebKit.custom-pasteboard-data`. Det senare
är WebKits typ för sidor som bygger sin EGEN dragpayload i JavaScript
(`dataTransfer.setData(...)` med en egen, godtycklig datatyp) istället
för att låta webbläsaren dra själva bildelementet - ett opakt, sidinternt
format som INGEN app utanför sidan kan tolka. Det här är alltså inte en
bugg i vår `.onDrop`/`NSItemProvider`-kod alls, utan en begränsning i hur
ChatGPTs webbsida är byggd - ingen mängd klientkod kan koda sig runt det.
"Klistra in"-fliken (`PlatformImage.fromPasteboard()`, går via webbläsarens
"Kopiera bild" - den riktiga bildbufferten, INTE sidans anpassade
dragkod) är den korrekta, PERMANENTA lösningen för just den sortens sida,
inte en tillfällig reservväg. UI-texterna i `ContentView.swift`
uppdaterade för att säga det rakt ut istället för att antyda att drag
"kanske" fungerar.

**Slutlärdom:** När flera oberoende, tekniskt korrekta fixförsök i rad
inte hjälper, sluta gissa och bygg in mätbar diagnostik (här:
`provider.registeredTypeIdentifiers` i ett synligt felmeddelande) istället
för en femte gissning - den gav svaret direkt. Vissa "buggar" är inte
buggar i den egna koden alls utan en begränsning hos en extern part
(här: en webbsidas egen, icke-standardiserade drag-implementation) - då
är rätt fix inte "mer drop-hanteringskod" utan en fungerande ALTERNATIV
väg (klistra in), presenterad som den avsedda lösningen för det fallet
istället för en gömd reservknapp.

---

## 2026-09-25: EditableMask antog fel pixelformat - penseln trasig/fel plats

**Symptom:** Efter att ha fixat koordinatmappningen (se posten nedan)
fungerade penseln i "Finjustera" fortfarande inte - träffade fortfarande
fel plats, och "Lägg till"/"Ta bort" gav samma (synliga) resultat, som att
läget inte spelade någon roll.

**Rotorsak:** `EditableMask.init(copying:)` KOPIERADE de råa bytesen från
Visions mask-`CVPixelBuffer` rakt av, i vad den ANTOG var samma format som
källan redan hade (`CVPixelBufferGetPixelFormatType(source)`), och
`paint(at:radius:adding:)` skapade sedan en `CGContext` som HÅRDKODAR
`bitsPerComponent: 8` + `DeviceGray`-färgrymd. Det här var redan
identifierat som en overifierad risk (se `CLAUDE.md`, "Kända
begränsningar"): om källbufferten inte faktiskt var 8-bitars gråskala
skulle antingen `CGContext`-skapandet misslyckas tyst (ingen effekt av
penseln alls), eller - värre - lyckas men tolka fel sorts bytes (t.ex. ett
flyttalsformat) som gråskale-pixlar, vilket skulle sprida ut/förskjuta
"målningen" över fel platser i bufferten på ett sätt som ser slumpmässigt
och positionsfel ut, och göra "lägg till"/"ta bort" oskiljbara eftersom
båda bara producerar brus i data som ändå tolkas fel vid kompositering.
Den vanliga bakgrundsborttagningen (`BackgroundRemovalService`) drabbades
ALDRIG av detta eftersom den läser masken via `CIImage(cvPixelBuffer:)`,
som självt känner av och tolkar buffertens faktiska pixelformat korrekt -
bara den handskrivna, rå `CGContext`-vägen i `EditableMask`/`paint` gissade.

**Fix:** `EditableMask.init(copying:)` skapar nu ALLTID kopian i ett känt,
fixerat format (`kCVPixelFormatType_OneComponent8`) och fyller den via
`CIContext.render(_:to:bounds:colorSpace:)`, som konverterar automatiskt
FRÅN källans verkliga format oavsett vilket det är - ingen gissning kvar.
Se `EditableMask.swift`.

**Lärdom:** En kod-kommentar/riskanteckning om ett overifierat antagande
("inte testat på enhet ännu") är inte samma sak som att antagandet är
säkert bara för att koden kompilerar och andra, näraliggande vägar (som
råkar gå via ett format-medvetet API som `CIImage`) fungerar - ett
symptom som "träffar fel plats" eller "gör samma sak oavsett läge" är en
stark signal att undersöka just den flaggade, overifierade risken FÖRST,
innan man letar efter nya buggar i närliggande, redan verifierad
geometri/koordinat-kod.

---

## 2026-09-25: Penseln i mask-editorn målade på fel ställe

**Symptom:** I "Finjustera"-penselverktyget (`MaskEditorView`) hamnade
ändringen till VÄNSTER om där man faktiskt målade - penselcirkeln (den
visuella markören) visades på rätt plats under fingret/muspekaren, men
själva masken uppdaterades någon annanstans.

**Rotorsak:** `imagePoint(from:...)` räknade om en klickpunkt i
containerns koordinater till en bildpixel genom att anta att bilden
fyller HELA `containerSize`. Men bilden visas med
`.aspectRatio(contentMode: .fit)`, vilket brevlådar (letterboxar) den med
tomrum centrerat på sidorna eller upptill/nedtill så fort bildens
proportion inte exakt matchar containerns kvadratiska yta - t.ex. alla
liggande eller stående bilder. Mappningen `(unscaledX / containerSize.width)
* maskSize.width` ignorerade det tomrummet helt, så resultatet blev
förskjutet med precis brevlådans bredd/höjd. `brushCursor`-cirkeln (som
bara ritas vid rå `location`, oberoende av den här uträkningen) visades
däremot alltid rätt, vilket dolde att den UNDERLIGGANDE målningen låg fel.

**Fix:** Lade till `aspectFitSize(for:in:)` som räknar ut bildens
FAKTISKA visningsstorlek/position inom containern (samma logik som
`scaledToFill`-varianten i `CanvasTransform` löser för ett annat
letterbox-liknande problem), och lät `imagePoint` subtrahera det
centrerade tomrummet (`imageOrigin`) innan klickpunkten skalas till
maskens pixelkoordinater. `pixelRadius`-uträkningen i `paint(at:...)`
använde av samma anledning `displaySize.width` istället för
`containerSize.width`. Se `MaskEditorView.swift`.

**Lärdom:** En visuell markör som ritas direkt vid den RÅA klickpunkten
(ingen transform-matte) kan se helt korrekt ut även när den FAKTISKA
träffytan (som går via en separat, felaktig koordinat-uträkning) inte är
det - lita inte på att en gest "ser rätt ut" bara för att en overlay-
indikator hamnar rätt, verifiera separat att den underliggande
koordinatmappningen stämmer, särskilt runt `.aspectRatio(contentMode:
.fit)` där innehållet ofta INTE fyller hela sin behållare.

---

## 2026-09-25: Att bara VÄLJA en form triggade riktig bakgrundsborttagning

**Symptom:** Redigerade man bilden (t.ex. ljusstyrka/filter under
"Justera"/"Filter") och sedan valde en form i formmenyn (kvadrat → cirkel
osv.), utan att någonsin ha bett om bakgrundsborttagning, "försvann"
bakgrunden (blev genomskinlig).

**Rotorsak:** `setOutputShape` anropade `removeBackground()` ovillkorat,
med motiveringen "av samma anledning som `setBackgroundStyle`" - men till
skillnad från bakgrundsstil har formvalet redan en synlig effekt UTAN
riktig bearbetning, eftersom `SubjectFramingCanvas`/`ManipulableImageView`
klipper direkt till vald form via SwiftUI-bindningen till `outputShape`.
Att ändå ovillkorat köra `removeBackground()` startade en riktig
Vision-körning med standardbakgrunden (genomskinlig) bara av att välja
form i menyn - exakt samma bugg som "Enbart panorering triggade riktig
bakgrundsborttagning" nedan, fast för formmenyn istället för dra-gesten.

**Fix:** `setOutputShape` kör numera `removeBackground()` villkorat av
`if processedImage != nil`, precis som `commitOutputShapeTransform`. Se
`SearchViewModel.swift`.

**Lärdom:** "Explicit val ska alltid tillämpas direkt"
(`setBackgroundStyle`-resonemanget) gäller bara när valet annars INTE har
någon synlig effekt alls. Formvalet hade redan en synlig effekt (klippning
i formramningen) utan att Vision behövde köras - kontrollera alltid om ett
UI-val redan syns via en billig, ren SwiftUI-bindning innan man antar att
det måste trigga den dyra bearbetningen för att "göra något".

---

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
