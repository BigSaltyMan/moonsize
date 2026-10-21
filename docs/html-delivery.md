# Offline HTML delivery and A4 printing

Current review entry: [evidence index](review-evidence.md). The two historical,
human-reviewed PDFs and their page-by-page record are now directly readable in
[review-artifacts](review-artifacts/); their unchanged hashes match the local
snapshot below. Release-specific clean CI and registry consumer verification are
recorded after committing in the [0.4.0 release](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.4.0).

The native CLI compiles in the pinned ECharts 5.6.0 resource. It no longer reads
`assets/echarts.min.js` from cwd, parents or another runtime location, and cannot
silently turn its default report into a CDN page. An independent directory
containing a malicious same-name resource produces identical HTML. There is no
runtime download or Node/browser requirement for the production CLI.

The library API is separate: `render_html(analysis, file_path, echarts?)` retains
its signature and empty/default-source CDN behavior for compatibility. Library
callers who require an offline file must pass the chart source. Missing-chart
fallback remains covered; it is not used as evidence of working offline charts.
See [vendored source, licenses and deterministic regeneration](../assets/README.md).

## Three delivery claims and their evidence

| Claim | Actual verification |
| --- | --- |
| Arbitrary cwd generates a self-contained page | Three real CLI runs: empty independent cwd, local/parent poisoned assets, and a complete V8-valid long-name/diagnostic module. Reconstructed chart source hash equals the vendored pin. |
| A moved report renders with no network | Original context closed. Copy is byte-identical in a new directory containing only report.html, with spaces and Chinese in its path. New context is offline before navigation, service workers blocked. All four charts paint, tooltip/table/metrics work; there are no external requests or rendering errors. A separate fetch control fails as expected. |
| Printed PDF is readable | Actual browser A4 PDFs, independently rendered with Poppler. PDF.js checks exact measurements, complete function/module identities, text bounds and retained graphics. Extracted text comparisons ignore whitespace introduced by font/ligature item splitting; spelling, punctuation, numbers and units remain checked. Every local page is also visually reviewed. Printing restores original chart widths, pie labels and disclosures. |

The HTTP development surface is intentional. AGENTS.md prohibits `file://`:
the offline test fulfills **only the main document** at a distinct loopback HTTP
URL, reading bytes from the copied file. It does not fulfill any JS, CSS, font,
image or control-probe request. The rest of the browser context remains offline.
The original context and its cache are not reused. This validates the copied
HTML's actual browser rendering with network disabled; OS double-click/file-URL
opening is not claimed as separately tested. No system network/security setting
is changed.

## Reproduce

Normal CLI generation needs only the built executable and input:

```sh
moon build --target native --release
# Use absolute CLI/input paths from an unrelated working directory:
/absolute/path/main.exe /absolute/path/fib.wasm --html report.html
```

The delivery test dependencies are development-only and lockfile-pinned:
Playwright 1.58.2 and PDF.js 5.4.624. Use Node 24 as in CI.

```sh
npm ci
npx playwright install --with-deps chromium
# Ubuntu test renderer and CJK fonts:
sudo apt-get install -y --no-install-recommends poppler-utils fonts-noto-cjk
npm run dev                       # separate terminal, http://127.0.0.1:5173/
npm run test:delivery
```

`node scripts/test-html-portability.mjs /absolute/path/main.exe` runs just the
three CLI/byte-level cases without a browser. Add `--browser` to require the
fresh offline contexts and real PDFs. Browser/PDF capability failure is a test
failure, not a silent skip. On Windows, the test can use an installed Chromium
browser and Poppler through these test-only environment variables:

```powershell
$env:MOONSIZE_BROWSER_EXECUTABLE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
$env:MOONSIZE_PDFTOPPM = '/absolute/path/to/pdftoppm.exe'
npm run test:delivery
```

Each run creates an independent `_build/html-delivery-verification/run-*/` folder
and writes `latest.json` at its parent. Evidence includes platform/browser and
runner versions, input/CLI/report/PDF hashes, cwd, exact command, original and
copy paths, request/error records, chart/print states, PDF text and every page
PNG. CI uploads `html-delivery-evidence` from its exact clean checkout SHA.

## Printing contract

The tested layout is A4 portrait with 12 mm margins and backgrounds enabled.
Before the browser's paper snapshot, the handler establishes a 186 mm content
width and one-column chart layout, resizes with animation disabled and flushes
ZRender synchronously. This addresses the observed old failure where screen
canvas widths clipped the first function bar and the right side of the tree.

The overview is a separate first page. Composition, functions and the module
map begin new pages; function rows can continue with repeated headers. Charts
use denser print rows, hover tips are hidden, and all required methods expand.
Tiny pie percentage labels hide in print to avoid clipped text; the full native
legend lists every displayed slice with its exact attributed bytes. Screen pie
labels and original inline styles/open states restore afterwards. No animation,
asynchronous redraw assumption or PDF generation feature is added to the CLI.

## Local acceptance, 2026-10-16

The unchanged input is `examples/fib.wasm`, SHA-256
`0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c`.
File/code/whole-file gzip/model-unreachable bytes remain 10675/5166/5207/0.
The entire previous embedded analysis JSON compares equal after regenerating
`examples/report.html` with the real CLI. Existing desktop/mobile captures still
represent the unchanged screen layout and were not regenerated; user report.png
and planning documents remain outside this commit.

Local browser: Microsoft Edge 156.0.4314.23 on Windows 10.0.26300, x64;
Playwright 1.58.2; Poppler 26.07.0. Actual PDFs are `example.pdf` (5 pages) and
`long-name-warning.pdf` (4 pages) under the run recorded in
[the checked-in results](html-delivery-results.json). All nine corresponding
Poppler PNGs were visually inspected. `manual-review.md` beside the PDFs records
each page. Metrics, full names/indices, table columns, graph warnings and model/
compression limits remain readable; no clipped page edge, black/empty chart,
hover overlay or unintended empty page was found. The overview's unused lower
space is intentional chapter pagination. Four widths (1440/1024/768/390) and
screen state after printing pass the actual browser regression.

Windows native release CLI grows from 804,864 to 2,893,824 bytes (+2,088,960).
This is the cost of shipping the fixed chart source in the executable, not a
change to Wasm example budgets. CLI source reconstruction is lazy, only on HTML
generation. The `.mbti` public signatures are unchanged. Local validation passes
336 native tests, 730 CLI cases (727 prior + 3 portability), four source demos
and budget exits 0/3. Linux CI reruns the full checks and real browser/PDF tests;
its PDFs may paginate differently with platform fonts and are automatically
checked rather than labeled human-reviewed.

Scope limits: this verifies the Chromium-family A4 settings above. Other browser
engines, physical printers and OS file associations have not been tested. The
local record contains source-parent SHA plus dirty-state/source-resource hashes;
the final push's CI artifact supplies clean exact-commit evidence.

## Opt-in current data entries, 2026-10-21

`--html new-report.html --data-segments` adds the existing current-input ledger;
`--data-json new-data.json` also enables it and shares one parsed report with the
HTML. Old `render_html` stays compatible; the new library entry point is
`render_html_with_data_segments(analysis, file_path, report, echarts?)`. It shares
the template and compression measurements, without reparsing the data section.
No data comparison, raw payload, expression evaluation or new chart is added.

The HTML includes a static summary and first20 rows. A native button adds20 at a
time using textContent; no-JavaScript readers keep the initial rows, and chart
failure does not prevent pagination. The table scrolls within its panel on narrow
screens. Printing keeps the displayed subset and its count, opens only those row
details, then restores their previous states. It does not create the hidden rows.

The existing delivery script now includes one shared45-entry fixture. For a local
targeted run, after starting `npm run dev`, use:

```sh
node scripts/test-html-portability.mjs _build/native/release/build/cmd/main/main.exe --browser --data-only
```

Use the Windows browser override shown above where needed. CI keeps its existing
full delivery step, including the data fixture, without a second job or new
browser dependency. The targeted local run generates one report and one actual
A4 PDF; it does not regenerate the two historical PDF acceptance cases.

Local evidence: `_build/html-delivery-verification/run-d7HW85/`, Microsoft Edge
156.0.4314.36 on Windows10.0.26300 x64, Playwright1.58.2 and Poppler26.07.0.
The server was started with `npm run dev`; the live root was opened before a
fresh offline context loaded the copied HTML via the main-document-only route
at `http://127.0.0.1:5173/`. No file URL, warmed original context or subresource
fulfilment was used. Actual requests and the failing offline control probe,
console errors (none), layout and print events are in evidence.json.

Fixture SHA-256: `ec51e960d520337777d0265895da284b5b0ab99e3c8f4370accd98c60414bc55`.
The ledger is328 B =129 B payload +195 B entry metadata +4 B section overhead,
with45 entries. Static20, keyboard-driven40, final45 and hidden-button states,
no-script initial20, ECharts-failure pagination and390px internal scrolling pass.
The PDF prints40/45 rows, not all45, with details expanded only during printing.
`data-entries.pdf` SHA-256:
`f7985acc0b1b0bcc55a1c1c8cd3657bf72e6f0f063ac4c4facc05c61845f95fb`.
All10 pages were rendered and automatically checked for text and horizontal
bounds. New-module pages5–9 and methods continuation10 were visually inspected,
along with data-desktop.png and data-mobile.png; the ledger, ranges, zero payload
and limits remain readable. Other pages use the existing automatic checks and
are not labeled a new manual review. State restored after actual printing:
40 rows, first detail open, remaining details closed, normal chart widths.

The formal example still analyzes `examples/fib.wasm` with the original
`0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c` hash.
It was regenerated with `examples/fib.wasm --html <new-staging-path> --data-segments`,
then explicitly copied after checking every old embedded analysis field equal.
The new optional data field describes one entry:252 B =240 B payload +8 B
metadata +4 B overhead. Generation record: `_build/html-data-example-eAD7qG/`;
formal HTML SHA-256 `9b4208c24d6bfc2397acef6d784896a79968053c05896bac05038501651c091c`.
No README screenshot or user report.png was replaced. This is Chromium-family
A4 evidence; other engines and physical printers remain untested. Final clean
commit evidence comes from the target Linux CI, not this pre-commit Windows run.

## 0.5.0 release evidence reuse

The data-entry PDF and original targeted review above are copied byte-for-byte
into [public review artifacts](review-artifacts/manifest.json). This is reuse of
the recorded acceptance, not a new browser/print run. The native embedded-resource
contract and library optional-resource behavior remain unchanged. Exact release
SHA, target Linux CI, public package hashes and consumer verification belong in
the [0.5.0 release record](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.0)
when those steps complete.
