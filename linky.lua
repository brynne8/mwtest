--[[
Author: Alexander Misel

Dependencies:
* timerwheel: Pure Lua timerwheel implementation
* lua-iconv: Lua bindings for POSIX iconv
]]
local MediaWikiApi = require('mwtest/mwapi')
local Utils = require('mwtest/utils')
local socket = require('socket')
local mime = require('mime')
local wheel = require('timerwheel').new()

local function utf8char(unicode)
  local char = string.char
  if unicode <= 0x7F then return char(unicode) end

  if (unicode <= 0x7FF) then
    local Byte0 = 0xC0 + math.floor(unicode / 0x40);
    local Byte1 = 0x80 + (unicode % 0x40);
    return char(Byte0, Byte1);
  end;

  if (unicode <= 0xFFFF) then
    local Byte0 = 0xE0 +  math.floor(unicode / 0x1000);
    local Byte1 = 0x80 + (math.floor(unicode / 0x40) % 0x40);
    local Byte2 = 0x80 + (unicode % 0x40);
    return char(Byte0, Byte1, Byte2);
  end;

  if (unicode <= 0x10FFFF) then
    local code = unicode
    local Byte3= 0x80 + (code % 0x40);
    code       = math.floor(code / 0x40)
    local Byte2= 0x80 + (code % 0x40);
    code       = math.floor(code / 0x40)
    local Byte1= 0x80 + (code % 0x40);
    code       = math.floor(code / 0x40)
    local Byte0= 0xF0 + code;

    return char(Byte0, Byte1, Byte2, Byte3);
  end;

  error 'Unicode cannot be greater than U+10FFFF!'
end

local iconv = require('iconv')
local g2u = iconv.new('utf-8', 'gb18030')
local u2g = iconv.new('gb18030', 'utf-8')

local cqserver = socket.udp()
cqserver:setpeername('127.0.0.1', '11235')

function sendToServer(data)
  cqserver:send(data)
end

local timer_id
local enabled_groups = { ['631656280'] = true }

function sendClientHello()
  sendToServer('ClientHello 5678')
  print('ClientHello sent.')
  timer_id = wheel:set(280, sendClientHello)
end

local cqclient = socket.udp()
cqclient:setsockname('127.0.0.1', '5678')
cqclient:settimeout(1)
print('Client started')

function processGroupMsg(data)
  if enabled_groups[data[2]] then
    local msg = g2u:iconv(mime.unb64(data[4])):gsub('&#91;', '['):gsub('&#93;', ']'):gsub('&amp;', '&')
    msg = msg:gsub('%[CQ:emoji,id=(%d+)%]', function(m1)
      local code = tonumber(m1)
      if code then
        return utf8char(code)
      end
    end)
    local wikilink = msg:match('%[%[(.-)%]%]')
    if wikilink then
      sendToServer('GroupMessage ' .. data[2] .. ' ' ..
        mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/' .. MediaWikiApi.urlEncode(wikilink))) .. ' 0')
    end
  end
end

sendClientHello()

while true do
  local recvbuff, recvip, recvport = cqclient:receivefrom()
  if recvbuff then
    local data = recvbuff:split(' ')
    if data[1] == 'GroupMessage' then
      processGroupMsg(data)
    else
      print(recvbuff, recvip, recvport)
    end
  else
    wheel:step()
  end
end

cqserver:close()