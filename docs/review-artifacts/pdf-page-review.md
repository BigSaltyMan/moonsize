# Local PDF page review (2026-10-16)

Browser: Edge 156.0.4314.23; Playwright 1.58.2; Windows 10.0.26300.
PDF renderer: Poppler 26.07.0, 110 dpi. Copied from the recorded run-JM2Zrx without changing the PDFs. Hashes are in [the original results](../html-delivery-results.json) and [the public manifest](manifest.json).

| PDF | Pages checked | Result |
| --- | --- | --- |
| example.pdf | 1 | File identity and 10675/5166/5207/0 B cards match HTML; visible model limit. Overview is an intentional separate page. |
| example.pdf | 2 | All section bars and units fit; ring complete; complete module legend with exact bytes. No tooltip overlay. |
| example.pdf | 3 | Function chart is no longer clipped; table header and rows 1-4 readable. |
| example.pdf | 4 | Repeated header; rows 5-20 include all columns and full names. |
| example.pdf | 5 | Raw tree complete; model/compression/resource limitations and footer retained. |
| long-name-warning.pdf | 1 | Long input path including Chinese/space/& wraps; real indirect-call diagnostic remains visible. |
| long-name-warning.pdf | 2 | Small raw sections, ring and complete wrapped module legend fit. |
| long-name-warning.pdf | 3 | Distinct same-name indices; full long name and literal script-end characters wrap safely; all numeric/state columns readable. |
| long-name-warning.pdf | 4 | Model-unreachable text/outline in tree; complete methods and footer. |

All 9 pages inspected as actual rendered PDF pages. No blank-only page, clipping, black/empty charts or overlapping controls observed. Screen widths, labels and native disclosures restore automatically after printing.

This is human review of local Windows PDFs. CI's clean-HEAD PDFs are independently generated and automatically checked, not labeled human-reviewed.
