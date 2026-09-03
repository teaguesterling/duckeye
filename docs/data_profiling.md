# Data Exploration & Profiling

`duckeye` turns DuckDB's engine into a CLI data explorer with three dedicated modes: **Raw Tables (`-r`)**, **Native Summaries (`-z`)**, and **Smart Profiling (`-Z`)**.

---

## 1. Raw Tabular Mode (`-r`)

`-r, --raw` bypasses prose block rendering and displays data files using DuckDB's box renderer:

```console
$ duckeye -r data.parquet
$ duckeye -r customers.csv
$ duckeye -r config.yaml
$ duckeye -r pyproject.toml
$ duckeye -r accounts.xlsx
$ duckeye -r archive.zip
$ duckeye -r .git
```

### Filtering with `-w` (SQL WHERE)
`-w` applies full SQL expressions to filter rows:

```console
$ duckeye -w "score > 90.0 AND active = true" metrics.parquet
$ duckeye -w "author_name = 'Teague Sterling'" .git
$ duckeye -w "category IN ('tools', 'hardware')" catalog.csv
```

### Limiting Output (`-n`)
```console
$ duckeye -r -n 10 huge_dataset.parquet
```

---

## 2. Fast Native Summary (`-z`)

`-z, --summary` runs DuckDB's built-in `SUMMARIZE` statement to return a quick statistical breakdown:

```console
$ duckeye -z products.parquet
┌─────────────┬─────────────┬─────────┬─────────┬───────────────┬───────────┬───────────┬─────────┬───────┬─────────────────┐
│ column_name │ column_type │   min   │   max   │ approx_unique │    avg    │    std    │   q50   │ count │ null_percentage │
├─────────────┼─────────────┼─────────┼─────────┼───────────────┼───────────┼───────────┼─────────┼───────┼─────────────────┤
│ id          │ BIGINT      │ 1       │ 1000    │ 1000          │ 500.5     │ 288.8     │ 500     │ 1000  │ 0.00            │
│ category    │ VARCHAR     │ electro │ tools   │ 3             │ NULL      │ NULL      │ NULL    │ 1000  │ 0.00            │
│ price       │ DOUBLE      │ 0.99    │ 1299.99 │ 850           │ 45.20     │ 112.4     │ 24.50   │ 980   │ 2.00            │
└─────────────┴─────────────┴─────────┴─────────┴───────────────┴───────────┴───────────┴─────────┴───────┴─────────────────┘
```

---

## 3. Smart Data Profiler (`-Z`)

`-Z, --profile` provides enhanced column profiling:

* **Numeric Columns**: Computes `min`, `avg`, `max`, and a histogram sparkline via `textplot` (`tp_sparkline()`), which renders a fixed 20 columns. `textplot` is loaded for `-Z` only; `-r` and `-z` draw no sparklines and do not load it.

!!! warning "`-Z` can crash"
    Loading `textplot` destabilises the profiling query: `duckdb` segfaults on roughly one run in five, taking `-Z` with it. The profiling SQL calls no `tp_*` function, so loading the extension is enough to trigger it. Re-running usually succeeds. `-r`, `-z` and every document mode are unaffected. Tracked against `textplot` 5bf843f; a reproducer is in `scripts/textplot-repro/`.
* **Temporal Columns (`DATE`, `TIMESTAMP`, `TIMESTAMPTZ`, `TIME`)**: Computes `min`, `max`, duration span (e.g. `24 days` or `12:00:00`), and time-series distribution sparklines across epoch bins.
* **Categorical / Low-cardinality**: Computes single-pass exact category distributions and percentages using `histogram()`.
* **List & Array Columns (`LIST`, `*[]`)**: Computes length stats (`min`, `avg`, `max`), length distribution sparklines, and sample arrays.
* **Map Columns (`MAP`)**: Computes key-value entry counts (`min`, `max`), cardinality distribution sparklines, and sample maps.
* **Struct & JSON Columns (`STRUCT`, `JSON`)**: Shows schema structure and sample representations.
* **Binary Columns (`BLOB`)**: Profiles by SIZE rather than by value — `octet_length` min/avg/max and a size-distribution sparkline, plus one escaped sample. A BLOB has no useful categories: a frequency table over escaped byte strings is accurate and unreadable.
* **All Columns**: Calculates exact `non_null` and `null_pct`.

```console
$ duckeye -Z products.parquet
┌──────────────┬──────────────────────┬──────────┬──────────┬───────────────┬──────────────────────┬────────────────────────────────────────────────────────┐
│    column    │         type         │ non_null │ null_pct │ approx_unique │     distribution     │                        summary                         │
├──────────────┼──────────────────────┼──────────┼──────────┼───────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ id           │ BIGINT               │ 1000     │ 0.0%     │ 1000          │ ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ │ min: 1, avg: 500.5, max: 1000                          │
│ category     │ VARCHAR              │ 1000     │ 0.0%     │ 3             │                      │ electronics (40.0%), groceries (40.0%), tools (20.0%)  │
│ price        │ DOUBLE               │ 980      │ 2.0%     │ 850           │ ██                ▄▄ │ min: 0.99, avg: 45.20, max: 1299.99                    │
│ created_date │ DATE                 │ 1000     │ 0.0%     │ 365           │ ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ │ min: 2026-01-01, max: 2026-12-31 (364 days)            │
│ in_stock     │ BOOLEAN              │ 1000     │ 0.0%     │ 2             │                      │ true (85.0%), false (15.0%)                            │
│ tags         │ VARCHAR[]            │ 1000     │ 0.0%     │ 45            │ ██                   │ len min: 1, avg: 2.3, max: 5, e.g. ['sale', 'new']     │
│ attrs        │ MAP(VARCHAR, BIGINT) │ 1000     │ 0.0%     │ 12            │ ██                   │ entries min: 1, max: 3, e.g. {rating=5}                │
└──────────────┴──────────────────────┴──────────┴──────────┴───────────────┴──────────────────────┴────────────────────────────────────────────────────────┘
```

### Profiling Filtered Subsets
Combine `-Z` with `-w` to profile specific partitions:

```console
$ duckeye -Z -w "category = 'electronics'" products.parquet
```

---

## 4. Terminal Width Adaptation

All tabular modes (`-r`, `-z`, `-Z`) dynamically adapt to the terminal width via `$COLUMNS` or `tput cols`:

* **Raw Mode (`-r`) & Summaries (`-z`)**: When rendering to a terminal or through a pager (`-p`), DuckDB's modern `duckbox` renderer constrains table width to `$COLUMNS` (via `.maxwidth $COLUMNS`), cleanly truncating wide columns with ellipses (`…`) and showing column count summaries rather than wrapping text across rows. When piped to standard Unix tools (e.g. `duckeye -r data.parquet | grep ...`), maximum width is unconstrained (`.maxwidth 0`) to preserve full column data.
* **Smart Profiler (`-Z`)**: Dynamically allocates character space for category distributions, sparklines, and sample values:

| Terminal Width | Category Limit | Text Budget | Formatting Behavior |
|---|---|---|---|
| **$\le$ 85 cols** | 1 (dominant category) | 12 chars | Compact view fitting standard 80-column windows |
| **86–115 cols** | 2 categories | ~25–35 chars | Balanced 2-item distribution |
| **$>$ 115 cols** | 3 categories | $\ge$ 45 chars | Full 3-item frequency breakdown with descriptive labels |

You can explicitly test or constrain rendering width by setting the `COLUMNS` environment variable:

```console
$ COLUMNS=80 duckeye -r data.parquet
$ COLUMNS=80 duckeye -Z data.parquet
$ COLUMNS=140 duckeye -Z data.parquet
```

