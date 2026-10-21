### Zdroje dat

- **Hranice EVL** – AOPK ČR, datová sada [Evropsky významné lokality](`r meta$sources$evl$page`) (ESRI shapefile v S-JTSK), poslední změna hranic `r fmt_date(meta$evl_updated)`, staženo `r fmt_date(meta$sources$evl$downloaded)`. Licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.cs), © AOPK ČR.
- **Předměty ochrany** – AOPK ČR, [seznam předmětů ochrany lokalit Natura 2000, stav 2/2025](`r meta$sources$features$url`) (xlsx), staženo `r fmt_date(meta$sources$features$downloaded)`.
- **Modelovaný biotop** – vrstvy `r paste0("\x60", unlist(meta$sources$habitat), "\x60", collapse = " a ")`: polygony KVES s modelovou pravděpodobností výskytu druhu (WGS 84).
- **Nálezová data** – AOPK ČR, [Nálezová databáze ochrany přírody (NDOP)](`r meta$sources$ndop$page`), nálezy obou druhů od `r fmt_date(meta$ndop$date_from)`, exportováno balíčkem R [rndop](https://github.com/kalab-oto/rndop) `r fmt_date(meta$sources$ndop$downloaded)` (nejnovější nález `r fmt_date(meta$ndop$last_record)`). Licence [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.cs), © AOPK ČR.
- **Podkladové mapy** – © přispěvatelé OpenStreetMap; letecké snímky Esri World Imagery.

### Souřadnicový systém

Všechny geometrické operace a výpočty ploch probíhají v systému S-JTSK / Krovak East North (EPSG:`r meta$crs_work`) na nezjednodušených geometriích. Mapa na této stránce zobrazuje tytéž geometrie převedené do WGS 84 (EPSG:4326).

### Postup zpracování

1. V seznamu předmětů ochrany byly oba druhy vyhledány podle kódu směrnice o stanovištích (1061 – modrásek bahenní, 1059 – modrásek očkovaný) a kontrolně podle latinského jména s rodem *Phengaris* i *Maculinea*. Použity byly jen řádky s typem lokality EVL, ptačí oblasti zahrnuty nejsou. Ke všem kódům lokalit ze seznamu existuje polygon ve vrstvě EVL.
2. Geometrie EVL i modelové vrstvy byly opraveny funkcí `st_make_valid()`, modelová vrstva byla převedena z WGS 84 do S-JTSK.
3. Za preferovaný biotop jsou považovány polygony s modelovou pravděpodobností výskytu p ≥ `r p_min_lab` bez ohledu na kategorii KVES. Plocha je dále rozdělena podle kategorií KVES a tříd pravděpodobnosti `r paste(p_class_labs, collapse = "; ")`. Modelovaný biotop s nižší pravděpodobností je pro srovnání uveden v souhrnné tabulce. Ve vrstvě modráska očkovaného je pravděpodobnost uložena v poli `ver.nausithous.romp`; jde o výstup modelu modráska očkovaného, pouze název pole byl převzat z vrstvy modráska bahenního.
4. Vrstva každého druhu byla protnuta jen s lokalitami, kde je daný druh předmětem ochrany.
5. Rozloha lokality je spočtena z polygonu EVL a může se nepatrně lišit od úředně vedené rozlohy. Podíl biotopu je vztažen k této spočtené rozloze.
6. Součet ploch biotopu za lokality byl ověřen proti celkové ploše protnuté vrstvy a proti ploše jejího sjednocení, žádná plocha tedy není započtena dvakrát.
7. Pro mapu byl preferovaný biotop sloučen podle lokality, kategorie KVES a třídy pravděpodobnosti. Biotop i hranice EVL byly převedeny do WGS 84 a byly z nich odstraněny jen nadbytečné vrcholy (algoritmus Douglas–Peucker s tolerancí `r fmt_num(web_meta$simplify_tol_m, 0.1)` m, žádný polygon ani otvor nebyl vypuštěn). Souřadnice jsou uloženy na `r web_meta$coord_digits` desetinných míst, obrysy v mapě se tak od zpracovaných geometrií odchylují nejvýše o `r fmt_num(web_meta$max_offset_m, 0.1)` m. Plochy v mapě i v tabulkách pocházejí z nezjednodušených geometrií.
8. Nálezová data: NDOP obsahuje od `r fmt_date(meta$ndop$date_from)` `r ndop_n$downloaded[["nausithous"]]` záznamů modráska bahenního a `r ndop_n$downloaded[["teleius"]]` záznamů modráska očkovaného. Po vyřazení negativních záznamů (druh byl hledán, ale nenalezen) zbylo `r ndop_n$positive[["nausithous"]]` a `r ndop_n$positive[["teleius"]]` záznamů. Z nich byly ponechány věrohodné a dosud nevalidované záznamy a vyřazeny záznamy určené k opravě (zbylo `r ndop_n$not_to_correct[["nausithous"]]` a `r ndop_n$not_to_correct[["teleius"]]`), dále záznamy s přesností lokalizace horší než `r fmt_num(meta$ndop$max_accuracy_m, 1)` m (zbylo `r ndop_n$accuracy_ok[["nausithous"]]` a `r ndop_n$accuracy_ok[["teleius"]]`). Mapa ukazuje jen nálezy uvnitř EVL, v nichž je druh předmětem ochrany: `r ndop_n$inside_sites[["nausithous"]]` nálezů modráska bahenního a `r ndop_n$inside_sites[["teleius"]]` nálezů modráska očkovaného. Nález je zakreslen v souřadnicích uvedených v NDOP (S-JTSK); u nálezů zakreslených linií nebo polygonem udává NDOP centroid.

### Vymezení „uvnitř EVL“

Polygony biotopu byly oříznuty hranicí lokality (geometrický průnik, `st_intersection()`), do výsledku se tedy počítá jen ta část polygonu, která leží uvnitř EVL. Polygony, které hranici lokality přesahují, jsou v souhrnné tabulce vyčísleny spolu s plochou, která leží vně lokality a do výsledku se nezapočítává. Lokality, v nichž model nenachází žádný preferovaný biotop, jsou označeny ve sloupci „Upozornění“.

Zpracování je popsáno ve skriptech `R/01_download.R`, `R/02_process.R` a `R/03_web.R`, stránka je vytvořena ze šablony `page.qmd`.
