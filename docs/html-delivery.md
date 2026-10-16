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
