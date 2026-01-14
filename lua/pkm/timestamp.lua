-- lua/pkm/timestamp.lua
-- Flexible timestamp handling for PKM system with configurable defaults

local M = {}
local config = {}

function M.setup(user_config)
  config = user_config
  
  -- Set default behavior if not specified
  config.timestamp.default_format = config.timestamp.default_format or "full"
  config.timestamp.auto_timestamp = config.timestamp.auto_timestamp ~= false -- default true
  config.timestamp.prompt_on_create = config.timestamp.prompt_on_create or false -- default false
end

--- Parse timestamp from various formats
--- @param timestamp_str string Timestamp string
--- @return table|nil Parsed timestamp {year, month, day, hour, min, sec}
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

--- Format timestamp to string
--- @param ts table Timestamp table
--- @param format_type string|nil Format type (default from config or ts.format)
--- @return string Formatted timestamp
function M.format_timestamp(ts, format_type)
  format_type = format_type or ts.format or config.timestamp.default_format
  
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
    return string.format("%04d-%02d-%02d_%s",
      ts.year, ts.month, ts.day, config.timestamp.unknown_time_marker)
  
  else
    -- Default: use config default or full
    return M.format_timestamp(ts, config.timestamp.default_format or "full")
  end
end

--- Get current timestamp with default format
--- @param format_override string|nil Override default format
--- @return table Timestamp
function M.now(format_override)
  local date = os.date("*t")
  local format = format_override or config.timestamp.default_format or "full"
  
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
  elseif format == "date_unknown" then
    -- Date only with unknown marker
  elseif format == "date_only" then
    -- Date only
  end
  
  return ts
end

--- Create timestamp - uses default or prompts based on config
--- @param force_interactive boolean Force interactive mode
--- @return table|nil Timestamp or nil if cancelled
function M.create_timestamp(force_interactive)
  -- If auto timestamp enabled and not forcing interactive, return now
  if config.timestamp.auto_timestamp and not force_interactive then
    return M.now()
  end
  
  -- If prompt on create or force interactive, show interactive dialog
  if config.timestamp.prompt_on_create or force_interactive then
    return M.create_interactive()
  end
  
  -- Default: return current timestamp with default format
  return M.now()
end

--- Interactive timestamp creation (when explicitly requested)
--- @return table|nil Timestamp or nil if cancelled
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

--- Get ISO 8601 formatted timestamp for YAML frontmatter
--- @param ts table|nil Timestamp (uses now if nil)
--- @return string ISO 8601 formatted string
function M.to_iso8601(ts)
  ts = ts or M.now()
  
  if ts.hour then
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d",
      ts.year, ts.month, ts.day, ts.hour, ts.min, ts.sec or 0)
  else
    return string.format("%04d-%02d-%02d", ts.year, ts.month, ts.day)
  end
end

--- Convert old Google Docs timestamp format to new format
--- @param filename string Filename with timestamp
--- @return table|nil Parsed timestamp
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

--- Create filename with timestamp
--- @param base_name string Base name for file
--- @param ts table|nil Timestamp (uses now if nil)
--- @param extension string File extension (default ".md")
--- @return string Filename
function M.create_filename(base_name, ts, extension)
  ts = ts or M.now()
  extension = extension or ".md"
  
  local timestamp_str = M.format_timestamp(ts)
  return base_name .. "_" .. timestamp_str .. extension
end

--- Parse filename with timestamp
--- @param filename string Filename
--- @return string|nil Base name
--- @return table|nil Timestamp
--- @return string|nil Extension
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

--- Compare two timestamps
--- @param ts1 table First timestamp
--- @param ts2 table Second timestamp
--- @return number -1 if ts1 < ts2, 0 if equal, 1 if ts1 > ts2
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

--- Check if timestamp is valid
--- @param ts table Timestamp
--- @return boolean True if valid
--- @return string|nil Error message if invalid
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

--- Get human-readable timestamp
--- @param ts table Timestamp
--- @return string Human-readable string
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
