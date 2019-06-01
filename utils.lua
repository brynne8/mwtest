local M = {}

function M.getTime (iso8601)
  local y, m, d, H, M, S = iso8601:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  return os.time{ year = y, month = m, day = d, hour = H, min = M, sec = S } + 28800
end

function M.hasValue (tab, val)
  if not tab then
    return false
  end
  for _, value in ipairs(tab) do
    if value == val then return true end
  end
  return false
end

function M.subrange(t, first, last)
  local sub = {}
  for i=first,last do
    sub[#sub + 1] = t[i]
  end
  return sub
end

-- only for arrays
table.filter = function(t, filterIter)
  local out = {}

  for i, v in ipairs(t) do
    if filterIter(v, i, t) then
      table.insert(out, v)
    end
  end

  return out
end

table.map = function(t, mapFunc)
  local out = {}

  for i, v in ipairs(t) do
    out[i] = mapFunc(v, i, t)
  end

  return out
end

table.reverse = function (t)
  local reversedTable = {}
  local itemCount = #t
  for k, v in ipairs(t) do
    reversedTable[itemCount + 1 - k] = v
  end
  return reversedTable
end

function M.tableConcat(t1, t2)
  for i=1, #t2 do
    t1[#t1+1] = t2[i]
  end
  return t1
end

function string.split(str, pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = '(.-)' .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= '' then
         table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end

return M