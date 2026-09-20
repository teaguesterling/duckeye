# AI Agent Guide: Code & Document Intelligence in `duckeye`

This guide teaches AI coding agents (Antigravity, Claude Code, OpenCode, Codex, etc.) how to use `duckeye` to navigate, discover, prune, and extract context from codebases and documents with precision, minimal context token overhead, and sub-second latency.

---

## 1. Why Agents Should Use `duckeye`

| Conventional Approach | Limitations for AI Agents | `duckeye` Approach |
|---|---|---|
| `cat large_file.py` | Dumps 2,000 lines into context; wastes tokens; dilutes attention | `duckeye -Q '.func#execute' file.py` extracts only the relevant function definition & body |
| `grep -rn "pattern" .` | No syntax awareness; catches comments and strings; misses multi-line blocks | `duckeye -F "websocket handlers" src/` extracts full syntactically bounded AST nodes |
| `grep` on `.docx`/`.pdf`/`.ipynb` | Binary/compressed formats fail or leak raw JSON / XML markup | Native DuckDB readers extract clean markdown/text blocks directly |
| LLM search across whole repo | High token cost, slow prompt roundtrips | Local 2-stage coarse-to-fine filtering (`-F` + `-R`) executes locally in milliseconds |

---

## 2. The 3-Step Progressive Extraction Pattern

When inspecting unfamiliar codebases or large documentation repositories, agents should follow the **Progressive Extraction Pattern**:

```
 ┌─────────────────────────────────────────────────────────────┐
 │ 1. Survey Structure                                         │
 │    duckeye -T <file>                                        │
 │    duckeye -T --json <file>                                 │
 └──────────────────────────────┬──────────────────────────────┘
                                │
                                ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 2. Coarse Structural Slicing                                │
 │    duckeye -F "<natural language concept>" <file>           │
 │    duckeye -Q '<css_selector>' <file>                       │
 └──────────────────────────────┬──────────────────────────────┘
                                │
                                ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 3. Fine Semantic Discrimination & Re-ranking                │
 │    duckeye -F "<concept>" -R "<exact intent>" <file>        │
 │    duckeye -Q '<selector>' -R "<intent>" --top-k 1 --json   │
 └─────────────────────────────────────────────────────────────┘
```

---

## 3. Natural Language Code & Document Discovery (`-F, --find`)

`-F, --find` translates natural language prompts into structural ASTCSS or document CSS selectors using a decoupled local model (`qwen3.5-0.8b-astcss` or local daemon).

### No Magic Prefixes Needed
You do **not** need to prepend `"find"`, `"find all"`, or `"search for"`. Pass bare noun phrases, method names, structural targets, or concepts:

#### Code Queries (27 languages: Python, Rust, Go, C/C++, JS/TS, Java, Bash, etc.):
```sh
# Query by functionality
duckeye -F "async websocket handlers" src/server.rs

# Query by method or class name
duckeye -F "execute method" src/worker.py
duckeye -F "WorkerService class" src/service.py

# Query by structural pattern
duckeye -F "error handling blocks" api/client.go
duckeye -F "unit test functions" tests/test_auth.py

# Pass explicit dialect hint when filename extension is ambiguous
duckeye -F "request dispatching" --dialect python script.bin
```

#### Document Queries (Markdown, DOCX, HTML, PDF, EPUB, LaTeX, etc.):
```sh
# Query top-level structure
duckeye -F "major section headings" docs/architecture.md

# Query code snippets inside prose
duckeye -F "bash command snippets" README.md

# Query callouts and warnings
duckeye -F "blockquotes and warning callouts" guide.docx
```

---

## 4. Semantic Re-ranking (`-R, --rank`)

When structural selectors (`-Q`) or natural language discovery (`-F`) produce multiple candidate nodes, `-R, --rank` evaluates each candidate with a cross-encoder (`Qwen3-Reranker-0.6B`), scoring relevance and filtering noise.

### Combining `-F` and `-R` (Coarse Slicing + Fine Ranking)
```sh
# Slices all handler functions, then re-ranks by authentication logic
duckeye -F "request handlers" -R "handles token validation and auth headers" src/auth.py

# Slices all database operations, re-ranks for memory optimization
duckeye -F "allocator functions" -R "optimizes memory usage" src/alloc.c
```

### Thresholds & Top-K Cutoffs
- `--threshold <score>`: Sets minimum relevance score (default: `0.70`, or `0.0` when `--top-k` is set). Candidates below the threshold are pruned.
- `--top-k <N>`: Limits output to the top $N$ highest-scoring results.

```sh
# Return only the single most relevant function
duckeye -Q '.func' -R "encodes payload to protobuf" --top-k 1 src/proto.rs

# Low threshold for broader recall
duckeye -R "security requirements" docs/spec.md --threshold 0.40
```

---

## 5. Machine-Readable JSON Output (`--json`)

Agents should use `--json` when parsing results programmatically or feeding candidate blocks into downstream tool pipelines.

### Outline JSON (`-T --json`)
```sh
duckeye -T --json docs/architecture.md
```
```json
[
  {"title": "System Architecture", "level": 1, "indent": 0, "element_order": 0},
  {"title": "Ingestion Pipeline", "level": 2, "indent": 1, "element_order": 1},
  {"title": "AST Engine", "level": 2, "indent": 1, "element_order": 3}
]
```

### Re-ranked Candidate JSON (`-F` / `-Q` with `-R --json`)
```sh
duckeye -Q '.func' -R "handles background execution" --top-k 1 --json src/worker.py
```
```json
[
  {
    "file_path": "src/worker.py",
    "type": "function_definition",
    "name": "execute",
    "start_line": 4,
    "end_line": 8,
    "score": 0.94,
    "content": "def execute(self, task_name: str, payload: dict) -> bool:\n    \"\"\"Run the given background task.\"\"\"\n    return True"
  }
]
```

### Document Section JSON (`-S` / `-s` `--json`)
```sh
duckeye -S "Security" --json spec.md
```
```json
[
  {
    "kind": "block",
    "element_type": "heading",
    "content": "Security",
    "level": 1,
    "encoding": "text",
    "attributes": {"heading_level": "2", "id": "security"},
    "element_order": 0
  },
  {
    "kind": "block",
    "element_type": "paragraph",
    "content": "All requests must include a Bearer token.",
    "level": 1,
    "encoding": "text",
    "attributes": {},
    "element_order": 1
  }
]
```

---

## 6. CSS Selector Reference for Code (`-Q`)

`duckeye` leverages [`sitting_duck`](https://github.com/teaguesterling/duckdb_sitting_duck) to query syntax trees across 27 programming languages:

| Selector | Matches | Example |
|---|---|---|
| `.func` | Any function or method | `duckeye -Q '.func' src/api.rs` |
| `.func#name` | Exact function name | `duckeye -Q '.func#validate_token' src/auth.py` |
| `.class` | Any class, struct, or interface | `duckeye -Q '.class' models/user.go` |
| `.class#Name` | Exact class name | `duckeye -Q '.class#SessionManager' src/session.ts` |
| `.func:async` | Async functions | `duckeye -Q '.func:async' routes/index.js` |
| `.func[name^=test_]` | Prefix matching | `duckeye -Q '.func[name^=test_]' tests/test_worker.py` |
| `class > func` | Direct child methods | `duckeye -Q 'class > func' src/service.py` |

---

## 7. Multi-Format Cheatsheet for Agents

```sh
# 1. Inspect data tables with smart profiling
duckeye -Z dataset.parquet
duckeye -Z -w "status = 500" logs.jsonl

# 2. PDF page extraction
duckeye -P 1-5 manual.pdf
duckeye -P 10- -S "Troubleshooting" manual.pdf

# 3. Read documents across git history without checking out branches
duckeye -S "Installation" 'git://README.md@v1.0.0'
duckeye -Q '.func#process' 'git://src/worker.rs@main~3'

# 4. Search 19M offline Wikipedia articles
duckeye -s "photosynthesis" wikipedia.zim
duckeye -S "Chlorophyll" wikipedia.zim
```

---

## 8. Environment Configuration for Local Daemon Inference

Agents running in autonomous workflows can configure local daemon transport via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `DUCKEYE_LLM_SOCKET` | `/tmp/woollama.sock` | Unix domain socket for ASTCSS compiler daemon |
| `DUCKEYE_LLM_ENDPOINT` | `http://localhost:11434` | HTTP endpoint URL for Ollama / LLM server |
| `DUCKEYE_RERANK_SOCKET` | `/tmp/reranker.sock` | Unix domain socket for cross-encoder reranker daemon |
| `DUCKEYE_RERANK_ENDPOINT` | `http://localhost:8001` | HTTP endpoint URL for Text Embeddings Inference / Reranker server |
