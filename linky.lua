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
    local Byte0 = 0xC0 + bit.rshift(unicode, 6);
    local Byte1 = 0x80 + bit.band(unicode, 0x3F);
    return char(Byte0, Byte1);
  end;

  if (unicode <= 0xFFFF) then
    local Byte0 = 0xE0 + bit.rshift(unicode, 12);
    local Byte1 = 0x80 + bit.band(bit.rshift(unicode, 6), 0x3F);
    local Byte2 = 0x80 + bit.band(unicode, 0x3F);
    return char(Byte0, Byte1, Byte2);
  end;

  if (unicode <= 0x10FFFF) then
    local code = unicode
    local Byte3= 0x80 + bit.band(code, 0x3F);
    code       = bit.rshift(code, 6)
    local Byte2= 0x80 + bit.band(code, 0x3F);
    code       = bit.rshift(code, 6)
    local Byte1= 0x80 + bit.band(code, 0x3F);
    code       = bit.rshift(code, 6)
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
  print(data)
  cqserver:send(data)
end

local timer_id
local enabled_groups = { ['10000'] = true }

function sendClientHello()
  sendToServer('ClientHello 5678')
  print('ClientHello sent.')
  timer_id = wheel:set(280, sendClientHello)
end

local cqclient = socket.udp()
cqclient:setsockname('127.0.0.1', '5678')
cqclient:settimeout(1)
print('Client started')

function linky(msg, group_id)
  msg = msg:gsub('%[CQ:emoji,id=(%d+)%]', function(m1)
    local code = tonumber(m1)
    if code then
      return utf8char(code)
    end
  end)
  local wikilink = msg:match('%[%[(.-)%]%]')
  if wikilink then
    sendToServer('GroupMessage ' .. group_id .. ' ' ..
      mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/' .. MediaWikiApi.urlEncode(wikilink))) .. ' 0')
    return
  end
  wikilink = msg:match('{{([^|]*)|?.*}}')
  if wikilink then
    sendToServer('GroupMessage ' .. group_id .. ' ' ..
      mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/Template:' .. MediaWikiApi.urlEncode(wikilink))) .. ' 0')
    return
  end
end

local spamlist = { '翻墙', '梯子' }

local spamusers = {}

function spamwords(msg, group_id, qq_num)
  for _, v in ipairs(spamlist) do
    local result = msg:match(v)
    if result then
      if spamusers[qq_num] then
        local curtime = os.time()
        if curtime - spamusers[qq_num].last_block > 3600 then
          spamusers[qq_num].count = 1
        else
          spamusers[qq_num].count = spamusers[qq_num].count + 1
        end
        spamusers[qq_num].last_block = curtime
      else
        spamusers[qq_num] = {
          count = 1,
          last_block = os.time()
        }
      end
      sendToServer('GroupBan ' .. group_id .. ' ' .. qq_num .. ' ' .. 600 * spamusers[qq_num].count)
      return true
    end
  end
end

local replylist = {
  ['^表白vva$'] = '谢谢。'
}

function reply(msg, group_id)
  for k, v in pairs(replylist) do
    for _, pat in ipairs(k:split('|')) do
      local result = msg:match(pat)
      if result then
        sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv(v)) .. ' 0')
        return true
      end
    end
  end
end

local dont_checkcard = { ['10000'] = true }

function check_groupcard(uinfo_str, group_id, qq_num)
  if dont_checkcard[group_id] then
    return
  end
  local strlen = bit.lshift(uinfo_str:byte(17), 8) + uinfo_str:byte(18)
  local start = 19 + strlen
  strlen = bit.lshift(uinfo_str:byte(start), 8) + uinfo_str:byte(start+1)
  start = start + 2
  if strlen == 0 then
    sendToServer('GroupMessage ' .. group_id .. ' ' .. 
      mime.b64(u2g:iconv('[CQ:at,qq=' .. qq_num .. '] 请按群公告要求修改群名片')) .. ' 0')
  else
    local group_card = g2u:iconv(uinfo_str:sub(start, start + strlen - 1))
    if not group_card:match('^User:') and not group_card:match('^学习:') and
      not group_card:match('^Bot:') then
      sendToServer('GroupMessage ' .. group_id .. ' ' .. 
      mime.b64(u2g:iconv('[CQ:at,qq=' .. qq_num .. '] 您的群名片不符合规定，请按群公告要求修改群名片')) .. ' 0')
    end
  end
end

function processGroupMsg(data)
  if enabled_groups[data[2]] then
    check_groupcard(mime.unb64(data[7]), data[2], data[3])
    local msg = g2u:iconv(mime.unb64(data[4])):gsub('&#91;', '['):gsub('&#93;', ']'):gsub('&amp;', '&')
    if spamwords(msg, data[2], data[3]) then return end
    if reply(msg, data[2]) then return end
    linky(msg, data[2])
  end
end

local welcome_test = [[欢迎 cq_at 加入本群。请新人先阅读群置顶公告，并照公告要求修改群名片。如果访问或编辑维基百科有困难，请先参阅群文件里的内容。群文件里有维基百科相关的介绍文档，建议阅读。群公告里也有维基百科相关公告及视频教程，欢迎参考。如果有问题，请直接在群里提出。]]

function processNewMember(data)
  if enabled_groups[data[2]] then
    sendToServer('GroupMessage ' .. data[2] .. ' ' .. 
      mime.b64(u2g:iconv(welcome_test:gsub('cq_at', '[CQ:at,qq=' .. data[4] .. ']'))) .. ' 0')
  end
end

sendClientHello()

while true do
  local recvbuff, recvip, recvport = cqclient:receivefrom()
  if recvbuff then
    local data = recvbuff:split(' ')
    if data[1] == 'GroupMessage' then
      processGroupMsg(data)
    elseif data[1] == 'GroupMemberIncrease' then
      processNewMember(data)
    else
      -- print(recvbuff, recvip, recvport)
    end
  else
    wheel:step()
  end
end

cqserver:close()
