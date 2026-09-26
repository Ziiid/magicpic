# Roadmap

Prioritetsordning för PictureApp. Se även `buggs.md` för hittade buggar
och `CLAUDE.md` för arkitektur/vägval.

## Klart

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
3e. ✅ Webbsökning utan API-nyckel (Google/Pinterest/ChatGPT öppnas i
   systemets webbläsare istället för ett Unsplash-anrop i appen) - se
   `WebSearchEngine`. Egen "Urklipp"-flik för att klistra in bilder
   (screenshots, eller kopierade bilder från sidor som ChatGPT vars
   sida inte stödjer native drag - se `buggs.md` 2026-09-25/26).
3f. ✅ Live förhandsvisning i "Justera"-panelen - en liten
   förhandsvisningsbild visas nu direkt i panelen istället för att man
   bara ser reglagen (rapporterat 2026-09-26, panelen täckte tidigare
   huvudbilden helt).
3g. ✅ Motivväljare när Vision hittar FLERA separata motiv (t.ex. två
   personer, eller en person + en hund) - `BackgroundRemovalService.
   detectSubjects(in:)` hämtar en mask PER instans (istället för bara en
   gemensam mask för alla, som tidigare), `SubjectPickerView` visar varje
   motiv som en färgad halvgenomskinlig overlay i sin faktiska form plus
   en tryckbar bock-markör, och `combinedMask(selecting:from:)` slår ihop
   de valda till en mask innan det befintliga bakgrunds-/form-flödet körs
   oförändrat. Väljaren visas ENDAST vid fler än ett motiv (annars
   fortsätter det gamla flödet direkt) och kan öppnas om senare via en
   "Motiv…"-knapp. Enmotivs-vägen bekräftad korrekt på enhet 2026-09-26
   (en bild med två personer nära varandra - Vision själv rapporterade
   bara EN sammanslagen instans, se "Kända begränsningar" i `CLAUDE.md`
   och `buggs.md` - väljaren ska då inte visas, och gjorde inte det).
   Själva väljar-UI:t (overlayer/markörer/"Motiv…"-knappen) är däremot
   ÄNNU INTE bekräftat på en bild där Vision faktiskt hittar flera
   instanser (t.ex. tydligt separerade motiv, eller person + husdjur) -
   testa det när ett sådant tillfälle uppstår.
3h. ✅ Dela via Meddelanden/Mail/AirDrop m.fl. och val av filformat
   (PNG/JPEG) - en ny "Dela"-knapp använder `ShareLink` mot en temporär
   fil (`SearchViewModel.refreshShareURL()`), rent SwiftUI så samma kod
   ger det native delningsarket på både Mac och iOS utan
   plattformsspecifik kod. Ny "Format"-meny (PNG med genomskinlighet,
   eller JPEG - som automatiskt läggs mot vit bakgrund eftersom JPEG
   saknar alfakanal, se `PlatformImage.exportData(as:)`) styr både
   "Spara" och "Dela". "Dra ut den färdiga bilden till Finder/en annan
   app" (den tredje delen av forna roadmap-punkt #10) är INTE med i den
   här omgången - se kvarvarande punkt nedan. Inte omtestad på enhet ännu.
3i. ✅ Granulär ångra/gör om ("Ångra"/"Gör om"-knappar) - täcker ALLT
   (bakgrund, form/positionering, filter, justeringar, motivval, manuell
   pensel-redigering) som EN gemensam historik i `SearchViewModel`
   (`EditSnapshot`/`undoStack`/`redoStack`). Ett tryck i en meny/på
   penseln räknas som ETT steg; att dra flera reglage i Justera-panelen
   eller bläddra flera filter i Filter-väljaren räknas ISTÄLLET som ETT
   steg för hela panel-sessionen (öppna→stäng), inte ett per utslag/tryck
   - `beginEditSession()`/`endEditSession()`, kopplat via `.onChange` i
   `DetailPanel` (fångar även nedswepning). Känd, medvetet accepterad
   ojämnhet: en sammansatt dra-/nyp-/vridgest i formramningen kan ge UPP
   TILL TRE undo-steg för EN fysisk gest (se kommentar vid
   `pushUndoSnapshot(overridingTransform:)` i `SearchViewModel.swift`) -
   att fixa hade krävt att röra den sköra sammansatta gesten i
   `ManipulableImageView`. Hittade och fixade samtidigt en riktig bugg
   (inte relaterad till undo/redo i sig) i `confirmSubjectSelection` - se
   `buggs.md` ("Att ändra motivval en andra gång gjorde ingenting"). Inte
   omtestad på enhet ännu.
3j. ✅ Visuell "80/20"-designspråk (80% Mac-/iOS-native, 20% egen
   personlighet på nyckel-actions) - `AppTheme`/`ToolbarChrome` (nya filer
   i `Support/`) ger `.nativeToolbar` (diskret, konturerad - Ångra/Gör
   om/Återställ, Form, Filter, Justera, Motiv, Finjustera) och
   `ToolbarChrome(tier: .hero)` (rundad pill i appens accentfärg, mjuk
   skugga, hover-lyft). Samma stil på BÅDA plattformarna (inget
   `#if os()`) - beslutat efter en interaktiv HTML-mockup (Artifact,
   eftersom SwiftUI inte går att förhandsgranska utan Xcode). SF Symbols
   i fyllda varianter på hero-knapparna, inga egna vektor-ikoner.
   Skärpt två gånger efter att användaren ifrågasatte den 2026-09-26:
   (1) Accentfärgen var initialt en påhittad terrakotta - rättad till
   Doxtail-grön (`#6aab8a`, samma som Persona/dog-id/dogish/doxtail-web,
   se `buggs.md`) efter att användaren påpekat att en etablerad
   varumärkesfärg redan fanns - och ALLA "aktivt/valt"-markörer i appen
   gjordes samtidigt konsekventa med samma gröna istället för
   `Color.accentColor` (systemets egen, användarberoende accentfärg, se
   `CLAUDE.md`). (2) Hero-listan kapades från tre (Bakgrund, Finjustera,
   Exportera) till BARA TVÅ (Bakgrund, Exportera) efter att `Form`/
   `Format` visade sig sakna sin native-stil helt (en riktig bugg, inte
   bara smaksak) och den ursprungliga hero-listan saknade en skarp
   motivering - regeln är nu appens egen enderadsbeskrivning i
   `CLAUDE.md`: "ta bort/byta bakgrund... och spara resultatet" är
   kärnlöftet, allt annat (inklusive pensel-finjustering, som KORRIGERAR
   snarare än utgör löftet) är stödjande och förblir native. Hårdkodade
   pixel-fontstorlekar (`size: 12.5`) bytta mot semantiska `.callout`-
   stilar som respekterar Dynamic Type/tillgänglighetsinställningar.
   Verktygsraden omstrukturerad till tre fasta, meningsfullt grupperade
   rader (historik / redigeringsverktyg / utdata) istället för fri
   radbrytning. Inte omtestad på enhet ännu.

## Kvar

5. Batch-bearbetning av flera bilder samtidigt. Ursprungligen tänkt som
   "flera markerade sökträffar" - INAKTUELL sedan sökresultat-rutnätet
   togs bort 2026-09-25 (webbsökning öppnar nu bara en webbläsarflik).
   Måste skrivas om till att gälla flera importerade/inklistrade bilder
   istället, t.ex. flera filer drag-and-droppade samtidigt (`handleDrop`
   tar idag bara `providers.first` - släpper man flera bilder samtidigt
   används bara den första, tyst).
6. Finder Quick Action för "Ta bort bakgrund" utan att öppna appen.
7. Exportförinställningar (produktbild, profilbild, Instagram-kvadrat osv.)
   - hänger ihop med rektangel-formens fasta bildproportion (PNG/JPEG
   finns redan, se 3h).
8. Innan/efter-jämförelse med skjutreglage.
10. Dra ut den färdiga bilden direkt till Finder/en annan app (resten av
    forna "Bättre export/delning" - dela och filformatval är klart, se
    3h ovan). Övervägdes men sköts upp: `.draggable(_:)`/`Transferable`
    hade krävt att läggas på den INTERAKTIVA formramningsytan
    (`SubjectFramingCanvas`), som redan äger en hårt förvärvad
    sammansatt dra-/nyp-/vridgest (se `CLAUDE.md`) - risk för
    gestkonflikt utan en egen, separat yta att dra ifrån (t.ex. en liten
    statisk miniatyr i verktygsraden).
11. Riktig Mac-meny (File/Edit-menykommandon, Cmd+O för att öppna en
    bild, Cmd+S för att spara) - appen saknar idag detta helt, vilket
    känns mindre "native" för en Mac-app tänkt att säljas.
