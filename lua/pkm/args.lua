-- =============================================================================
-- pkm.args — One reading of a command's arguments, for every command
-- =============================================================================
-- Dependencies : none (pure; no editor state, no I/O)
-- Consumed by  : pkm.views, pkm.tags (their parse_command_args), and every
--                typed command from v1.12.0 onward
--
-- A Neovim user command hands its callback `opts.fargs` (the arguments already
-- split on whitespace) and `opts.bang`. Turning that into "which action, on
-- what, with which options" was open-coded in each command, so eleven commands
-- meant eleven slightly different readings of the same grammar. This module is
-- the single reading:
--
--     :PKM<Context>[!] <verb> [positional ...] [key=value ...]
--
-- `parse` owns only the *structure* — which token is the verb, which are
-- positional, which are `key=value`, and whether a `!` was given. What a verb
-- then means, and whether its arguments are well-formed, stays with the caller,
-- because that is domain knowledge a generic parser cannot hold. The two
-- existing parsers (`views`, `tags`) are thin wrappers over this; the point of
-- migrating them is to prove one reading serves both rather than becoming a
-- third.
--
-- The one genuine difference between callers is what a first token that is *not*
-- a declared verb means. For `:PKMView leituras` it is the default verb's
-- argument (open the view named "leituras"); for `:PKMTags sprinkle` it is a
-- mistake. `parse` does not decide this — it reports `is_verb`, and the caller
-- acts on it. That keeps the policy where the policy belongs.
--
-- Public API:
--   parse(opts, spec)            → parsed
--   complete_verbs(spec, arglead) → string[]  verbs matching the prefix
--
-- parsed = {
--   verb       : string|nil   the resolved verb (nil when spec declares none)
--   positional : string[]     the remaining words, in order
--   named      : table         { key = value } from key=value tokens (see spec.named)
--   bang       : boolean       whether the command was called with !
--   is_verb    : boolean       whether the first token matched a declared verb
-- }
--
-- spec = {
--   verbs   : string[]|nil     declared verbs; without this, everything is
--                              positional and `verb` is nil
--   default : string|nil       the verb assumed when the first token is not one
--   escape  : (string)->bool   optional: given the whole positional joined by
--                              spaces, return true to force the default verb and
--                              keep every token as its argument. This is how a
--                              view named after a verb still opens.
--   named   : boolean          opt in to key=value parsing. Off by default so a
--                              tag or name containing '=' is never eaten.
-- }
-- =============================================================================

local M = {}

-- Key of a `key=value` token: a letter, then word characters, `_` or `-`.
-- The value is everything after the first `=`, so `title=a=b` is title → "a=b".
local NAMED = '^([%a][%w_%-]*)=(.*)$'

--- Read a command's arguments into their structural parts.
---@param opts table  A command callback's opts (needs `.fargs`; reads `.bang`)
---@param spec table|nil
---@return table parsed
function M.parse(opts, spec)
  opts = opts or {}
  spec = spec or {}

  local named, positional = {}, {}
  for _, tok in ipairs(opts.fargs or {}) do
    local key, value = nil, nil
    if spec.named then key, value = tok:match(NAMED) end
    if key then
      named[key] = value
    else
      positional[#positional + 1] = tok
    end
  end

  local parsed = {
    verb       = nil,
    positional = positional,
    named      = named,
    bang       = opts.bang and true or false,
    is_verb    = false,
  }

  -- No verbs declared: the whole thing is positional.
  if not spec.verbs or #spec.verbs == 0 then
    return parsed
  end

  local declared = {}
  for _, v in ipairs(spec.verbs) do declared[v:lower()] = true end

  -- No positional at all: the default verb, with nothing to act on.
  if #positional == 0 then
    parsed.verb = spec.default
    return parsed
  end

  -- The whole positional names something the default verb takes as its
  -- argument (a view named "add"): the default verb wins over the token that
  -- looks like a verb.
  if spec.escape and spec.escape(table.concat(positional, ' ')) then
    parsed.verb = spec.default
    return parsed
  end

  -- First token is a declared verb: it is the verb, the rest is its argument.
  local first = positional[1]:lower()
  if declared[first] then
    parsed.verb    = first
    parsed.is_verb = true
    parsed.positional = {}
    for i = 2, #positional do parsed.positional[#parsed.positional + 1] = positional[i] end
    return parsed
  end

  -- First token is not a verb: the default verb, keeping every token. Whether
  -- that is "open this name" or "unknown action" is the caller's to decide from
  -- `is_verb`.
  parsed.verb = spec.default
  return parsed
end

--- The declared verbs matching a completion prefix, in declaration order.
--- Drawing completion from the same `spec.verbs` the parser reads is what stops
--- a verb from existing without completing, or completing without existing.
---@param spec table
---@param arglead string|nil  The partial word being completed
---@return string[]
function M.complete_verbs(spec, arglead)
  local lead = (arglead or ''):lower()
  local out  = {}
  for _, v in ipairs((spec and spec.verbs) or {}) do
    if v:lower():find(lead, 1, true) == 1 then out[#out + 1] = v end
  end
  return out
end

return M
