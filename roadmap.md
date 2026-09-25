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

## Kvar

4. Välja vilket motiv (av flera `VNInstanceMaskObservation`-instanser) som
   ska behållas. Kärnan i "ta bort bakgrund"-löftet när Vision hittar
   flera personer/objekt i samma bild - just nu behålls alla.
5. Batch-bearbetning av flera bilder samtidigt. Ursprungligen tänkt som
   "flera markerade sökträffar" - INAKTUELL sedan sökresultat-rutnätet
   togs bort 2026-09-25 (webbsökning öppnar nu bara en webbläsarflik).
   Måste skrivas om till att gälla flera importerade/inklistrade bilder
   istället, t.ex. flera filer drag-and-droppade samtidigt (`handleDrop`
   tar idag bara `providers.first` - släpper man flera bilder samtidigt
   används bara den första, tyst).
6. Finder Quick Action för "Ta bort bakgrund" utan att öppna appen.
7. Exportförinställningar (produktbild, profilbild, Instagram-kvadrat osv.)
   - hänger ihop med #10 (endast PNG idag) och rektangel-formens
   fasta bildproportion.
8. Innan/efter-jämförelse med skjutreglage.
9. Granulär ångra/gör om (Cmd+Z-historik för justeringar/filter/
   mask-redigering) - idag finns bara `restoreOriginal()`, ett
   allt-eller-inget-återställ till originalbilden.
10. Bättre export/delning - idag bara PNG via en explicit Spara-knapp.
    Saknar: dela via Messages/Mail/AirDrop (särskilt värdefullt på iOS),
    dra ut den färdiga bilden till Finder/en annan app, val av
    filformat/storlek.
11. Riktig Mac-meny (File/Edit-menykommandon, Cmd+O för att öppna en
    bild, Cmd+S för att spara) - appen saknar idag detta helt, vilket
    känns mindre "native" för en Mac-app tänkt att säljas.
