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

* **Numeric Columns**: Computes `min`, `avg`, `max`, and a 10-bin histogram sparkline via `textplot` (`tp_sparkline()`).
* **Categorical / Low-cardinality**: Computes single-pass exact category distributions and percentages using `histogram()`.
* **Nested / Arrays**: Extracts array length distributions and sample elements.
* **All Columns**: Calculates exact `non_null` and `null_pct`.

```console
$ duckeye -Z products.parquet
┌──────────┬─────────┬──────────┬──────────┬───────────────┬──────────────────────┬────────────────────────────────────────────────────────┐
│  column  │  type   │ non_null │ null_pct │ approx_unique │     distribution     │                        summary                         │
├──────────┼─────────┼──────────┼──────────┼───────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ id       │ BIGINT  │ 1000     │ 0.0%     │ 1000          │ ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ │ min: 1, avg: 500.5, max: 1000                          │
│ category │ VARCHAR │ 1000     │ 0.0%     │ 3             │                      │ electronics (40.0%), groceries (40.0%), tools (20.0%)  │
│ price    │ DOUBLE  │ 980      │ 2.0%     │ 850           │ ██                ▄▄ │ min: 0.99, avg: 45.20, max: 1299.99                    │
│ in_stock │ BOOLEAN │ 1000     │ 0.0%     │ 2             │                      │ true (85.0%), false (15.0%)                            │
│ tags     │ VARCHAR │ 1000     │ 0.0%     │ 45            │                      │ [sale] (25.0%), [new] (20.0%), [clearance] (10.0%)     │
└──────────┴─────────┴──────────┴──────────┴───────────────┴──────────────────────┴────────────────────────────────────────────────────────┘
```

### Profiling Filtered Subsets
Combine `-Z` with `-w` to profile specific partitions:

```console
$ duckeye -Z -w "category = 'electronics'" products.parquet
```

---

## 4. Terminal Width Adaptation

The smart profiler dynamically inspects the terminal width via `$COLUMNS` or `tput cols` and budget-allocates character space for the `summary` column so that output never runs off screen or breaks into fragmented wrapped lines:

| Terminal Width | Category Limit | Text Budget | Formatting Behavior |
|---|---|---|---|
| **$\le$ 85 cols** | 1 (dominant category) | 12 chars | Compact view fitting standard 80-column windows |
| **86–115 cols** | 2 categories | ~25–35 chars | Balanced 2-item distribution |
| **$>$ 115 cols** | 3 categories | $\ge$ 45 chars | Full 3-item frequency breakdown with descriptive labels |

You can explicitly test or constrain rendering width by setting the `COLUMNS` environment variable:

```console
$ COLUMNS=80 duckeye -Z data.parquet
$ COLUMNS=140 duckeye -Z data.parquet
```

