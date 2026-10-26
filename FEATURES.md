# Feature parity with AozoraEpub3

Every feature of the Java app (hmdev/AozoraEpub3 1.1.0b46), where it lives in the Swift port,
and how it was checked.

**Golden** = converted with the Java build and the Swift engine, with every text file in the
EPUB (XHTML, OPF, NCX, CSS) byte-identical and every image the same name and pixel size:
22 inputs × 8 setting variants = 176 conversions, 0 differences. That output is recorded in
`Tests/Fixtures/golden/expected.json`, and `GoldenTests` checks it on every `swift test`.

| Feature | Java | Swift | Checked |
|---|---|---|---|
| **Input** | | | |
| .txt in Shift_JIS (MS932) or UTF-8, BOM handling | `AozoraEpub3`, `InputStreamReader` | `TextIO`, `MS932Decoder` (Java's exact table, dumped from the JDK) | Golden |
| .zip / .txtz with text and images (CP932 entry names) | commons-compress | `ArchiveReader` (system libarchive) | Golden, unit test |
| Archives with several texts (one book each) | `countZipText` | `AozoraEpub.prepare` | Golden, unit test |
| Image-only .zip / .cbz / .rar (comics) | `Epub3ImageWriter` | `EpubImageWriter` | Golden (.cbz) |
| .rar (text or images) | junrar | libarchive (RAR4 + RAR5) | Unit test (reader) |
| Folders (recursive), multiple files | GUI | `AppModel.add(urls:)` | Manual |
| Windows .url shortcuts | `readInternetShortCut` | `AppModel.readInternetShortcut` | Not yet tested |
| Links to Aozora .zip/.txtz/.rar files | `convertWeb` | `AozoraEpub.fetch` | Not yet tested |
| **Aozora annotations** | | | |
| Ruby (｜《》), auto ruby base detection, per-character ruby | `convertRubyText` | `AozoraConverter+Line` | Golden |
| Gaiji: ※［＃…］ by name, U+, JIS men-ku-ten, substitute table, image gaiji | `convertGaijiChuki`, `JisConverter` | `GaijiConverter` (+ JIS table dumped from Java) | Golden |
| Latin decomposition 〔e'tiquette〕, くの字点 ／＼ | `LatinConverter` | `LatinConverter` | Golden |
| Forward-reference chuki ［＃「…」に傍点］ etc. | `replaceChukiSufTag` | `replaceChukiSufTag` | Golden |
| Indents, wrap-indent, 字詰め, boxes (罫囲み/枠囲み), 地付き, 地寄せ | chuki_tag.txt | same tables | Golden |
| Page breaks, 左右中央 / ページの左, colophon split (底本：) | `PageBreakType` | `PageBreakType` | Golden |
| Warichu (割り注) with automatic line break | `convertTextLineToEpub3` | same | Golden |
| Window headings (窓見出し), captions, kunten/kaeriten | same | same | Golden |
| Auto tate-chu-yoko (2/3-digit, 1 digit, !?, dates) | `convertTcyText` | `tcy()` | Golden |
| Upright symbols in vertical text, ≪≫/“”/― substitutions | `convertReplacedChar` | same | Golden |
| Dakuten combining marks: as is / overlay / glyph fonts | same | same (fonts bundled) | Golden |
| IVS output (BMP / SSP), 4-byte kanji | same | same | Golden |
| Full-width space hyphenation (Kobo/Kindle, Reader) | same | same | Golden |
| Comment blocks: hide / print / convert | same | same | Golden |
| replace.txt character substitutions | `replaceMap` | `AozoraConverter(replaceFile:)` (app: support folder) | Code review |
| User glyph fonts in gaiji/ | `utf16FontMap` … | `loadGaijiFonts` | Code review (app uses the bundled folder) |
| **Title & metadata** | | | |
| Title/author detection, 6 layouts, publisher-first | `BookInfo.setMetaInfo` | `BookInfo` | Golden |
| Title from "[作者] 題名" file names | `getFileTitleCreator` | `BookInfo.fileTitleCreator` | Golden (`UseFileName`) |
| Title page: in text / centered / horizontal / none | `title_middle.vm` … | same templates | Golden |
| Furigana (file-as) for title and author, publisher | confirm dialog | review sheet | Manual |
| **Table of contents** | | | |
| Headings from 見出し/大/中/小, same-line, page breaks | `getBookInfo` | same | Golden |
| Chapter names, numbers, bracketed numbers, custom regex | same | same | Golden |
| Join next line, exclude runs, max length | same | same | Golden |
| Nested nav.xhtml / toc.ncx, TOC page (vertical/horizontal), cover in TOC | `Epub3Writer` | `EpubWriter.buildTocLevels` | Golden |
| Select / rename TOC entries before converting | `JConfirmDialog` | `TocEditor` | Manual |
| **Cover** | | | |
| First illustration within N lines, same-name image, file/URL, none | GUI/CLI | `ConversionSettings.cover` | Golden (first illustration) |
| cover.png/jpg next to the text | `JConfirmDialog` | `AozoraEpub.prepare` | Code review |
| Pick another illustration, crop and zoom, keep original | `JCoverImagePanel` | `CoverEditor` | Manual |
| Cover history per file (session) | `BookInfoHistory` | `AppModel.history` | Manual |
| Generated cover from title/author | (new) | `GeneratedCover` | Manual |
| **Images** | | | |
| Single-page images, fit/no-fit, aspect sizing | `getImagePageType` | `EpubWriter.getImagePageType` | Golden |
| Wrap (float) small images, scale relative to screen | same | same | Golden |
| Reader float display (page / block) | same | same | Golden |
| Resize to max W/H, JPEG quality, gamma | `ImageUtils` | `ImageUtils` (Core Graphics) | Golden (sizes) |
| Auto margin trimming with page-number removal | `getPlainMargin` | same (incl. Java's gray→sRGB mapping) | Golden (sizes), unit test |
| Auto-rotate wide images | same | same | Golden (sizes) |
| SVG fixed layout for image-only books | `svg_image.vm` | same | Golden |
| Leave out illustrations | `noIllust` | same | Golden |
| **Output** | | | |
| EPUB 3 zip (mimetype first, stored) | commons-compress | ZIPFoundation | Golden |
| File naming "[作者] 題名.epub" or input name, overwrite guard | `getOutFile` | `AozoraEpub.outputPath` | Golden |
| .epub / .kepub.epub / .fxl.kepub.epub | ext option | same | Golden (`kobo`) |
| .mobi via kindlegen (Kindle quirks in templates) | `ProcessBuilder` | `KindleGen` (finds Kindle Previewer's copy) | Not tested (kindlegen not installed) |
| Customizable templates and CSS (`*_custom` overrides) | Velocity | `Velocity.swift` (subset interpreter, same .vm files) | Golden, unit tests |
| **Settings** | | | |
| Every GUI option (≈130 keys) | `AozoraEpub3Applet` | `ConversionSettings` | Golden configs |
| Device presets | presets/*.ini | same files + Apple Books, Send to Kindle, Kobo Clara, Kobo Libra | Manual |
| Profiles | profiles/*.ini | Application Support/Profiles/*.ini (same format) | Manual |
| Import/export AozoraEpub3.ini | — | Settings ▸ Profiles | Manual |
| **Web novels** | | | |
| Site definitions web/<host>/extract.txt | `WebAozoraConverter` | `WebNovelDownloader` (from the maintained kyukyunyorituryo fork) | Syosetu: live test |
| TOC pagination (Syosetu ?p=), Kakuyomu JSON TOC, User-Agent | fork | same | Syosetu: live test; Kakuyomu: not yet tested |
| Cache, update detection, only-updated / latest-N chapters | same | same | Not yet tested beyond a fresh download |
| Large mitemin images | fork | `WebOptions.largeImages` | Not tested |

## Intentional differences

- `dcterms:modified` is real UTC. Java formatted local time with a `Z` suffix.
- A text whose first line is empty converts; Java threw a NullPointerException.
- Index errors on malformed input are clamped instead of aborting the book.
- A cropped external cover image is used; Java silently fell back to the uncropped file.
- Web downloads resolve chapter images against their own chapter page (Java used the last chapter's).
- Image bytes differ (Core Graphics vs Java ImageIO encoders); sizes match.

## Java behavior kept on purpose (so output matches)

- Velocity 1.7 semantics: empty strings are truthy, undefined references print literally.
- The image-only writer ignores style settings (line height 0.0 in its unused CSS).
- `［＃改ページ］`-style quirks such as the `wrcBrPos` operator-precedence bug in warichu.
- Presets reset "scale images" and Reader float options when the key is absent.
