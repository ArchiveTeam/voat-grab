dofile("table_show.lua")
dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered_external = {}
local discovered = {}

if urlparse == nil or http == nil then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local discovered = {}
local ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(urlparse.unescape(url), "[<>\\%*%$%^%[%],%(%){}]")
    or string.match(url, "^https?://voat%.co/Account/Login")
    or string.match(url, "^https?://voat%.coimages/") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://cdn%.voat%.co/") then
    return true
  end

  if not string.match(url, "^https?://[^/]*voat%.co") then
    discovered_external[url] = true
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if ids[s] then
      return true
    end
  end

  local match = string.match(url, "^https?://[^/]*voat%.co/u/([^/%?&]+)")
  if match then
    discovered["user:" .. match] = true
  else
    local match = string.match(url, "^https?://[^/]*voat%.co/v/([^/%?&]+)")
    if match then
      discovered["subverse:" .. match] = true
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.match(url, "^(.-)%.?$")
    url_ = string.gsub(url_, "&amp;", "&")
    url_ = string.match(url_, "^(.-)%s*$")
    url_ = string.match(url_, "^(.-)%??$")
    url_ = string.match(url_, "^(.-)&?$")
    url_ = string.match(url_, "^(.-)/?$")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "\\[uU]002[fF]") then
      return checknewurl(string.gsub(newurl, "\\[uU]002[fF]", "/"))
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, "/" .. newurl))
    end
  end

  local function eval_sum(s)
    if string.match(s, '%+') then
      total = 0
      for i in string.gmatch(s, "([0-9]+)") do
        total = total + tonumber(i)
      end
      return tostring(total)
    end
    return s
  end

  if string.match(url, "^https?://voat%.co/v/[^/]+/[0-9]+/[0-9]+$") then
    check(string.match(url, "^(.+)/[0-9]+$"))
  end

  if allowed(url, nil) and status_code == 200
    and not string.match(url, "^https?://cdn%.voat%.co/") then
    html = read_file(file)
    for submissionId, parentId, command, startingIndex, sort
      in string.gmatch(html, "javascript:loadMoreComments%([^,]+,%s*[^,]+,%s*([^%),]+),%s*([^%),]+),%s*([^%),]+),%s*([^%),]+),%s*([^%),]+)%)") do
      print('found', submissionId, parentId, command, startingIndex, sort)
      sort = string.match(sort, "^'(.-)'$")
      command = string.match(command, "^'(.-)'$")
      submissionId = eval_sum(submissionId)
      parentId = eval_sum(parentId)
      startingIndex = eval_sum(startingIndex)
      local newurl = "/comments/" .. submissionId .. "/" ..parentId .. "/" .. command .. "/" .. startingIndex .. "/" .. sort
      checknewurl(newurl)
    end
    for submissionID, sort in string.gmatch(html, "javascript:getCommentTree%(([^%),]+),%s*([^%),]+)%)") do
      print('found', submissionID, sort)
      submissionID = eval_sum(submissionID)
      sort = string.match(sort, "^'(.-)'$")
      local newurl = "/comments/" .. submissionID .. "/tree/" .. sort
      checknewurl(newurl)
    end
    if string.match(html, '<h3 class="panel%-title">Whoops!</h3>') then
      io.stdout:write("Got bad data from voat.\n")
      io.stdout:flush()
      abortgrab = true
    end
    if string.match(html, '<div id="no%-comments" class="alert%-notice">No comments o_O</div>') then
      io.stdout:write("No comments found, skipping for now.\n")
      io.stdout:flush()
      abortgrab = true
    end
    if string.match(html, '<h1 class="red">Warning!</h1>') then
      io.stdout:write("18+ cookie not working.\n")
      io.stdout:flush()
      abortgrab = true
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  local match = string.match(url["url"], "^https?://voat%.co/comments/([0-9]+)/tree/Top$")
  if match then
    ids[match] = true
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if string.match(newloc, "inactive%.min")
      or string.match(newloc, "ReturnUrl")
      or string.match(newloc, "adultcontent") then
      io.stdout:write("Found invalid redirect.\n")
      io.stdout:flush()
      abortgrab = true
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    io.stdout:flush()
    return wget.actions.ABORT
  end

  if status_code == 0
    or (status_code > 400 and status_code ~= 404) then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 12
    if not allowed(url["url"], nil) then
      maxtries = 3
    end
    if tries >= maxtries then
      io.stdout:write("I give up...\n")
      io.stdout:flush()
      tries = 0
      if maxtries == 3 then
        return wget.actions.EXIT
      else
        return wget.actions.ABORT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end


wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local discos = {
    ["voat-yyt0otkvbba1wzk"]=discovered,
    ["urls-voat2xf2bckik45"]=discovered_external
  }
  for k, d in pairs(discos) do
    local items = nil
    for item, _ in pairs(d) do
      print('found item', item)
      if items == nil then
        items = item
      else
        items = items .. "\0" .. item
      end
    end

    if items ~= nil then
      local tries = 0
      while tries < 10 do
        local body, code, headers, status = http.request(
          "http://blackbird-amqp.meo.ws:23038/" .. k .. "/",
          items
        )
        if code == 200 or code == 409 then
          break
        end
        os.execute("sleep " .. math.floor(math.pow(2, tries)))
        tries = tries + 1
      end
      if tries == 10 then
        abortgrab = true
      end
    end
  end
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

