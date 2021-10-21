local curl_http = require('curl_http')
local json = require('cjson')
local socket = require('socket')
-- local inspect = require('inspect')

local lastUnix = nil

function search(keyword)
  local res, err, ecode = curl_http.httpsget(
      'http://m.baidu.com/sf/vsearch?' .. curl_http.params{
        word = keyword,
        pd = 'realtime_ugc',
        pn = 0,
        rtt = 12,
        sa = 3,
        mod = 5,
        p_type = 1,
        data_type = 'json',
        atn = 'list'
      },
      nil, 1
    )
  if res and res:gsub('^%s+', ''):len() ~= 0 then
    local start_time = lastUnix or os.time() - 3600
    res = res:gsub('^%s+', '')
    res = json.decode(res).data.list
    local ret = {}
    for i, v in ipairs(res) do
      if i == 1 then lastUnix = tonumber(v.pubUnixTime) end
      if tonumber(v.pubUnixTime) <= start_time then break end
      table.insert(ret, {
        header = v.nick .. '@' .. (v.source or v.site)  .. '：(' .. v.pubTime .. ')',
        text = v.SubAbs:gsub('<.->', ''):gsub('%s+', '\255')
          .. (type(v.originContent) == 'string' and
              v.originContent:gsub('</br>', '__NL__'):gsub('%s+', '\255'):gsub('__NL__', '\n') or ''),
        url = v.source_url or v.url
      })
    end
    return ret
  else
    print(err, ecode)
  end
end

local lkserver = socket.udp()
lkserver:setpeername('127.0.0.1', '5678')

function sendToServer(data)
  for i, v in ipairs(data) do
    print('FeedGeneral 904780983 ' .. v.header .. '\n' ..
      v.text .. '\n' .. v.url)
    lkserver:send('FeedGeneral 904780983 ' .. v.header .. '\n' ..
      v.text .. '\n' .. v.url)
  end
end

while true do
  local ok, data = pcall(function() return search('维基百科') end)
  if ok and data then
    sendToServer(data)
    socket.sleep(600)
  end
end


