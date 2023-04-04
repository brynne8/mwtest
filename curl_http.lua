local curl = require('libcurl')
local ffi = require('ffi')

local function httpsget(url, headers, retry_times)
  local t = {}
  local h_strs = nil
  
  if headers then
    h_strs = {}
    local i = 0
    for k, v in pairs(headers) do
      table.insert(h_strs, k .. ': ' .. v)
    end
  end

  local e = assert(curl.easy{
    url = url,
    failonerror = true,
    httpheader = h_strs,
    accept_encoding = 'gzip, deflate',
    ssl_verifyhost = false,
    ssl_verifypeer = false,
    timeout = 60,
    writefunction = function(data, size)
      if size == 0 then return 0 end
      table.insert(t, ffi.string(data, size))
      return size
    end
  })

  local res, err, ecode
  for i = 1, retry_times do
    t = {}
    --print('attempt ' .. i)
    res, err, ecode = e:perform()
    if res then break end
  end
  e:close()
  if not res then return nil, err, ecode end
  return table.concat(t)
end

function url_encode(str)
  if str then
    str = string.gsub(str, '\n', '\r\n')
    str =
      string.gsub(
      str,
      '([^%w:/%-%_%.%~])',
      function(c)
        return string.format('%%%02X', string.byte(c))
      end
    )
  end
  return str
end

--- Convert HTTP arguments to a URL-encoded request body.
-- @param arguments (table) the arguments to convert
-- @return (string) a request body created from the URL-encoded arguments
function params(arguments)
  local body = nil
  for key, value in pairs(arguments) do
    if body then
      body = body .. '&'
    else
      body = ''
    end
    body = body .. url_encode(key) .. '=' .. url_encode(value)
  end
  return body or ''
end

return {
  httpsget = httpsget,
  params = params,
  url_encode = url_encode
}
