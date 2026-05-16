-- =============================================================================
-- pkm.filter — Filter expression parser and evaluator
-- =============================================================================
-- Dependencies : none
-- Consumed by  : pkm.export (match_file, collect_files),
--                pkm.views (planned), pkm.index (planned)
--
-- Implements a small boolean filter language over note fields.
-- All matching is case-insensitive. Tag matching is EXACT (case-insensitive):
-- tag:rpg matches only notes whose tags array contains "rpg", not notes whose
-- tags merely contain "rpg" as a substring. Title and text matching are
-- substring (case-insensitive, plain, never fuzzy).
--
-- Grammar:
--   expr     = and_expr (OR and_expr)*
--   and_expr = not_expr (AND not_expr)*
--   not_expr = NOT? atom
--   atom     = "(" expr ")" | predicate
--   predicate= field ":" value
--   field    = "tag" | "title" | "text"
--   value    = bare_word | "quoted string"
--
-- The parser is a hand-rolled recursive descent parser (~90 lines).
-- Quoted values may contain spaces; bare word values stop at whitespace.
-- Keywords (AND, OR, NOT) are case-insensitive.
--
-- Note data table consumed by eval():
--   { path=string, title=string, tags=string[], body=string }
--   path  — absolute file path (not used by eval, but carried for callers)
--   title — frontmatter title field
--   tags  — frontmatter tags array (strings)
--   body  — full body text, lines joined with newline, from content_start onward
--
-- Public API:
--   parse(expr)        → tree, nil  |  nil, error_string
--   eval(tree, note)   → boolean
--   from_legacy(tbl)   → tree | nil  (converts {tags_any, tags_all, title, text})
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Lexer
-- =============================================================================

--- Tokenize a filter expression string into a flat array of token tables.
--- Token types: AND, OR, NOT, LPAREN, RPAREN, PRED{field, value}, EOF.
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

    else
      -- Scan to end of bare token: stops at whitespace, parens, or end-of-string.
      -- This scan intentionally stops mid-quoted-value at an embedded space;
      -- the quoted-value branch below re-scans the original string for the
      -- closing quote, so the short scan does not cause a correctness problem.
      local j = i
      while j <= n and not expr:sub(j, j):match('[%s()]') do
        j = j + 1
      end
      local word = expr:sub(i, j - 1)

      local colon = word:find(':', 1, true)
      if colon then
        local field = word:sub(1, colon - 1):lower()

        -- Position of the character immediately after ':' in the original string.
        -- Derivation: word starts at i (1-indexed); colon is its 1-indexed offset
        -- within word; so ':' is at i+colon-1, and the char after ':' is i+colon.
        local after_colon = i + colon

        if after_colon <= n and expr:sub(after_colon, after_colon) == '"' then
          -- Quoted value: scan forward in the original string for the closing '"'.
          -- This correctly handles spaces inside the value.
          local val_start = after_colon + 1
          local k         = val_start
          while k <= n and expr:sub(k, k) ~= '"' do
            k = k + 1
          end
          if k > n then
            return nil, "unterminated quoted string in filter expression"
          end
          tokens[#tokens + 1] = {
            type  = 'PRED',
            field = field,
            value = expr:sub(val_start, k - 1),
          }
          i = k + 1  -- advance past closing '"'

        else
          -- Bare word value: already fully captured by the initial word scan.
          tokens[#tokens + 1] = {
            type  = 'PRED',
            field = field,
            value = word:sub(colon + 1),
          }
          i = j
        end

      else
        -- No colon → must be a keyword; anything else is an error.
        local upper = word:upper()
        if     upper == 'AND' then tokens[#tokens + 1] = { type = 'AND' }
        elseif upper == 'OR'  then tokens[#tokens + 1] = { type = 'OR'  }
        elseif upper == 'NOT' then tokens[#tokens + 1] = { type = 'NOT' }
        else
          return nil, string.format(
            "unexpected token '%s' at position %d — expected AND, OR, NOT, or field:value",
            word, i)
        end
        i = j
      end
    end
  end

  tokens[#tokens + 1] = { type = 'EOF' }
  return tokens, nil
end

-- =============================================================================
-- SECTION: Parser (recursive descent)
-- =============================================================================

-- Forward declarations required for mutual recursion among the four functions.
local parse_expr
local parse_and_expr
local parse_not_expr
local parse_atom

--- expr = and_expr (OR and_expr)*
---@param tokens table
---@param pos    integer  1-based index into tokens
---@return table|nil node,  integer|string  next_pos or error
parse_expr = function(tokens, pos)
  local node, new_pos = parse_and_expr(tokens, pos)
  if not node then return nil, new_pos end

  while tokens[new_pos] and tokens[new_pos].type == 'OR' do
    local right, next_pos = parse_and_expr(tokens, new_pos + 1)
    if not right then return nil, next_pos end
    node    = { type = 'OR', args = { node, right } }
    new_pos = next_pos
  end

  return node, new_pos
end

--- and_expr = not_expr (AND not_expr)*
parse_and_expr = function(tokens, pos)
  local node, new_pos = parse_not_expr(tokens, pos)
  if not node then return nil, new_pos end

  while tokens[new_pos] and tokens[new_pos].type == 'AND' do
    local right, next_pos = parse_not_expr(tokens, new_pos + 1)
    if not right then return nil, next_pos end
    node    = { type = 'AND', args = { node, right } }
    new_pos = next_pos
  end

  return node, new_pos
end

--- not_expr = NOT? atom
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
    if tok.field ~= 'tag' and tok.field ~= 'title' and tok.field ~= 'text' then
      return nil, string.format(
        "unknown field '%s' — valid fields are: tag, title, text", tok.field)
    end
    return { type = 'PRED', field = tok.field, value = tok.value }, pos + 1

  else
    return nil, string.format(
      "expected predicate or '(' but got '%s'", tok.type)
  end
end

-- =============================================================================
-- SECTION: Public API — parse
-- =============================================================================

--- Parse a filter expression string into an AST.
--- Returns (tree, nil) on success, (nil, error_string) on any parse failure.
---
--- The returned tree is a nested table of nodes:
---   Predicate : { type="PRED", field="tag"|"title"|"text", value=string }
---   Boolean   : { type="AND"|"OR", args={node, node, ...} }
---   Negation  : { type="NOT", args={node} }
---
--- Examples:
---   filter.parse('tag:rpg AND title:ringforge')
---   filter.parse('(tag:mathematics OR tag:physics) AND NOT tag:draft')
---   filter.parse('text:"Fourier transform" AND tag:analysis')
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

  -- Verify the whole token stream was consumed (no trailing garbage).
  if tokens[result] and tokens[result].type ~= 'EOF' then
    return nil, string.format(
      "unexpected '%s' after end of expression", tokens[result].type)
  end

  return tree, nil
end

-- =============================================================================
-- SECTION: Public API — eval
-- =============================================================================

--- Evaluate a parsed filter tree against a note data table.
--- Returns true if the note satisfies all constraints in the tree.
---
--- Matching rules:
---   tag:value   — EXACT match (case-insensitive) against each entry in note.tags
---   title:value — substring match (case-insensitive) in note.title
---   text:value  — substring match (case-insensitive) in note.body
---
--- The note table must contain:
---   note.tags   string[]  (may be nil or empty — treated as no tags)
---   note.title  string    (may be nil — treated as empty string)
---   note.body   string    (may be nil — treated as empty string)
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
      return tostring(note.body or ''):lower():find(val, 1, true) ~= nil
    end

    return false  -- unreachable after field validation in parse_atom, but safe

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

return M
