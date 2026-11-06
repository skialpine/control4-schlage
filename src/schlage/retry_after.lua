-- RFC 9110 HTTP-date / delay-seconds, interpreted in UTC without local DST.
local months =
  { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
local weekdays = {
  Sun = 0,
  Mon = 1,
  Tue = 2,
  Wed = 3,
  Thu = 4,
  Fri = 5,
  Sat = 6,
  Sunday = 0,
  Monday = 1,
  Tuesday = 2,
  Wednesday = 3,
  Thursday = 4,
  Friday = 5,
  Saturday = 6,
}
local function leaps(y)
  return math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400)
end
return function(value, now)
  if type(value) ~= "string" then
    return nil
  end
  value = value:match("^%s*(.-)%s*$")
  if value:match("^%d+$") then
    local seconds = tonumber(value)
    return seconds and seconds < math.huge and seconds or nil
  end
  local weekday, day, month, year, hour, minute, second =
    value:match("^(%a%a%a), (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$")
  if not day then
    weekday, day, month, year, hour, minute, second =
      value:match("^(%a+), (%d%d)%-(%a%a%a)%-(%d%d) (%d%d):(%d%d):(%d%d) GMT$")
    if year then
      local current = tonumber(os.date("!%Y", now))
      year = math.floor(current / 100) * 100 + tonumber(year)
      if year > current + 50 then
        year = year - 100
      end
    end
  end
  if not day then
    weekday, month, day, hour, minute, second, year =
      value:match("^(%a%a%a) (%a%a%a) ([ %d]%d) (%d%d):(%d%d):(%d%d) (%d%d%d%d)$")
  end
  day, year, hour, minute, second, month =
    tonumber(day), tonumber(year), tonumber(hour), tonumber(minute), tonumber(second), months[month]
  if
    not day
    or not year
    or not month
    or weekdays[weekday] == nil
    or year < 1601
    or hour > 23
    or minute > 59
    or second > 60
  then
    return nil
  end
  local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
  local lengths = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if day < 1 or day > lengths[month] then
    return nil
  end
  local days = 365 * (year - 1970) + leaps(year - 1) - leaps(1969) + day - 1
  for i = 1, month - 1 do
    days = days + lengths[i]
  end
  if (days + 4) % 7 ~= weekdays[weekday] then
    return nil
  end
  return math.max(0, days * 86400 + hour * 3600 + minute * 60 + second - now)
end
