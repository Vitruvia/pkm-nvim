-- =============================================================================
-- pkm.filter — Filter expression parser and evaluator
-- =============================================================================
-- Dependencies : none
-- Consumed by  : pkm.export (match_file, collect_files),
--                pkm.views, pkm.telescope, pkm.ui
--
-- Implements a small boolean filter language over note fields.
-- All matching is case-insensitive. Tag matching via the tag: field is EXACT
-- (case-insensitive); title:, text:, filename:, and any: matching are plain
-- substring (never fuzzy).
--
-- Grammar:
--   expr      = and_expr (OR and_expr)*
--   and_expr  = not_expr (AND not_expr)*
--   not_expr  = NOT? atom
--   atom      = "(" expr ")" | predicate
--   predicate = (field ":")? value
--   field    = "tag" | "title" | "text" | "filename" | "type" | "any"
--   value     = bare_word | "quoted string"
--
-- When no field prefix is present, or when the left side of a colon is not a
-- known field, the token is treated as an `any` predicate. `any` evaluates as
-- a case-insensitive plain substring test across title, body, filename, and
-- tag values simultaneously. A standalone quoted string ("ring forge") is also
-- an `any` predicate. Literal keywords or colons can be forced into `any` by
-- quoting them ("and", "http://example.com").
--
-- Disambiguation rule:
--   word:word  →  field predicate   ONLY when the left side is a known field
--   word:word  →  any predicate     when the left side is unknown
--   word       →  any predicate
--   "..."      →  any predicate
--
-- Note data table consumed by eval():
--   { path=string, filename=string, title=string, tags=string[], body=string }
--   path     — absolute file path (not matched by eval; carried for callers)
--   filename — file stem without extension
--   title    — frontmatter title if set; filename stem with underscores replaced if not
--   tags     — frontmatter tags array (lowercase strings)
--   body     — note body (lines after frontmatter joined with "\n")
--   note_type — index-computed type: 'note'|'agg'|'bib'|'journal'|'scratch'|'other'
--
-- Public API:
--   parse(expr)        → tree, nil  |  nil, error_string
--   parse_prompt(expr) → tree | nil  — lenient parse for a live (as-you-type)
--                        prompt; never errors mid-keystroke
--   eval(tree, note)   → boolean
--   tag_sets(tree)     → the tag sets satisfying the expression, with the
--                        conditions no tag can reach — pure
--   from_legacy(tbl)   → tree | nil  (converts {tags_any, tags_all, title, text})
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Lexer
-- =============================================================================

--- Known field names. Used by the tokenizer to distinguish field predicates
--- from bare-word any-predicates. "any" is the explicit form.
local KNOWN_FIELDS = {
  tag = true, title = true, text = true,
  filename = true, any = true, type = true,
}

--- Tokenize a filter expression string into a flat array of token tables.
--- Token types: AND, OR, NOT, LPAREN, RPAREN, PRED{field, value}, EOF.
---
--- A PRED token is produced for:
---   known_field:value          →  PRED{field=known_field, value=value}
---   known_field:"quoted value" →  PRED{field=known_field, value=quoted}
---   unknown_field:value        →  PRED{field='any',       value='unknown_field:value'}
---   bare_word                  →  PRED{field='any',       value=bare_word}
---   "quoted string"            →  PRED{field='any',       value=quoted string}
---
--- Returns (tokens, nil) on success, (nil, error_string) on unrecognised input.
---@param expr string
---@return table|nil tokens
---@return string|nil err
local function tokenize(expr)
  local tokens = {}
  local i      = 1
  local n      = #expr

  while i <= n do
    local c = expr:sub(i, i)

    -- Skip whitespace
    if c:match('%s') then
      i = i + 1

    elseif c == '(' then
      tokens[#tokens + 1] = { type = 'LPAREN' }
      i = i + 1

    elseif c == ')' then
      tokens[#tokens + 1] = { type = 'RPAREN' }
      i = i + 1

    elseif c == '"' then
      -- Standalone quoted string → any predicate.
      local j = i + 1
      while j <= n and expr:sub(j, j) ~= '"' do j = j + 1 end
      if j > n then return nil, "unclosed quote in filter expression" end
      tokens[#tokens + 1] = { type = 'PRED', field = 'any', value = expr:sub(i + 1, j - 1) }
      i = j + 1

    else
      -- Read bare word until whitespace, paren, or end-of-string.
      -- Stops before '"' so that field:"quoted value" can be handled below.
      local j = i
      while j <= n and not expr:sub(j, j):match('[%s%(%)"]') do
        j = j + 1
      end
      local raw = expr:sub(i, j - 1)
      i = j

      -- Keywords (case-insensitive) take priority.
      local upper = raw:upper()
      if upper == 'AND' then
        tokens[#tokens + 1] = { type = 'AND' }
      elseif upper == 'OR' then
        tokens[#tokens + 1] = { type = 'OR' }
      elseif upper == 'NOT' then
        tokens[#tokens + 1] = { type = 'NOT' }
      else
        local colon = raw:find(':', 1, true)
        if colon and colon > 1 then
          local field      = raw:sub(1, colon - 1)
          local value_rest = raw:sub(colon + 1)

          if KNOWN_FIELDS[field] then
            local value
            if value_rest == '' then
              -- No inline value; check for a quoted value immediately following
              -- (e.g. tag:"ring forge" — scan stopped before the '"').
              if i <= n and expr:sub(i, i) == '"' then
                local qj = i + 1
                while qj <= n and expr:sub(qj, qj) ~= '"' do qj = qj + 1 end
                if qj > n then return nil, "unclosed quote in filter expression" end
                value = expr:sub(i + 1, qj - 1)
                i = qj + 1
              else
                return nil, string.format("field '%s:' has no value", field)
              end
            else
              value = value_rest
            end
            tokens[#tokens + 1] = { type = 'PRED', field = field, value = value }
          else
            -- Unknown field → treat the whole raw token as an any value.
            -- e.g. "body:text" or "http://example.com"
            tokens[#tokens + 1] = { type = 'PRED', field = 'any', value = raw }
          end
        else
          -- No colon (and not a keyword) → bare any predicate.
          tokens[#tokens + 1] = { type = 'PRED', field = 'any', value = raw }
        end
      end
    end
  end

  tokens[#tokens + 1] = { type = 'EOF' }
  return tokens, nil
end

-- =============================================================================
-- SECTION: Parser (recursive descent)
-- =============================================================================

-- Forward declarations required by mutual recursion.
local parse_expr, parse_and_expr, parse_not_expr, parse_atom

parse_expr = function(tokens, pos)
  local left, new_pos = parse_and_expr(tokens, pos)
  if not left then return nil, new_pos end
  local args = { left }
  while tokens[new_pos] and tokens[new_pos].type == 'OR' do
    local right, rpos = parse_and_expr(tokens, new_pos + 1)
    if not right then return nil, rpos end
    args[#args + 1] = right
    new_pos = rpos
  end
  if #args == 1 then return args[1], new_pos end
  return { type = 'OR', args = args }, new_pos
end

parse_and_expr = function(tokens, pos)
  local left, new_pos = parse_not_expr(tokens, pos)
  if not left then return nil, new_pos end
  local args = { left }
  while tokens[new_pos] and tokens[new_pos].type == 'AND' do
    local right, rpos = parse_not_expr(tokens, new_pos + 1)
    if not right then return nil, rpos end
    args[#args + 1] = right
    new_pos = rpos
  end
  if #args == 1 then return args[1], new_pos end
  return { type = 'AND', args = args }, new_pos
end

parse_not_expr = function(tokens, pos)
  if tokens[pos] and tokens[pos].type == 'NOT' then
    local child, new_pos = parse_atom(tokens, pos + 1)
    if not child then return nil, new_pos end
    return { type = 'NOT', args = { child } }, new_pos
  end
  return parse_atom(tokens, pos)
end

--- atom = "(" expr ")" | predicate
parse_atom = function(tokens, pos)
  local tok = tokens[pos]
  if not tok or tok.type == 'EOF' then
    return nil, "unexpected end of expression"
  end

  if tok.type == 'LPAREN' then
    local node, new_pos = parse_expr(tokens, pos + 1)
    if not node then return nil, new_pos end
    local closing = tokens[new_pos]
    if not closing or closing.type ~= 'RPAREN' then
      return nil, "expected ')' to close parenthesis"
    end
    return node, new_pos + 1

  elseif tok.type == 'PRED' then
    -- Field is guaranteed valid by the tokenizer (KNOWN_FIELDS); no re-check needed.
    return { type = 'PRED', field = tok.field, value = tok.value }, pos + 1

  else
    return nil, string.format("expected predicate or '(' but got '%s'", tok.type)
  end
end

-- =============================================================================
-- SECTION: Public API — parse
-- =============================================================================

--- Parse a filter expression string into an AST.
--- Returns (tree, nil) on success, (nil, error_string) on any parse failure.
---
--- The returned tree is a nested table of nodes:
---   Predicate : { type="PRED", field="tag"|"title"|"text"|"filename"|"any",
---                 value=string }
---   Boolean   : { type="AND"|"OR", args={node, node, ...} }
---   Negation  : { type="NOT", args={node} }
---
--- Examples:
---   filter.parse('fourier')                           -- any:fourier
---   filter.parse('"ring forge"')                      -- any:"ring forge"
---   filter.parse('tag:rpg AND title:ringforge')
---   filter.parse('(tag:mathematics OR tag:physics) AND NOT tag:draft')
---   filter.parse('text:"Fourier transform" AND tag:analysis')
---   filter.parse('body:text')                         -- any:"body:text" (unknown field)
---
---@param expr string
---@return table|nil tree
---@return string|nil err
function M.parse(expr)
  if type(expr) ~= 'string' or expr:match('^%s*$') then
    return nil, "filter expression must be a non-empty string"
  end

  local tokens, lex_err = tokenize(expr)
  if not tokens then
    return nil, lex_err
  end

  local tree, result = parse_expr(tokens, 1)
  if not tree then
    return nil, "parse error: " .. result
  end

  if tokens[result] and tokens[result].type ~= 'EOF' then
    return nil, string.format(
      "unexpected '%s' after end of expression", tokens[result].type)
  end

  return tree, nil
end

--- Parse a *live* (as-you-type) filter prompt into a tree, forgivingly.
---
--- The single rule every live picker shares, so it lives in one place:
---   empty / whitespace  → nil    (the caller reads nil as "match everything")
---   parseable expression → the AST from M.parse()
---   unparseable / partial (mid-typing "AND", an unclosed paren) → a bare
---                          any-predicate over the raw text
---
--- The last case is what keeps a prompt from being rejected between keystrokes:
--- a half-typed boolean still narrows the list as a plain substring instead of
--- clearing it. Never returns an error — unlike M.parse(), which reports one.
---@param prompt string|nil
---@return table|nil tree
function M.parse_prompt(prompt)
  if type(prompt) ~= 'string' or prompt:match('^%s*$') then return nil end
  return M.parse(prompt) or { type = 'PRED', field = 'any', value = prompt }
end

-- =============================================================================
-- SECTION: Public API — eval
-- =============================================================================

--- Evaluate a parsed filter tree against a note data table.
--- Returns true if the note satisfies all constraints in the tree.
---
--- Matching rules:
---   tag:value      — EXACT match (case-insensitive) against each entry in note.tags
---   title:value    — substring match (case-insensitive) in note.title
---   text:value     — substring match (case-insensitive) in note.body
---   filename:value — substring match (case-insensitive) in note.filename
---   any:value      — substring match across title, body, filename, AND tag values
---                    (tag values are also substring for `any:`, unlike exact for `tag:`)
---
---@param tree table   AST node produced by M.parse()
---@param note table   Note data table
---@return boolean
function M.eval(tree, note)
  if tree.type == 'PRED' then
    local val = tree.value:lower()

    if tree.field == 'tag' then
      for _, t in ipairs(note.tags or {}) do
        if tostring(t):lower() == val then return true end
      end
      return false

    elseif tree.field == 'title' then
      return tostring(note.title or ''):lower():find(val, 1, true) ~= nil

    elseif tree.field == 'text' then
      local body_l = note.body_lower or tostring(note.body or ''):lower()
      return body_l:find(val, 1, true) ~= nil

    elseif tree.field == 'filename' then
      return tostring(note.filename or ''):lower():find(val, 1, true) ~= nil

    elseif tree.field == 'type' then
      return (note.note_type or 'other'):lower() == val

    elseif tree.field == 'any' then
      if tostring(note.title    or ''):lower():find(val, 1, true) then return true end
      local body_l = note.body_lower or tostring(note.body or ''):lower()
      if body_l:find(val, 1, true) then return true end
      if tostring(note.filename or ''):lower():find(val, 1, true) then return true end
      for _, t in ipairs(note.tags or {}) do
        if tostring(t):lower():find(val, 1, true) then return true end
      end
      return false
    end

    return false  -- unreachable; tokenizer guarantees field is in KNOWN_FIELDS

  elseif tree.type == 'AND' then
    for _, arg in ipairs(tree.args) do
      if not M.eval(arg, note) then return false end
    end
    return true

  elseif tree.type == 'OR' then
    for _, arg in ipairs(tree.args) do
      if M.eval(arg, note) then return true end
    end
    return false

  elseif tree.type == 'NOT' then
    return not M.eval(tree.args[1], note)
  end

  return false
end

-- =============================================================================
-- SECTION: Public API — from_legacy
-- =============================================================================

--- Convert a legacy filter table to a filter tree.
--- Provides backward compatibility with the existing export.lua filter format.
---
--- Legacy format:
---   {
---     tags_any = {"tag1", "tag2"},  -- OR logic: note has at least one
---     tags_all = {"tag3", "tag4"},  -- AND logic: note has all of these
---     title    = "substring",       -- title contains this string
---     text     = "substring",       -- body contains this string
---   }
---
--- All present fields are AND-ed together at the top level.
--- Returns nil when no fields are specified (no constraints = match everything).
---
---@param tbl table  Legacy filter table; any field may be absent or nil
---@return table|nil tree
function M.from_legacy(tbl)
  local parts = {}

  if tbl.tags_any and #tbl.tags_any > 0 then
    if #tbl.tags_any == 1 then
      parts[#parts + 1] = { type = 'PRED', field = 'tag', value = tbl.tags_any[1] }
    else
      local args = {}
      for _, t in ipairs(tbl.tags_any) do
        args[#args + 1] = { type = 'PRED', field = 'tag', value = t }
      end
      parts[#parts + 1] = { type = 'OR', args = args }
    end
  end

  if tbl.tags_all and #tbl.tags_all > 0 then
    for _, t in ipairs(tbl.tags_all) do
      parts[#parts + 1] = { type = 'PRED', field = 'tag', value = t }
    end
  end

  if tbl.title and tbl.title ~= '' then
    parts[#parts + 1] = { type = 'PRED', field = 'title', value = tbl.title }
  end

  if tbl.text and tbl.text ~= '' then
    parts[#parts + 1] = { type = 'PRED', field = 'text', value = tbl.text }
  end

  if #parts == 0 then return nil end
  if #parts == 1 then return parts[1] end
  return { type = 'AND', args = parts }
end

-- =============================================================================
-- SECTION: Tag satisfiability
-- =============================================================================
--
-- "Put this note in that view" has a precise meaning here: a view is a filter,
-- so belonging to it means satisfying the filter. Tags are the only part of a
-- note a bulk operation may safely rewrite for that purpose — a title or a body
-- cannot be invented — so the question is which *sets of tags* make an
-- expression true, and which parts of it no tag can reach.
--
-- The answer is the expression in disjunctive normal form: a list of
-- alternatives, any one of which suffices. Each alternative says which tags must
-- be present, which must be absent, and which non-tag conditions it still
-- depends on (its blockers). Negation is pushed down as it goes, so `NOT` over a
-- group becomes De Morgan's dual rather than a special case later.

--- Merge two alternatives. Returns nil when they contradict: a tag required by
--- one and forbidden by the other makes the combination unsatisfiable, and a
--- combination that cannot hold is not an alternative at all.
---@param a table
---@param b table
---@return table|nil
local function merge_alt(a, b)
  local add, remove = {}, {}

  for tag in pairs(a.add) do add[tag] = true end
  for tag in pairs(b.add) do
    if a.remove[tag] then return nil end
    add[tag] = true
  end
  for tag in pairs(a.remove) do remove[tag] = true end
  for tag in pairs(b.remove) do
    if a.add[tag] then return nil end
    remove[tag] = true
  end

  local blockers = {}
  vim.list_extend(blockers, a.blockers)
  vim.list_extend(blockers, b.blockers)

  return { add = add, remove = remove, blockers = blockers }
end

--- Alternatives satisfying (or, when negated, refuting) one subtree.
---@param tree    table
---@param negated boolean
---@return table[]  each { add = set, remove = set, blockers = string[] }
local function alternatives(tree, negated)
  if tree.type == 'PRED' then
    local value = tostring(tree.value):lower()

    if tree.field == 'tag' then
      if negated then
        return { { add = {}, remove = { [value] = true }, blockers = {} } }
      end
      return { { add = { [value] = true }, remove = {}, blockers = {} } }
    end

    -- Any other field describes something tags cannot change.
    return { {
      add = {}, remove = {},
      blockers = { (negated and 'NOT ' or '') .. tree.field .. ':' .. tree.value },
    } }

  elseif tree.type == 'NOT' then
    return alternatives(tree.args[1], not negated)

  elseif tree.type == 'AND' or tree.type == 'OR' then
    -- Under negation the connective flips: NOT(a AND b) is NOT a OR NOT b.
    local as_union = (tree.type == 'OR') ~= negated

    local out
    for _, arg in ipairs(tree.args) do
      local child = alternatives(arg, negated)

      if not out then
        out = child
      elseif as_union then
        vim.list_extend(out, child)
      else
        local crossed = {}
        for _, left in ipairs(out) do
          for _, right in ipairs(child) do
            local merged = merge_alt(left, right)
            if merged then crossed[#crossed + 1] = merged end
          end
        end
        out = crossed
      end
    end

    return out or {}
  end

  return {}
end

--- The tag sets that make a filter expression true.
---
--- Each returned alternative is one way to satisfy the whole expression: apply
--- its `add` and `remove` to a note and the filter matches — **provided** its
--- `blockers` are empty. A blocker names a condition no tag can produce
--- (`title:`, `text:`, `type:`, `filename:`, `any:`), and an alternative
--- carrying one is reported rather than hidden, so a caller can say *why*
--- membership is not achievable instead of silently writing tags that will not
--- make the note match.
---
--- An empty result means the expression is self-contradictory (`tag:a AND NOT
--- tag:a`) and nothing satisfies it.
---
--- Pure: no editor state, no I/O.
---@param tree table  A parse() result
---@return { add: string[], remove: string[], blockers: string[] }[]
function M.tag_sets(tree)
  if not tree then return {} end

  local out = {}
  for _, alt in ipairs(alternatives(tree, false)) do
    local add, remove = {}, {}
    for tag in pairs(alt.add) do add[#add + 1] = tag end
    for tag in pairs(alt.remove) do remove[#remove + 1] = tag end
    table.sort(add)
    table.sort(remove)

    out[#out + 1] = { add = add, remove = remove, blockers = alt.blockers }
  end

  return out
end

return M
