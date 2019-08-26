--[[
Author: Alexander Misel
]]
local copas = require('copas')
local chttp = require('copas.http')
local limit = require("copas.limit")
local MediaWikiApi = require('mwtest/mwapi')
local Utils = require('mwtest/utils')
local json = require('cjson')

local science_data = {
  last_date = 0,
  list = nil,
  new_list = {} -- after a complete check would assign to list
}

local science_dict = {}

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

function stripHtmlTags(extract)
  if not extract then return '' end
  local first_para = extract:match('<p>(.-)\n</p>')
  if not first_para then return '' end
  first_para = first_para:gsub('<span><span><math.-alttext="(.-)".-</span></span>', 
                function(p1)
                  return p1:gsub('%b{}', function (p2)
                    return p2:gsub('^{\\displaystyle (.-)}$', function (p3)
                      return '$' .. p3:gsub('^{(.*)}$', '%1') .. '$'
                    end)
                  end)
                end)
  first_para = first_para:gsub('%b<>', '')

  for uchar, end_pos in first_para:gmatch('([%z\1-\127\194-\244][\128-\191]*)()') do
    if uchar == '。' or uchar == '：' then
      if end_pos > 450 then
        first_para = first_para:sub(1, end_pos - 1)
        break
      end
    end
  end
  return first_para
end

function getSummary(titles)
  local res, code = chttpsget('https://zh.wikipedia.org/w/api.php?' ..
    MediaWikiApi.createRequestBody {
      action = 'query',
      prop = 'extracts|info',
      inprop = 'varianttitles',
      exintro = 1,
      titles = titles,
      format = 'json',
      formatversion = 2
    })
  if code == 200 then
    local pages =  json.decode(res).query.pages
    for _, v in ipairs(pages) do
      v.extract = stripHtmlTags(v.extract)
    end
    return pages
  end
end

local sci_cats = {
  '极高重要度数学条目', '高重要度数学条目', '中重要度数学条目',
  '极高重要度物理学条目', '高重要度物理学条目', '中重要度物理学条目',
  '极高重要度化学条目', '高重要度化学条目', '中重要度化学条目',
  '极高重要度生物学条目', '高重要度生物学条目', '中重要度生物学条目',
  '极高重要度医学条目', '高重要度医学条目', '中重要度医学条目',
  '极高重要度电脑和信息技术条目', '高重要度电脑和信息技术条目', '中重要度电脑和信息技术条目',
}

function getScienceArt()
  print('Start fetching science articles')
  local getCatMembers = function (cat, cmcontinue)
    local res, code = chttpsget('https://zh.wikipedia.org/w/api.php?action=query&format=json&list=categorymembers' ..
      '&cmlimit=500&cmtitle=Category:' .. cat .. (cmcontinue and ('&cmcontinue=' .. cmcontinue) or ''))
    if code ~= 200 then
      MediaWikiApi.trace('Failed to get science art')
      return
    end
    
    local raw_catmem = json.decode(res).query.categorymembers
    for _, v in ipairs(raw_catmem) do
      local art_name = v.title:match('Talk:(.-)$')
      if art_name then science_dict[art_name:gsub(' ', '_')] = true end
    end
    
    if res.continue then
      getCatMembers(cat, cmcontinue)
    end
  end

  for _, v in ipairs(sci_cats) do
    getCatMembers(v)
  end
end

copas.addthread(getScienceArt)
copas.loop()

local taskset = limit.new(10)
local titles = ''
local id = 0
for art_name in pairs(science_dict) do
  id = id + 1
  titles = titles .. '|' .. art_name
  if id % 20 == 0 then
    local temp_titles = titles:sub(2)
    taskset:addthread(function()
      local pages = getSummary(temp_titles)
      for _, v in ipairs(pages) do
        science_dict[v.title:gsub(' ', '_')] = {
          disp_name = v.varianttitles['zh-cn'],
          extract = v.extract == '' and '无摘要' or v.extract
        }
      end
    end)
    titles = ''
  end
end

copas.loop()

id = 0
for k, v in pairs(science_dict) do
  if type(v) ~= 'boolean' then
    id = id + 1
    science_data.new_list[id] = {
      article = k,
      disp_name = v.disp_name,
      extract = v.extract
    }
  end
end

science_data.list = science_data.new_list
science_data.new_list = {}
local f = io.open("mwtest/sci.txt", "wb")
f:write(json.encode(science_data))
f:close()
