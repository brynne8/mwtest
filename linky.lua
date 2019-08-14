--[[
Author: Alexander Misel
Dependencies:
* timerwheel: Pure Lua timerwheel implementation
* lua-iconv: Lua bindings for POSIX iconv
]]
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
  timer_id = wheel:set(280, sendClientHello)
end

local cqclient = socket.udp()
cqclient:setsockname('127.0.0.1', '5678')
cqclient:settimeout(1)
print('Client started')

local transwiki = {
  ['c'] = 'commons.wikimedia.org',
  ['commons'] = 'commons.wikimedia.org',
  ['en'] = 'en.wikipedia.org',
  ['d'] = 'www.wikidata.org',
  ['de'] = 'de.wikipedia.org',
  ['ja'] = 'ja.wikipedia.org',
  ['ko'] = 'ko.wikipedia.org',
  ['m'] = 'meta.wikimedia.org',
  ['q'] = 'zh.wikiquote.org',
  ['s'] = 'zh.wikisource.org'
}

function linky(msg, group_id)
  msg = msg:gsub('%[CQ:emoji,id=(%d+)%]', function(m1)
    local code = tonumber(m1)
    if code then
      return utf8char(code)
    end
  end)
  local wikilink = msg:match('%[%[(.-)%]%]')
  if wikilink then
    local trans_key, trans_val = wikilink:match('^(.-):(.*)')
    local remote_url = transwiki[trans_key]
    if remote_url then
      sendToServer('GroupMessage ' .. group_id .. ' ' ..
        mime.b64(u2g:iconv('https://' .. remote_url .. '/wiki/' .. Utils.urlEncode(trans_val))) .. ' 0')
    else
      sendToServer('GroupMessage ' .. group_id .. ' ' ..
        mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/' .. Utils.urlEncode(wikilink))) .. ' 0')
    end
    return true
  end
  wikilink = msg:match('{{([^|]*)|?.*}}')
  if wikilink then
    sendToServer('GroupMessage ' .. group_id .. ' ' ..
      mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/Template:' .. Utils.urlEncode(wikilink))) .. ' 0')
    return true
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

local bad_patterns = { '上维基娘', '百度.-词条', '词典.-词条' }

local replylist = {
  ['^表白vva$'] = '谢谢。'
}

function reply(msg, group_id)
  for _, v in ipairs(bad_patterns) do
    if msg:match(v) then return end
  end
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

local dont_checkcard = { ['308617666'] = true }

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
    local ugroup, uname = group_card:match('^(.-):%s*([^#]*[^#%s])')
    local pass = false
    if ugroup and uname ~= '' and
      (ugroup == 'User' or ugroup == '学习' or ugroup == 'Bot' or ugroup == '管-User') then
      if ugroup == 'User' then
        if not uname:match('[@:%(%)]') and not (uname:match('^%d*$')) and
          not (uname:match('[\228-\233][\128-\191][\128-\191]') and uname:match('%a')) then
          pass = true
        end
      else
        pass = true
      end
    end
    if not pass then
      sendToServer('GroupMessage ' .. group_id .. ' ' .. 
        mime.b64(u2g:iconv('[CQ:at,qq=' .. qq_num .. '] 您的群名片不符合规定，请按群公告要求修改群名片')) .. ' 0')
    end
  end
end

local op_admins = { ['10000'] = true }
local blacklist = {}
local bl_string = ''

function setBlacklist(op, qq_num)
  if op == 'add' then
    blacklist[qq_num] = true
    bl_string = bl_string .. qq_num .. '\n'
    local f = io.open("mwtest/bl.txt", "a")
    f:write(qq_num .. '\n')
    f:close()
  elseif op == 'remove' then
    blacklist[qq_num] = nil
    bl_string = bl_string:gsub(qq_num .. '\n', '', 1)
    local f = io.open("mwtest/bl.txt", "w")
    f:write(bl_string)
    f:close()
  else
    error('op is not specified')
  end
end

function checkBlacklist(data)
  if blacklist[data[3]] then
    if data[1] == 'RequestAddGroup' then
      sendToServer('GroupAddRequest ' .. data[5] .. ' 1 2' .. mime.b64(u2g:iconv('黑名单成员自动拒绝')))
    elseif data[1] == 'GroupMessage' then
      sendToServer('GroupKick ' .. data[2] .. ' ' .. data[3] .. ' 0')
    end
    return true
  end
end

function executeOp(group_id, op, params)
  if op == 'b' or op == 'block' then
    sendToServer('GroupKick ' .. group_id .. ' ' .. params .. ' 0')
    setBlacklist('add', params)
    sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv(params .. '已加入黑名单')) .. ' 0')
  elseif op == 'ub' or op == 'unblock' then
    setBlacklist('remove', params)
    sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv(params .. '已移除黑名单')) .. ' 0')
  end
end

function processGroupMsg(data)
  if enabled_groups[data[2]] and data[3] ~= '1000000' then
    if checkBlacklist(data) then return end
    check_groupcard(mime.unb64(data[7]), data[2], data[3])
    local msg = g2u:iconv(mime.unb64(data[4])):gsub('&#91;', '['):gsub('&#93;', ']'):gsub('&amp;', '&')
    -- operations
    local op, params = msg:match('^!(.-) (.*)$')
    if op and op_admins[data[3]] then
      executeOp(data[2], op, params)
    end
    
    if spamwords(msg, data[2], data[3]) then return end
    if linky(msg, data[2]) then return end
    if op ~= '' and reply(msg, data[2]) then return end
  end
end

local welcome_test = [[欢迎 cq_at 加入本群。请新人先阅读群置顶公告，并照公告要求修改群名片。如果访问或编辑维基百科有困难，请先参阅群文件里的内容。群文件里有维基百科相关的介绍文档，建议阅读。群公告里也有维基百科相关公告及视频教程，欢迎参考。如果有问题，请直接在群里提出。]]

function processNewMember(data)
  if enabled_groups[data[2]] then
    sendToServer('GroupMessage ' .. data[2] .. ' ' .. 
      mime.b64(u2g:iconv(welcome_test:gsub('cq_at', '[CQ:at,qq=' .. data[4] .. ']'))) .. ' 0')
  end
end

-- Main Loop
local bl_file = io.open("mwtest/bl.txt", "r")
for line in bl_file:lines() do
  blacklist[line] = true
end
bl_file:seek('set')
bl_string = bl_file:read('*a')
bl_file:close()

sendClientHello()

while true do
  local recvbuff, recvip, recvport = cqclient:receivefrom()
  if recvbuff then
    local data = recvbuff:split(' ')
    if data[1] == 'GroupMessage' then
      processGroupMsg(data)
    elseif data[1] == 'GroupMemberIncrease' then
      processNewMember(data)
    elseif data[1] == 'RequestAddGroup' then
      checkBlacklist(data)
    else
      -- print(recvbuff, recvip, recvport)
    end
  else
    wheel:step()
  end
end

cqserver:close()
