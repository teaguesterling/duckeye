-- leveled_ast — project ANY depth-first, level-numbered SQL table into the node
-- schema sitting_duck's CSS selector engine already accepts.
--
-- The insight this rests on: a depth-first ordering plus a level column fully
-- determines a tree. No stored node_id or parent_id is needed, because both are
-- computable -- node_id is the row's position in the ordering, and a node's parent
-- is the nearest preceding row with a smaller level. duck_blocks are shaped this
-- way; so is any indentation-derived outline, any recursive listing, and
-- sitting_duck's own AST.
--
-- Given that projection, `ast_select_from(table, selector)` works unchanged, so a
-- CSS selector language over documents needs no new grammar, no second parser and
-- no translator to keep in sync with sitting_duck's.
--
-- PARAMETERS
--   src           name of the source table (anything query_table() accepts)
--   order_col     REQUIRED. The depth-first ordering, monotonic in document order.
--                 Explicit by choice: DuckDB does preserve insertion order by
--                 default, but `rowid` cannot be passed here (it is a pseudo-column
--                 and `columns()` sees only declared ones), it does not exist on a
--                 view at all, and preserve_insertion_order is a setting that can be
--                 turned off. A caller without an ordering column adds one when
--                 building the table -- `row_number() OVER () AS ord` -- which is
--                 one line and removes every one of those caveats.
--   level_col     depth. Any monotonic integer scale; 0- or 1-based both work.
--   type_col      node type, matched by a bare `tag` selector.
--   name_col      matched by `#name`.
--   partition_col groups independent trees in one table (a file path, a doc id).
--                 Pass a literal column of constants for a single tree.
--   attrs_col     a MAP(VARCHAR,VARCHAR) whose entries back `[attr=value]`, or the
--                 name of any VARCHAR column to ignore attributes.
--
-- PRECONDITION, and the one a design doc would miss: THE ORDERING MUST BE COMPLETE.
-- Every node's ancestors must be present as rows. "Parent = nearest preceding row
-- with a smaller level" is only correct when no ancestor is missing; where one is,
-- it silently attaches the node to whatever happened to come before it at a lower
-- level, which may be a peer rather than an ancestor.
--
-- Measured on `glob('docs/**')`, which returns FILES only, no directories:
--
--   9  d=1  parent=1  docs/skill.md
--   10 d=3  parent=9  docs/superpowers/specs/2026-09-08-....md    <- a FILE parents a FILE
--
-- depths ran 0,1,3 with nothing at 2, and the depth-3 node adopted the depth-1 file
-- above it. duck_blocks satisfy the precondition (every block is a row, levels are
-- contiguous by construction); a file listing does not, and must synthesise its
-- directory rows first. There is no way to detect this from inside the projector --
-- a level gap is indistinguishable from a legitimately deep child -- so it belongs
-- in the contract, not in a runtime check.
--
-- KNOWN COST: parent/descendant/children are correlated subqueries here -- O(n^2),
-- measured at 258ms for 696 rows. Correct, and deliberately the naive form so the
-- semantics are readable. The window/lag-stack rewrite is the optimisation, not the
-- specification.
--
-- KNOWN BLOCKER: ast_select_from requires all 21 read_ast columns, including
-- SEMANTIC_TYPE -- which is not in duckdb_types(), so no outside caller can write
-- NULL::SEMANTIC_TYPE. The typed NULLs below are borrowed from a zero-row read_ast
-- as a workaround. The real fix is for sitting_duck to accept a minimal source
-- schema; see the note at the bottom.

-- USAGE. `.read` must be the only thing in its own -c, but a session may take
-- several -c flags and state persists across them:
--
--   duckdb -unsigned \
--     -c "LOAD sitting_duck; LOAD duck_block_utils; LOAD markdown;" \
--     -c ".read prototypes/leveled_ast.sql" \
--     -c "CREATE TEMP TABLE t AS SELECT ...;
--         CREATE TEMP TABLE p AS SELECT * FROM leveled_ast('t','ord','lvl','ty','nm','part','tiny.sh');" \
--     -c "SELECT * FROM ast_select_from('p', 'list > list_item');"

CREATE OR REPLACE MACRO leveled_nodes(src, order_col, level_col, type_col, name_col, partition_col) AS TABLE
  SELECT
    list_value(columns(lambda c: c = order_col))[1]     AS ord,
    list_value(columns(lambda c: c = level_col))[1]     AS lvl,
    list_value(columns(lambda c: c = type_col))[1]      AS ty,
    list_value(columns(lambda c: c = name_col))[1]      AS nm,
    list_value(columns(lambda c: c = partition_col))[1] AS part
  FROM query_table(src);

-- The structural half: everything CSS combinators need, derived from (ord, lvl).
--   parent        nearest preceding row, same partition, with a smaller level
--   subtree_end   the row before the next row at or above my level -- my span
--   descendants   rows strictly inside that span
--   children      rows inside the span exactly one level deeper
--   sibling_index position among rows sharing my parent
-- A SYNTHETIC ROOT is required, not cosmetic. A depth-first leveled table is a
-- FOREST -- every top-level row has no parent -- whereas a tree-sitter AST always
-- has exactly one root (program/module/stylesheet). Sibling combinators resolve
-- against a shared parent, so without a root `A + B` and `A ~ B` match nothing at
-- the top level, which is where most document siblings live. Measured: the first
-- version of this projector produced 5 NULL-parent nodes and `heading + paragraph`
-- returned no matches.
CREATE OR REPLACE MACRO leveled_structure(src, order_col, level_col, type_col, name_col, partition_col) AS TABLE
  WITH raw AS (
    SELECT * FROM leveled_nodes(src, order_col, level_col, type_col, name_col, partition_col)
  ),
  rooted AS (
    SELECT DISTINCT part, NULL::BIGINT AS ord_pre, (min(lvl) OVER (PARTITION BY part)) - 1 AS root_lvl
    FROM raw
  ),
  n AS (
    SELECT part, 0::BIGINT AS ord, root_lvl AS lvl, 'document' AS ty, '' AS nm,
           1::BIGINT AS node_id
    FROM rooted
    UNION ALL
    SELECT part, ord::BIGINT, lvl, ty, nm,
           row_number() OVER (PARTITION BY part ORDER BY ord) + 1 AS node_id
    FROM raw
  )
  SELECT
    a.node_id, a.ord, a.lvl, a.ty, a.nm, a.part,
    (SELECT max(p.node_id) FROM n p
      WHERE p.part = a.part AND p.ord < a.ord AND p.lvl < a.lvl)              AS parent_id,
    coalesce((SELECT min(e.ord) FROM n e
      WHERE e.part = a.part AND e.ord > a.ord AND e.lvl <= a.lvl), 2147483647) AS subtree_end
  FROM n a;

CREATE OR REPLACE MACRO leveled_ast(src, order_col, level_col, type_col, name_col, partition_col, tiny) AS TABLE
  WITH s AS (
    SELECT * FROM leveled_structure(src, order_col, level_col, type_col, name_col, partition_col)
  )
  SELECT
    a.node_id::BIGINT                                                        AS node_id,
    a.ty::VARCHAR                                                            AS type,
    (SELECT semantic_type   FROM read_ast(tiny) WHERE false)                 AS semantic_type,
    0::UTINYINT                                                              AS flags,
    a.nm::VARCHAR                                                            AS name,
    (SELECT qualified_name  FROM read_ast(tiny) WHERE false)                 AS qualified_name,
    NULL::VARCHAR                                                            AS signature_type,
    (SELECT parameters      FROM read_ast(tiny) WHERE false)                 AS parameters,
    NULL::VARCHAR[]                                                          AS modifiers,
    NULL::VARCHAR                                                            AS annotations,
    a.part::VARCHAR                                                          AS file_path,
    'leveled'                                                                AS language,
    NULL::UINTEGER                                                           AS start_line,
    NULL::UINTEGER                                                           AS end_line,
    a.parent_id::BIGINT                                                      AS parent_id,
    a.lvl::UINTEGER                                                          AS depth,
    (row_number() OVER (PARTITION BY a.part, a.parent_id ORDER BY a.ord) - 1)::INTEGER AS sibling_index,
    (SELECT count(*) FROM s c
      WHERE c.part = a.part AND c.ord > a.ord AND c.ord < a.subtree_end
        AND c.lvl = a.lvl + 1)::UINTEGER                                     AS children_count,
    (SELECT count(*) FROM s d
      WHERE d.part = a.part AND d.ord > a.ord AND d.ord < a.subtree_end)::UINTEGER AS descendant_count,
    (SELECT scope FROM read_ast(tiny) WHERE false)                           AS scope,
    a.nm::VARCHAR                                                            AS peek
  FROM s a;

-- WHAT SITTING_DUCK WOULD NEED TO CHANGE for this to stop being a hack:
--
--   1. Publish SEMANTIC_TYPE as a catalog type, or accept a source without it.
--      Today an outside extension cannot construct one, so the seven typed NULLs
--      above must be borrowed from a zero-row read_ast() call.
--   2. Accept a MINIMAL source schema -- node_id, parent_id, type, name, depth,
--      sibling_index, descendant_count, children_count, file_path -- and treat the
--      other twelve as optional, raising a clear error when a selector needs an
--      absent column. The precedent already exists: `[peek...]` against a table
--      parsed with peek := 'none' raises a re-parse hint rather than failing
--      obscurely.
--
-- Neither is a new engine. ast_select_from already reads its source through
-- query_table(), so it was always generic over the table -- the AST is simply the
-- only thing that had ever been passed to it.
