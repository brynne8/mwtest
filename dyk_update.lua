--[[
Author: Alexander Misel
Original python code: https://github.com/liangent/updatedyk/blob/master/updatedyk.py
]]
local MediaWikiApi = require('mwtest/mwapi')
local socket = require('socket')
local sha1 = require('sha1')

function getTime (iso8601)
  local y, m, d, H, M, S = iso8601:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  return os.time{ year = y, month = m, day = d, hour = H, min = M, sec = S } + 28800
end

function hasValue (tab, val)
  if not tab then
    return false
  end
  for _, value in ipairs(tab) do
    if value == val then return true end
  end
  return false
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

function normalizeTpl(tpl_str)
  local template = {}
  for line in tpl_str:gmatch('[^\n]+') do
    local attr, value = line:match('^ *| *(%w+) *= *(.-) *$')
    if attr then
      template[attr] = value
    end
  end
  return template
end

function generateTpl(template, ordering)
  local tpl_str = ''
  if ordering then
    for _, v in ipairs(ordering) do
      tpl_str = tpl_str .. '\n | ' .. v .. ' = ' .. (template[v] or '')
    end
  else
    for k, v in pairs(template) do
      tpl_str = tpl_str .. '\n | ' .. k .. ' = ' .. (v or '')
    end
  end
  return tpl_str
end

function processDykEntry(content)
  local start, tpl_str, final = content:match('{{ ?Dyk/auto()(.-)()\n}}')
  local dyk_tpl = normalizeTpl(tpl_str)
  local entries = {}
  local questions = {}
  for i = 1, 6 do
    local question = dyk_tpl[tostring(i-1)]
    table.insert(entries, {
      question = question,
      image = dyk_tpl['p' .. (i-1)],
      type = dyk_tpl['t' .. (i-1)]
    })
    questions[question] = true
  end
  return entries, questions, start, final
end

function updateDyk(entries, content, start, final)
  local new_entries = {}
  
  for i = 1, 6 do
    new_entries[tostring(i-1)] = entries[i].question
    new_entries['p' .. (i-1)] = entries[i].image
    new_entries['t' .. (i-1)] = entries[i].type
  end
  
  new_entries.allimages = '{{{allimages|no}}}'
  
  local tpl_order = { '0', 'p0', 't0', '1', 'p1', 't1', '2', 'p2', 't2', 
    '3', 'p3', 't3', '4', 'p4', 't4', '5', 'p5', 't5', 'allimages' }
  return content:sub(1, start-1) .. generateTpl(new_entries, tpl_order) .. content:sub(final)
end

function processDykcEntry(entry_str)
  local entry = normalizeTpl(entry_str)

  if not entry.hash then
    return sha1.sha1(entry.question), entry.timestamp
  end
  if not entry.result then
    return nil, entry.timestamp
  end
  local result, timestamp = entry.result:match('^(.-)|.-|(.-)$')
  if timestamp == '0' then
    return nil, entry.timestamp
  end

  if result and timestamp then
    local jsonres = MediaWikiApi.performRequest {
      action = 'query',
      prop = 'revisions',
      titles = 'Wikipedia:新条目推荐/候选',
      rvlimit = 1,
      rvprop = 'user|comment',
      rvdir = 'newer',
      rvstart = timestamp - 1,
      rvend = timestamp,
      format = 'json',
      formatversion = 2
    }
    if not jsonres.query.pages[1].revisions then
      MediaWikiApi.trace('Bad timestamp!')
      return nil, entry.timestamp
    end
    local user = jsonres.query.pages[1].revisions[1].user
    
    -- closed by admin
    jsonres = MediaWikiApi.performRequest {
      action = 'query',
      list = 'users',
      ususers = user,
      usprop = 'groups',
      format = 'json'
    }
    if not hasValue(jsonres.query.users[1].groups, 'sysop') then
      MediaWikiApi.trace('User:' .. user .. ' doesn\'t have sysop access!')
      return nil, entry.timestamp
    end
    
    if result == '+' or result == '*' then
      return true, entry
    else
      return false, entry
    end
  else
    return nil, entry.timestamp
  end
end

function updateTalkPage(article, id, dykc_tpl, dykc_tail, failed)
  local talk_title = 'Talk:' .. article
  local talk_page = MediaWikiApi.getCurrent(talk_title)
  talkpage_cont = talk_page and talk_page.content or ''
  talkpage_cont = talkpage_cont:gsub('{{ ?DYK ?[Ii]nvite%s-}}\n?', '')
  local talk_new = failed and '' or os.date('!{{DYKtalk|%Y年|%m月%d日}}\n'):gsub('0(%d[月日])', '%1')
  if #talkpage_cont then
    talk_new = talk_new .. talkpage_cont
  end
  
  local additional_params = { revid = id, closets = '{{subst:#time:U}}' }
  if failed then
    additional_params.rejected = 'rejected'
  end
  talk_new = talk_new .. ('\n\n{{ DYKEntry/archive' .. dykc_tpl ..
    generateTpl(additional_params) .. '\n}}' .. dykc_tail)
  MediaWikiApi.edit(talk_title, talk_new)
end

function concatTimedEntries(new_list)
  local result_str = ''
  for k, v in ipairs(new_list) do
    if v.timestamp then
      if k == 1 then
        result_str = result_str .. os.date('!\n=== %m月%d日 ===', v.timestamp):gsub('0(%d[月日])', '%1')
      elseif new_list[k-1].timestamp then
        if os.date('!%d', new_list[k-1].timestamp) ~= os.date('!%d', v.timestamp) then
          result_str = result_str .. os.date('!\n=== %m月%d日 ===', v.timestamp):gsub('0(%d[月日])', '%1')
        end
      end
    end
    result_str = result_str .. '\n==== ====' .. v.entry
  end
  return result_str
end

function hashRemoval(hash_dict)
  MediaWikiApi.base_time = os.time()

  local dykc_page = MediaWikiApi.getCurrent('Wikipedia:新条目推荐/候选')
  local dykc_list = dykc_page.content:split('\n{{ ?DYKEntry')
  local dykc_head = table.remove(dykc_list, 1):gsub('\n=[^\n]-月[^\n]-日[^\n]-=\n', '\n'):gsub('\n=[^\n]+=%s-$', '')
  for k = 1, #dykc_list do
    dykc_list[k] = '\n{{ DYKEntry' .. dykc_list[k]
  end
  local dykc_final = table.remove(dykc_list)
  local new_dykc_list = {}
  
  for i = 1, #dykc_list do
    local clear_entry = dykc_list[i]
    local dykc_tpl, dykc_tail = clear_entry:match('^\n{{ DYKEntry(.-)\n}}(.*)$')
    if i == #dykc_list then
        local newsec = dykc_tail:match('\n=[^\n]+=%s-$')
        dykc_final = (newsec or '') .. dykc_final
      end
    old_tail_len = #dykc_tail
    dykc_tail = dykc_tail:gsub('\n=.+=%s-$', '')
    dykc_list[i] = dykc_list[i]:sub(1, #dykc_list[i] - old_tail_len) .. dykc_tail

    local parsedEntry = normalizeTpl(dykc_tpl)
    if not (parsedEntry.hash and hash_dict[parsedEntry.hash]) then
      table.insert(new_dykc_list, {
        entry = dykc_list[i],
        timestamp = tonumber(parsedEntry.timestamp)
      })
    end
  end
  
  if not pcall(function ()
    MediaWikiApi.edit('Wikipedia:新条目推荐/候选', dykc_head .. concatTimedEntries(new_dykc_list) .. dykc_final)
  end) then
    MediaWikiApi.trace('Save failed. Try again...')
    hashRemoval(remove_hash)
  end
end

function mainTask()
  MediaWikiApi.base_time = os.time()

  local dykc_page = MediaWikiApi.getCurrent('Wikipedia:新条目推荐/候选')
  local dyk = MediaWikiApi.getCurrent('Template:Dyk')
  local archive_title = 'Wikipedia:新条目推荐/' .. os.date('!%Y年%m月'):gsub('0(%d[月日])', '%1')
  local archive = MediaWikiApi.getCurrent(archive_title)
  if not archive then
    MediaWikiApi.edit(archive_title, '{{DYKMonthlyArchive}}')
  end

  local dykc_list = dykc_page.content:split('\n{{ ?DYKEntry')
  local dykc_head = table.remove(dykc_list, 1):gsub('\n=[^\n]-月[^\n]-日[^\n]-=\n', '\n'):gsub('\n=[^\n]+=%s-$', '')
  for k = 1, #dykc_list do
    dykc_list[k] = '\n{{ DYKEntry' .. dykc_list[k]
  end
  local dykc_final = table.remove(dykc_list)

  local delta_hours = 8
  if #dykc_list > 16 then
    delta_hours = 2
  elseif #dykc_list > 12 then
    delta_hours = 4
  elseif #dykc_list > 6 then
    delta_hours = 6
  end

  local recent_time = getTime(dyk.timestamp)

  if os.difftime(os.time(), recent_time) > delta_hours * 3600 then
    local new_dykc_list = {}

    local dyk_cont = dyk.content
    local dyk_entries, dyk_ques, dyk_start, dyk_end = processDykEntry(dyk_cont)
    
    local remove_hash = {}
    
    for i = #dykc_list, 1, -1 do
      local dykc_tpl, dykc_tail = dykc_list[i]:match('^\n{{ DYKEntry(.-)\n}}(.*)$')
      if i == #dykc_list then
        local newsec = dykc_tail:match('\n=[^\n]+=%s-$')
        dykc_final = (newsec or '') .. dykc_final
      end
      old_tail_len = #dykc_tail
      dykc_tail = dykc_tail:gsub('\n=.+=%s-$', '')
      dykc_list[i] = dykc_list[i]:sub(1, #dykc_list[i] - old_tail_len) .. dykc_tail
      
      local res, parsedEntry = processDykcEntry(dykc_tpl)
      if res == true and #dyk_entries < 12 then
        if not dyk_ques[parsedEntry.question] then
          table.insert(dyk_entries, 1, parsedEntry)
        end
        MediaWikiApi.trace('Archiving ' .. parsedEntry.article)
        MediaWikiApi.editPend('Wikipedia:新条目推荐/存档/' .. os.date('!%Y年%m月'):gsub('0(%d[月日])', '%1'),
                              '* ' .. parsedEntry.question .. '\n', nil, true)
        MediaWikiApi.editPend('Wikipedia:新条目推荐/供稿/' .. os.date('!%Y年%m月%d日'):gsub('0(%d[月日])', '%1'),
                              '* ' .. parsedEntry.question .. '\n', nil, true)
        MediaWikiApi.editPend('Wikipedia:新条目推荐/分类存档/未分类', ' [[' .. parsedEntry.article .. ']]') -- append
        -- purge mainpage?
        MediaWikiApi.trace('Archive talk page of ' .. parsedEntry.article)
        updateTalkPage(parsedEntry.article, dykc_page.revid, dykc_tpl, dykc_tail)
        remove_hash[parsedEntry.hash] = true
      elseif res == false then
        MediaWikiApi.trace('Archive failed candidate ' .. parsedEntry.article)
        MediaWikiApi.editPend('Wikipedia:新条目推荐/未通过/' .. os.date('!%Y年'), '\n* ' .. parsedEntry.question) -- append
        MediaWikiApi.trace('Archive talk page of ' .. parsedEntry.article)
        artpage = MediaWikiApi.getCurrent(parsedEntry.article)
        if artpage then
          updateTalkPage(parsedEntry.article, dykc_page.revid, dykc_tpl, dykc_tail, true)
        else -- when article is deleted
          local additional_params = { revid = dykc_page.revid, closets = '{{subst:#time:U}}', rejected = 'rejected' }
          local talk_new = '\n\n{{ DYKEntry/archive' .. dykc_tpl .. generateTpl(additional_params) .. '\n}}'
          MediaWikiApi.editPend('Wikipedia talk:新条目推荐/未通过/' .. os.date('!%Y年'), talk_new) -- append
        end
        remove_hash[parsedEntry.hash] = true
      else
        local temp_content = dykc_list[i]
        local timestamp = tonumber(parsedEntry)
        if res then
          if res == true then
            timestamp = tonumber(parsedEntry.timestamp)
          else
            temp_content = temp_content:gsub('\n}}', generateTpl({ hash = res, result = '' }, { 'hash', 'result' }) .. '\n}}', 1)
          end
        end
        table.insert(new_dykc_list, 1, {
          entry = temp_content,
          timestamp = timestamp
        })
      end
    end
    MediaWikiApi.trace('Updating DYK page')
    MediaWikiApi.edit('Template:Dyk', updateDyk(dyk_entries, dyk_cont, dyk_start, dyk_end))
    
    MediaWikiApi.trace('Updating DYKC page')
    if not pcall(function ()
      MediaWikiApi.edit('Wikipedia:新条目推荐/候选', dykc_head .. concatTimedEntries(new_dykc_list) .. dykc_final)
    end) then
      MediaWikiApi.trace('Save failed. Try again...')
      hashRemoval(remove_hash)
    end
  end
end

function runner()
  pcall(mainTask)
  MediaWikiApi.edit_token = nil
  MediaWikiApi.trace('Sleep one hour')
  socket.sleep(3600)
  runner()
end

-- MediaWikiApi.login('username', 'password')
-- runner()
mainTask()
