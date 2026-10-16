# Reading the HTML analysis report

This documents `--html`, not the independent optimization experiment report.
Its public `render_html(analysis, file_path, echarts?)` API and CLI flags remain
unchanged. Size, reachability, retained, compression and budget algorithms are
unchanged.

Read the page in this order:

1. **Header and overview:** full input path, chapter navigation and exact bytes
   for file, complete code section, whole-file gzip and unreachable local function
   encodings. Human-readable units are supplementary, not substitutes for bytes.
2. **Analysis status:** actual graph diagnostics remain visible. No detected gaps
   does not mean full Wasm verification. Candidates are not guaranteed savings.
3. **Composition:** raw/independent section gzip on one fixed byte axis; module
   ring shares of attributed function bytes, excluding code-section overhead.
4. **Functions:** Top 20 ranked by body bytes, followed by the same ordered rows
   as a native expandable table. Full names/modules wrap, remain selectable and
   have a separate full-space index; only the table needs horizontal scrolling.
5. **Module map:** module→function nesting and raw encoded areas. Colors are
   hashed from module identity and shared with the ring. Text and outlines also
   indicate model-unreachable functions.
6. **Methods:** root/edge scope, retained limits, compression ranges and resource
   mode, using native disclosure controls.

The ring tooltip computes `value / sum(all ring values)` for attributed shares
and separately `value / codeSize` for the complete section. Neither is a share
of the complete file. Independent function gzip uses encoded size, including
the body size prefix, as its raw denominator. Independent streams are not
additive and do not estimate transfer or deletion savings.

The function table and charts consume the same prepared JSON and compression
results. There is no second table analysis or recompression. All previous
embedded payload fields and schema version 1 are retained; treemap leaves add
`index` for unambiguous identity, including duplicate names. This is separate
from the call-graph JSON format. Every failure retains its actual item error;
null/failed values never become zero-byte measurements.

## Layout, keyboard and fallback

The warm light layout has a maximum outer width of 1416 px, including padding.
Cards switch from four columns to two, then one. Composition panels switch to
one column, and bar heights depend on their own row counts. Labels adapt to the
chart's available width; tooltips and function tables keep full names. The
document uses system fonts, tabular numbers, wrapping paths and visible keyboard
focus. The overview skip link, navigation, comparison button, scroll region and
native details have semantic keyboard targets.

With JavaScript and ECharts, the comparison button toggles independent gzip
alongside raw without changing the axis extent. The legend remains available.
Before printing, the report establishes the A4 content width before synchronous,
animation-free chart redraw and flush. Chart heights use denser print rows.
Disclosures open, hover tips hide, and the complete native module legend replaces
small pie percentage labels. After printing, the original widths, heights,
disclosure and pie-label states return. Print CSS repeats table headers and
starts major chapters on new pages; no screen screenshot is substituted for a
PDF. See [offline and PDF acceptance](html-delivery.md) for actual evidence.

The native CLI embeds its compiled-in ECharts 5.6.0 in every report, independent
of cwd and without downloads or asset discovery. It has no remote font,
stylesheet or script dependency. The library API is separate: omitting its
optional echarts source retains CDN mode for compatibility; offline library
callers must supply a source. That mode is visibly identified near the overview.
Missing/broken ECharts produces a chart status message;
cards, the server-rendered function table and methods remain readable. Native
details work even when JavaScript is disabled. Measurement failures are separate
from chart-loading failures.

## Reproducing this example

The input was deliberately **not** rebuilt or replaced for this display change:

```sh
sha256sum examples/fib.wasm
moon build --target native --release
_build/native/release/build/cmd/main/main.exe examples/fib.wasm --html examples/report.html
```

Input SHA-256:
`0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c`.
Its metrics remain file 10,675 B, code 5,166 B, whole-file gzip 5,207 B,
unreachable local function encodings 0 B, and 47 local functions. The previous
generated page from `c90f0d2` was compared with the regenerated page: every
existing payload field/value is unchanged, with only the additive leaf index.

`examples/report.png` is the existing user-modified image and was not overwritten.
The READMEs directly display both new real-browser screenshots. The
captures use 1440 × 1000 and 390 × 844 browser viewports. The actual JPEG
files are `examples/report-desktop.jpg` (1440 × 1000 pixels) and
`examples/report-mobile.jpg` (375 × 812 pixels); the browser scaled the mobile
capture. The extensions reflect the returned JPEG format.

## Verification and browser acceptance

Library tests exercise table ranking/identity/ranges, shared injected measurement
results, separate whole/local errors, escaping, diagnostics and empty fallback.
The compression CLI regression continues to execute the report's own formatter
functions. `scripts/test-html-report.mjs` adds real CLI fixtures for empty/single
modules, preceding imports, Top 20 truncation, Unicode/very long names, duplicate
and missing names, many small modules, graph gaps, repeated custom names, long
paths and unrelated-cwd generation. Library CDN mode remains covered by native
tests. V8 independently validates the complete fixtures.

The generated script is executed with observable chart/DOM adapters, including
four width inputs, native comparison events, resizing, print disclosure state,
missing ECharts and init failures. These verify options, state and actual
formatters; they do **not** draw a browser page or prove pixel layout. Copying
the self-contained file to another directory preserves its payload; static
resource checks and adapter execution require no network.

Visual review uses the repository development server, not a file URL:

```sh
npm run dev
# Open http://localhost:5173/ (serves examples/report.html)
```

The existing server on port 5173 was reused. Actual in-app Chromium browser
checks on 2026-10-16 produced these results, independently of the adapters:

| Item | Result |
| --- | --- |
| 1440 / 1024 / 768 / 390 px layouts | Rendered; no document-level horizontal overflow. Four/two/one card columns and two/one composition columns work. |
| Charts and comparison | Four canvases painted; independent gzip toggles and the small expanded streams remain visible. Section tooltip shows actual raw/gzip values within the panel. |
| Function table | Real 390 px viewport: 317 px scroll region contains a 900 px table. Navigation works; Enter collapses and reopens native details with visible focus. |
| Long and repeated names | A separate V8-valid module displays the complete 454-character Unicode name on multiple lines and preserves distinct indices for duplicate names. No page-level overflow at 390 px. |
| Missing library | Removing only the embedded chart-library script in a temporary test copy displays the fallback, disables comparison, and leaves cards and the full native table readable. |
| Graph gaps | A real CLI-generated indirect-call fixture displays the specific diagnostic outside disclosures. |
| Screenshots | Actual viewport captures: report-desktop.jpg and report-mobile.jpg. The original report.png is untouched. |
| Relocated report, disconnected network | Completed in fresh offline Chromium contexts with only copied HTML bytes fulfilled as the main HTTP document; no external resources, successful network control, all charts painted. See html-delivery.md. |
| Actual print/PDF output | Completed using the pinned Playwright test runner and Edge/Chromium printing. Poppler rendered every page; all 9 pages of the two local A4 PDFs were visually reviewed. Screen styles and open states restore. See html-delivery.md. |

The browser initially rejected file navigation. The user then explicitly chose
`http://localhost:5173` for the redesign screenshots. The later offline delivery
test uses distinct HTTP URLs on the same loopback development surface. No file-navigation restriction was bypassed. The server is
loopback-only and serves examples/. The later delivery regression now verifies
fresh offline rendering and real PDFs in Linux CI as well. Human visual review
is recorded separately for the local Windows PDFs; CI does not perform human
review. Neither file:// opening nor non-Chromium printing is claimed as tested.
