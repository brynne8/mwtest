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

  local continue_flag = bit.rshift(unicode, 6)
  local bytes = {}
  
  repeat
    bytes[#bytes + 1] = 0x80 + bit.band(unicode, 0x3F);
    unicode = bit.rshift(unicode, 6)
    
    continue_flag = bit.rshift(continue_flag, 5)
  until continue_flag == 0
  bytes[#bytes + 1] = 0xF0 + unicode;
  
  return char(unpack(table.reverse(bytes)))
end

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
  ['s'] = 'zh.wikisource.org',
  ['mirror'] = 'zh.wikipedia-mirror.org',
  ['en-mirror'] = 'en.wikipedia-mirror.org',
  ['ja-mirror'] = 'ja.wikipedia-mirror.org',
  ['zh-mirror'] = 'zh.wikipedia-mirror.org'
}

local iconv = require('iconv')
local g2u = iconv.new('utf-8', 'gb18030')
local u2g = iconv.new('gb18030', 'utf-8')

local cqserver = socket.udp()
cqserver:setpeername('127.0.0.1', '11235')

local cqclient = socket.udp()
cqclient:setsockname('127.0.0.1', '5678')
cqclient:settimeout(1)
print('Client started')

local feedserver = socket.udp()
feedserver:setpeername('127.0.0.1', '5680')

math.randomseed( tonumber(tostring(os.time()):reverse():sub(1,6)) )

local timer_id
local enabled_groups = { ['10000'] = true }

local is_working = true

function sendToServer(data)
  print(data)
  cqserver:send(data)
end

function sendClientHello()
  sendToServer('ClientHello 5678')
  print(os.date(), 'Memory count: ', collectgarbage("count"))
  timer_id = wheel:set(280, sendClientHello)
end

function linky(msg, group_id)
  msg = msg:gsub('%[CQ:emoji,id=(%d+)%]', function(m1)
    local code = tonumber(m1)
    if code then
      return utf8char(code)
    end
  end)
  local wikilink = msg:match('%[%[([^|%[%]]+)|?[^%[%]]-%]%]')
  if wikilink then
    local trans_key, trans_val = wikilink:match('^(.-):(.*)')
    local remote_url = transwiki[trans_key]
    if remote_url then
      local send_str = 'https://' .. remote_url .. '/wiki/' .. Utils.urlEncode(trans_val)
      if trans_key:match('mirror') then
        send_str = send_str .. '\n这个网址是维基百科的镜像网站。可以登陆编辑。请注意，请勿在其他不明来源' ..
                      '的镜像网站登录维基账号，否则账号可能被盗。'
      end
      sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv(send_str)) .. ' 0')
    else
      sendToServer('GroupMessage ' .. group_id .. ' ' ..
        mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/' .. Utils.urlEncode(wikilink))) .. ' 0')
    end
    return true
  end
  wikilink = msg:match('{{([^|}]*)|?[^}]-}}')
  if wikilink then
    sendToServer('GroupMessage ' .. group_id .. ' ' ..
      mime.b64(u2g:iconv('https://zh.wikipedia.org/wiki/Template:' .. Utils.urlEncode(wikilink))) .. ' 0')
    return true
  end
end

local spamlist = { '翻墙', '梯子' }

Utils.tableConcat(spamlist, extend_spamlist)

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

local ReplyDicts = require('mwtest/reply_dicts')
local replylist = ReplyDicts.replylist
local cmd_replylist = ReplyDicts.cmd_replylist
local newbie_reply = ReplyDicts.newbie_reply

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
  if not uinfo_str or dont_checkcard[group_id] then
    return
  end
  if uinfo_str:len() < 17 then
    print(group_id, qq_num, uinfo_str)
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
    else
      return ugroup, uname
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
  elseif op == 'shutdown' then
    is_working = false
    sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv('Viviane已停止处理消息')) .. ' 0')
  elseif op == 'startup' then
    is_working = true
    sendToServer('GroupMessage ' .. group_id .. ' ' .. mime.b64(u2g:iconv('Viviane已开始处理消息')) .. ' 0')
  end
end

function stripAt(msg)
  local at_qq, rest_msg = msg:match('^%[CQ:at,qq=(%d+)%] (.*)')
  if not at_qq then rest_msg = msg end
  return at_qq, rest_msg
end

local last_atme = 0
local last_feed = {}
for k in pairs(enabled_groups) do
  last_feed[k] = 0
end

function requestFeed(group_id, str)
  if os.time() - last_feed[group_id] > 60 then
    feedserver:send(str)
  else
    sendToServer('GroupMessage ' .. group_id .. ' ' ..
      mime.b64(u2g:iconv('条目推送功能每分钟只能用1次喔~')) .. ' 0')
  end
end

function processGroupMsg(data)
  if enabled_groups[data[2]] and data[3] ~= '1000000' then
    if checkBlacklist(data) then return end
    local ugroup, uname = check_groupcard(mime.unb64(data[7]), data[2], data[3])
    local msg = g2u:iconv(mime.unb64(data[4])):gsub('&#91;', '['):gsub('&#93;', ']'):gsub('&amp;', '&')
    -- operations
    local op, params_start = msg:match('^!(%a*)()')
    if op and op_admins[data[3]] then
      executeOp(data[2], op, msg:sub(params_start + 1))
    end
    if not is_working then return end

    if spamwords(msg, data[2], data[3]) then return end
    local at_qq, msg = stripAt(msg)
    local cmd = msg:match('^/(%w*)')
    if cmd then
      if cmd == 'info' or cmd == 'help' then
        local cmdlist = '当前可用所有命令有：\n'
        for k in pairs(cmd_replylist) do
          cmdlist = cmdlist .. '/' .. k .. ' '
        end
        sendToServer('GroupMessage ' .. data[2] .. ' ' .. mime.b64(u2g:iconv(cmdlist)) .. ' 0')
        return
      elseif cmd == 'newbie' then
        local r = math.random(#newbie_reply)
        sendToServer('GroupMessage ' .. data[2] .. ' ' .. mime.b64(u2g:iconv(newbie_reply[r])) .. ' 0')
        return
      elseif cmd == 'popular' then
        requestFeed(data[2], 'RandomPopularArticle ' .. data[2])
        return
      elseif cmd == 'science' then
        requestFeed(data[2], 'RandomScienceArticle ' .. data[2])
        return
      elseif cmd_replylist[cmd] then
        sendToServer('GroupMessage ' .. data[2] .. ' ' .. mime.b64(u2g:iconv(cmd_replylist[cmd])) .. ' 0')
        return
      end
    end
    if linky(msg, data[2]) then return end
    if (op ~= '') and reply(msg, data[2]) then return end
    if ugroup ~= 'User' and ugroup ~= '管-User' and os.time() - last_atme > 600 then
      if at_qq == '10000' then
        last_atme = os.time()
        sendToServer('GroupMessage ' .. data[2] .. ' ' ..
          mime.b64(u2g:iconv('我是群管机器人Viviane，我不是人工智能，不能聊天。[CQ:face,id=21]')) .. ' 0')
      end
    end
  end
end

local welcome_test = [[欢迎 cq_at 加入本群。请新人先阅读群置顶公告，并照公告要求修改群名片。如果访问或编辑维基百科有困难，请先参阅群文件里的内容。群文件里有维基百科相关的介绍文档，建议阅读。群公告里也有维基百科相关公告及视频教程，欢迎参考。如果有问题，请直接在群里提出。]]

function processNewMember(data)
  if enabled_groups[data[2]] then
    sendToServer('GroupMessage ' .. data[2] .. ' ' .. 
      mime.b64(u2g:iconv(welcome_test:gsub('cq_at', '[CQ:at,qq=' .. data[4] .. ']'))) .. ' 0')
  end
end

function processFeed(data)
  if data[3] == '1' then
    last_feed[data[2]] = os.time()
    sendToServer('GroupMessage ' .. data[2] .. ' ' ..
      mime.b64(u2g:iconv(data[5] .. (data[7] and ('（昨日浏览量：' .. data[7] .. '）') or '') ..
        '\n\n' .. data[6]:gsub('\255', ' ') .. '\n' ..
        'https://zh.wikipedia.org/wiki/' .. Utils.urlEncode(data[4]))) .. ' 0')
  else
    sendToServer('GroupMessage ' .. data[2] .. ' ' ..
      mime.b64(u2g:iconv('数据还没下载好呢，等下喔~')) .. ' 0')
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
    elseif data[1] == 'Feed' then
      processFeed(data)
    else
      -- print(recvbuff, recvip, recvport)
    end
  else
    wheel:step()
  end
end

cqserver:close()
