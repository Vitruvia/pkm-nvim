-- =============================================================================
-- pkm.timestamp — Timestamp parsing, formatting, and creation
-- =============================================================================
-- Dependencies : none (uses os.date only)
-- Consumed by  : pkm.journal, pkm.notes, pkm.yaml (via create_frontmatter),
--                pkm.init (via sync autocmd)
--
-- Timestamp table format: {year, month, day, hour?, min?, sec?, format}
-- format values: "full" | "date_time" | "date_only" | "date_unknown"
--
-- Public API:
--   setup(user_config)               → Initialize with resolved PKM config
--   parse_timestamp(str)             → timestamp table from filename string
--   format_timestamp(ts, format?)    → filename-safe string from timestamp table
--   now(format_override?)            → current time as timestamp table
--   create_timestamp(force?)         → auto or interactive based on config
--   create_interactive()             → fully prompt-driven timestamp creation
--   to_iso8601(ts?)                  → ISO 8601 string for YAML frontmatter
--   parse_legacy_filename(filename)  → timestamp from old Google Docs format
--   create_filename(base, ts?, ext?) → full filename string with timestamp
--   parse_filename(filename)         → (base, ts, ext) from a filename
--   compare(ts1, ts2)                → -1|0|1 ordering
--   validate(ts)                     → (boolean, string?) validity check
--   to_human(ts)                     → human-readable display string
-- =============================================================================
local M = {}

local config = {}

-- =============================================================================
-- SECTION: Setup
-- =============================================================================
---@param user_config table Resolved PKM config from pkm.config.resolve()
function M.setup(user_config)
  config = user_config or {}
  config.timestamp = config.timestamp or {}
  
  -- Set default behavior if not specified
  config.timestamp.default_format = config.timestamp.default_format or "full"
  config.timestamp.auto_timestamp = config.timestamp.auto_timestamp ~= false -- default true
  config.timestamp.prompt_on_create = config.timestamp.prompt_on_create or false -- default false
end

-- =============================================================================
-- SECTION: Parsing
-- =============================================================================
--- Parse a timestamp string from a PKM filename into a timestamp table.
--- Supports four formats: full (YYYY-MM-DD_HH-MM-SS), date_time
--- (YYYY-MM-DD_HH-MM), date_only (YYYY-MM-DD), date_unknown
--- (YYYY-MM-DD_99-99-99).
---@param timestamp_str string
---@return {year:integer, month:integer, day:integer, hour:integer?, min:integer?, sec:integer?, format:string}|nil
function M.parse_timestamp(timestamp_str)
  if not timestamp_str then return nil end
  
  -- Try full timestamp: YYYY-MM-DD_HH-MM-SS
  local year, month, day, hour, min, sec = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
      format = "full"
    }
  end
  
  -- Try date + time without seconds: YYYY-MM-DD_HH-MM
  year, month, day, hour, min = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = nil,
      format = "date_time"
    }
  end
  
  -- Try date only: YYYY-MM-DD
  year, month, day = timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = nil,
      min = nil,
      sec = nil,
      format = "date_only"
    }
  end
  
  -- Try date with unknown time: YYYY-MM-DD_99-99-99
  year, month, day = 
    timestamp_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_99%-99%-99$")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = nil,
      min = nil,
      sec = nil,
      format = "date_unknown"
    }
  end
  
  return nil
end

-- =============================================================================
-- SECTION: Formatting
-- =============================================================================
--- Format timestamp to string
function M.format_timestamp(ts, format_type)
  local default = (config.timestamp and config.timestamp.default_format) or "full"
  format_type = format_type or ts.format or default
  
  if format_type == "full" then
    return string.format("%04d-%02d-%02d_%02d-%02d-%02d",
      ts.year, ts.month, ts.day, ts.hour or 0, ts.min or 0, ts.sec or 0)
  
  elseif format_type == "date_time" then
    return string.format("%04d-%02d-%02d_%02d-%02d",
      ts.year, ts.month, ts.day, ts.hour or 0, ts.min or 0)
  
  elseif format_type == "date_only" then
    return string.format("%04d-%02d-%02d",
      ts.year, ts.month, ts.day)
  
  elseif format_type == "date_unknown" then
    local unknown_marker = (config.timestamp and config.timestamp.unknown_time_marker) or "99-99-99"
    return string.format("%04d-%02d-%02d_%s",
      ts.year, ts.month, ts.day, unknown_marker)
  
  else
    return M.format_timestamp(ts, default)
  end
end

-- =============================================================================
-- SECTION: Timestamp creation
-- =============================================================================
--- Return the current time as a timestamp table.
---@param format_override string|nil Override the config default format
---@return table Timestamp table
function M.now(format_override)
  local date = os.date("*t")
  local default = (config.timestamp and config.timestamp.default_format) or "full"
  local format = format_override or default
  
  local ts = {
    year = date.year,
    month = date.month,
    day = date.day,
    format = format,
  }
  
  if format == "full" then
    ts.hour = date.hour
    ts.min = date.min
    ts.sec = date.sec
  elseif format == "date_time" then
    ts.hour = date.hour
    ts.min = date.min
  end
  
  return ts
end

--- Create a timestamp using the configured default behavior.
--- If auto_timestamp is true (default), returns now(). If prompt_on_create
--- is true or force_interactive is set, prompts interactively.
---@param force_interactive boolean|nil Force interactive prompt regardless of config
---@return table|nil Timestamp table, or nil if cancelled
function M.create_timestamp(force_interactive)
  local auto = true
  if config.timestamp and config.timestamp.auto_timestamp == false then auto = false end
  
  if auto and not force_interactive then
    return M.now()
  end
  
  local prompt = false
  if config.timestamp and config.timestamp.prompt_on_create then prompt = true end

  if prompt or force_interactive then
    return M.create_interactive()
  end
  
  return M.now()
end

--- Interactively prompt for date, then time format (now/custom/unknown/none).
--- Returns nil if the user cancels or enters an invalid format.
---@return table|nil Timestamp table
function M.create_interactive()
  -- Date prompt
  vim.fn.inputsave()
  local date_str = vim.fn.input("Date (YYYY-MM-DD) [today]: ")
  vim.fn.inputrestore()
  
  local ts
  
  if date_str == "" then
    ts = M.now("date_only")
  else
    local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    
    if not year then
      vim.notify("Invalid date format", vim.log.levels.ERROR)
      return nil
    end
    
    ts = {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
    }
  end
  
  -- Time prompt
  vim.fn.inputsave()
  local time_choice = vim.fn.input(
    "Time (1=now, 2=custom, 3=unknown, 4=none) [1]: ", "1"
  )
  vim.fn.inputrestore()
  
  if time_choice == "" then time_choice = "1" end
  
  if time_choice == "1" then
    local now = os.date("*t")
    ts.hour = now.hour
    ts.min = now.min
    ts.sec = now.sec
    ts.format = "full"
    
  elseif time_choice == "2" then
    vim.fn.inputsave()
    local time_str = vim.fn.input("Time (HH:MM or HH:MM:SS): ")
    vim.fn.inputrestore()
    
    local hour, min, sec = time_str:match("^(%d%d):(%d%d):(%d%d)$")
    if hour then
      ts.hour = tonumber(hour)
      ts.min = tonumber(min)
      ts.sec = tonumber(sec)
      ts.format = "full"
    else
      hour, min = time_str:match("^(%d%d):(%d%d)$")
      if hour then
        ts.hour = tonumber(hour)
        ts.min = tonumber(min)
        ts.format = "date_time"
      else
        vim.notify("Invalid time format", vim.log.levels.ERROR)
        return nil
      end
    end
    
  elseif time_choice == "3" then
    ts.format = "date_unknown"
    
  elseif time_choice == "4" then
    ts.format = "date_only"
    
  else
    vim.notify("Invalid choice", vim.log.levels.ERROR)
    return nil
  end
  
  return ts
end

-- =============================================================================
-- SECTION: ISO 8601 conversion
-- =============================================================================
--- Convert a timestamp table to an ISO 8601 string for YAML frontmatter.
--- Includes time component if ts.hour is present; date-only otherwise.
--- Defaults to current time if ts is nil.
---@param ts table|nil Timestamp table (default: now())
---@return string e.g. "2026-05-09T22:17:17" or "2026-05-09"
function M.to_iso8601(ts)
  ts = ts or M.now()
  
  if ts.hour then
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d",
      ts.year, ts.month, ts.day, ts.hour, ts.min, ts.sec or 0)
  else
    return string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
  end
end

-- =============================================================================
-- SECTION: Filename utilities
-- =============================================================================
--- Attempt to extract a date from an old Google Docs-style filename.
--- Returns a date_only timestamp table or nil if no match.
---@param filename string
---@return table|nil
function M.parse_legacy_filename(filename)
  local year, month, day = filename:match("(%d%d%d%d)%-(%d+)%-(%d+)")
  
  if year then
    return {
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      format = "date_only"
    }
  end
  
  return nil
end

--- Build a full filename string: base_name + "_" + formatted timestamp + extension.
---@param base_name string Prefix e.g. "journal" or "scratch"
---@param ts table|nil Timestamp table (default: now())
---@param extension string|nil File extension (default: ".md")
---@return string
function M.create_filename(base_name, ts, extension)
  ts = ts or M.now()
  extension = extension or ".md"
  
  local timestamp_str = M.format_timestamp(ts)
  return base_name .. "_" .. timestamp_str .. extension
end

--- Split a filename into its base name, timestamp, and extension.
--- Returns the original filename as base and nil timestamp if no match.
---@param filename string
---@return string base, table|nil ts, string ext
function M.parse_filename(filename)
  local name, ext = filename:match("^(.+)(%.%w+)$")
  if not name then
    name = filename
    ext = ""
  end
  
  local base, timestamp_str = name:match("^(.+)_(%d%d%d%d%-.+)$")
  
  if not base or not timestamp_str then
    return filename, nil, ext
  end
  
  local ts = M.parse_timestamp(timestamp_str)
  
  return base, ts, ext
end

-- =============================================================================
-- SECTION: Comparison and validation
-- =============================================================================
--- Compare two timestamp tables.
--- Compares year, month, day, then time components if present.
--- A timestamp with time is considered later than one without (same date).
---@param ts1 table
---@param ts2 table
---@return integer -1 if ts1 < ts2, 0 if equal, 1 if ts1 > ts2
function M.compare(ts1, ts2)
  if ts1.year ~= ts2.year then
    return ts1.year < ts2.year and -1 or 1
  end
  if ts1.month ~= ts2.month then
    return ts1.month < ts2.month and -1 or 1
  end
  if ts1.day ~= ts2.day then
    return ts1.day < ts2.day and -1 or 1
  end
  
  if not ts1.hour and not ts2.hour then
    return 0
  end
  
  if ts1.hour and not ts2.hour then
    return 1
  end
  if not ts1.hour and ts2.hour then
    return -1
  end
  
  if ts1.hour ~= ts2.hour then
    return ts1.hour < ts2.hour and -1 or 1
  end
  if ts1.min ~= ts2.min then
    return ts1.min < ts2.min and -1 or 1
  end
  
  if ts1.sec and ts2.sec then
    if ts1.sec ~= ts2.sec then
      return ts1.sec < ts2.sec and -1 or 1
    end
  end
  
  return 0
end

--- Validate that a timestamp table has valid date and time components.
---@param ts table
---@return boolean valid
---@return string|nil error_message
function M.validate(ts)
  if not ts.year or not ts.month or not ts.day then
    return false, "Missing date components"
  end
  
  if ts.year < 1900 or ts.year > 2100 then
    return false, "Invalid year"
  end
  
  if ts.month < 1 or ts.month > 12 then
    return false, "Invalid month"
  end
  
  if ts.day < 1 or ts.day > 31 then
    return false, "Invalid day"
  end
  
  if ts.hour then
    if ts.hour < 0 or ts.hour > 23 then
      return false, "Invalid hour"
    end
  end
  
  if ts.min then
    if ts.min < 0 or ts.min > 59 then
      return false, "Invalid minute"
    end
  end
  
  if ts.sec then
    if ts.sec < 0 or ts.sec > 59 then
      return false, "Invalid second"
    end
  end
  
  return true
end

--- Format a timestamp as a human-readable display string.
--- Examples: "2026-05-09 at 22:17:17", "2026-05-09", "2026-05-09 (time unknown)"
---@param ts table
---@return string
function M.to_human(ts)
  local date_str = string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
  
  if not ts.hour then
    if ts.format == "date_unknown" then
      return date_str .. " (time unknown)"
    else
      return date_str
    end
  end
  
  if ts.sec then
    return string.format("%s at %02d:%02d:%02d",
      date_str, ts.hour, ts.min, ts.sec)
  else
    return string.format("%s at %02d:%02d",
      date_str, ts.hour, ts.min)
  end
end

return M
