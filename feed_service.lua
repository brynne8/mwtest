--[[
Author: Alexander Misel
]]
local copas = require('copas')
local chttp = require('copas.http')
local limit = require("copas.limit")
local socket = require('socket')
local MediaWikiApi = require('mwtest/mwapi')
local Utils = require('mwtest/utils')
local json = require('cjson')

local lkserver = socket.udp()
lkserver:setpeername('127.0.0.1', '5678')

local lkclient = socket.udp()
lkclient:setsockname('127.0.0.1', '5680')
lkclient:settimeout(1)
print('Client started')

math.randomseed( tonumber(tostring(os.time()):reverse():sub(1,6)) )

function sendToServer(data)
  print(data)
  lkserver:send(data)
end

local spamlist = { '六四', '天安门', '暴动', '逃犯', '港独', '法轮', '近平', '泽民', '锦涛', 
  '岐山', '家宝', '文贵', '永康', '占领', '雨伞革命', '人权', '维权', '学运', '学潮', '社运',
  '庆红', '镕基', '洪志', '反送中', '蛤', '中华民国', '瓜瓜', '仲勋', '国锋', '光复', '割让', 
  '晓波', '克强', '韩正', '熙来', '紫阳', '耀邦', '明泽', '柴玲', '王丹', '民运', '主运', '反共',
  '吾尔开希', '艾未未', '会运', '出征', '新疆', '北戴河', '乌鲁木齐', '草榴', '防火长城', '丽媛',
  '普选', '封锁网站', '新唐人', '达赖', '刘鹤', '王沪宁' }

local content_black = { '六四', '学运', '学潮', '社运', '会运', '民运', '主运', '反共', '逃犯条例',
  '示威', '天安门', '异议', '持不同政见' }

local topview_data = {
  last_date = 0,
  list = nil,
  new_list = {} -- after a complete check would assign to list
}

local science_data = {
  last_date = 0,
  list = nil,
  new_list = {} -- after a complete check would assign to list
}

function list_match(list, str)
  for _, v in ipairs(list) do
    if str:match(v) then return true end
  end
  return false
end

function list_replace(list, str)
  for _, v in ipairs(list) do
    str = str:gsub(v, string.rep('*', math.ceil(v:len() / 3)))
  end
  return str
end

-- Copas Async Request
function chttpsget(req_url)
  MediaWikiApi.trace('CHTTP request')
  local res = {}
  local _, code, resheaders, _ = chttp.request {
    url = req_url,
    protocol = 'tlsv1_2',
    headers = {
      ['User-Agent'] = string.format('mediawikilua %d.%d', 0, 2),
      ['Accept-Language'] = 'zh-cn'
    },
    sink = ltn12.sink.table(res)
  }

  MediaWikiApi.trace('  Result status:', code)
  return table.concat(res), code, resheaders
end

function getSummary(art_name)
  local res, code = chttpsget('https://zh.wikipedia.org/api/rest_v1/page/summary/'
    .. art_name)
  if code == 200 then
    res = json.decode(res)
    return res.titles.display, res.extract and res.extract:gsub('\n*', '')
  end
end

function getTopView(new_date)
  print('Start fetching topviews')
  local old_last_date = topview_data.last_date
  local cur_datetime = os.date('*t', os.time() - 86400)
  local y = cur_datetime.year
  local m = cur_datetime.month < 10 and ('0' .. cur_datetime.month) or cur_datetime.month
  local d = cur_datetime.day
  topview_data.last_date = new_date
  local data_str = y .. '/' .. m .. '/' .. d
  
  local res, code = chttpsget('https://wikimedia.org/api/rest_v1/metrics/pageviews/top/' ..
    'zh.wikipedia.org/all-access/' .. data_str)
  if code ~= 200 then
    MediaWikiApi.trace('Failed to get topviews')
    topview_data.last_date = old_last_date
    return
  end
  
  local raw_topview = json.decode(res).items[1].articles
  local taskset = limit.new(10)
  for _, v in ipairs(raw_topview) do
    local art_name = v.article
    if not art_name:match(':') and not list_match(spamlist, art_name) then
      local id = #topview_data.new_list + 1
      topview_data.new_list[id] = { article = art_name, views = v.views }
      taskset:addthread(function()
        local disp_name, extract = getSummary(art_name)
        topview_data.new_list[id].disp_name = disp_name
        topview_data.new_list[id].extract = extract == '' and '无摘要' or extract
        if id % 10 == 0 then print(id) end
      end)
    end
  end
end

function randomPopularArt(data)
  if not topview_data.list then
    sendToServer('Feed ' .. data[2] .. ' 0')
  else
    local id = math.random(#topview_data.list)
    local item = topview_data.list[id]
    sendToServer('Feed ' .. data[2] .. ' 1 ' .. item.article .. ' ' .. item.disp_name:gsub(' ', '_') .. 
      ' ' .. item.extract:gsub(' ', '') .. ' ' .. item.views)
  end
end

function randomScienceArt(data)
  if not science_data.list then
    sendToServer('Feed ' .. data[2] .. ' 0')
  else
    local id = math.random(#science_data.list)
    local item = science_data.list[id]
    sendToServer('Feed ' .. data[2] .. ' 1 ' .. item.article .. ' ' .. item.disp_name:gsub(' ', '_') .. 
      ' ' .. item.extract:gsub(' ', '\255'))
  end
end

local pop_file = io.open("mwtest/pop.txt", "rb")
local pop_str = pop_file:read('*a')
if pop_str:len() > 100 then
  topview_data = json.decode(pop_str)
  print(#topview_data.list)
end
pop_file:close()

pop_file = io.open("mwtest/sci.txt", "rb")
pop_str = pop_file:read('*a')
if pop_str:len() > 100 then
  science_data = json.decode(pop_str)
  print(#science_data.list)
end
pop_file:close()

while true do
  local recvbuff, recvip, recvport = lkclient:receivefrom()
  if recvbuff then
    print(recvbuff)
    local data = recvbuff:split(' ')
    if data[1] == 'RandomPopularArticle' then
      randomPopularArt(data)
    elseif data[1] == 'RandomScienceArticle' then
      randomScienceArt(data)
    else
      -- print(recvbuff, recvip, recvport)
    end
  else
    local curdate = os.date('*t')
    if topview_data.last_date ~= curdate.day and curdate.hour >= 10 then
      copas.addthread(function ()
        getTopView(curdate.day)
      end)
    end
    if copas.finished() then
      local new_len = #topview_data.new_list
      if new_len ~= 0 then
        for i = new_len, 1, -1 do
          local v = topview_data.new_list[i]
          if v.disp_name and list_match(spamlist, v.disp_name) then
            table.remove(topview_data.new_list, i)
          elseif v.extract then
            if list_match(content_black, v.extract) then
              table.remove(topview_data.new_list, i)
            else
              v.extract = list_replace(spamlist, v.extract)
            end
          else
            table.remove(topview_data.new_list, i)
          end
        end
        topview_data.list = topview_data.new_list
        topview_data.new_list = {}
        local f = io.open("mwtest/pop.txt", "wb")
        f:write(json.encode(topview_data))
        f:close()
      end
    else
      copas.step()
    end
  end
end

lkserver:close()
