LanzouyunAPI = {}
LanzouyunAPI.__index = LanzouyunAPI

local cjson = require("cjson")
local http = require("http")
local ltn12 = require("ltn12")
local socket = require("socket")
local Http = luajava.bindClass("com.androlua.Http")
local URLEncoder = luajava.bindClass("java.net.URLEncoder")
import "org.jsoup.*"


-- 建立对象LanzouyunAPI
function LanzouyunAPI:new()
  local self = setmetatable({}, LanzouyunAPI)
  -- 基础类
  self.Http = Http
  self.http = http
  self.cjson = cjson
  self.socket = socket
  self.URLEncoder = URLEncoder

  -- 缓存控制，未实现
  self.use_cache = true -- 默认开启
  self.cache_duration = 600 -- 单位秒
  self.clear_cache = true -- 默认清除

  -- 基础参数
  self.host = "https://fxjd.lanzn.com/"
  self.wd = ""
  self.url = ""
  self.uid = ""
  self.pwd = ""
  self.mode = "ipad"
  self.auto = true
  self.page = 1
  self.document = ""

  -- 临时使用
  self.headers = {}
  self.info = {}
  self.appdata = {}
  self.searchdata = {}
  return self
end

-- 提取链接id
function LanzouyunAPI:UID()
  local id = self.url:match("%.com/(.+)") or self.url
  self.uid = id
  return id
end

-- 初始化函数，设置默认值和headers
function LanzouyunAPI:init()
  self.headers = {
    ['Referer'] = self.host,
    ['User-Agent'] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
    ['Accept'] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    ['Accept-Encoding'] = "utf8, deflate, br",
    ['Accept-Language'] = "zh-CN,zh;q=0.9",
    ['Cache-Control'] = "max-age=0",
    ['Connection'] = "keep-alive",
    ['sec-ch-ua'] = '" Not;A Brand";v="99", "Chromium";v="90", "Google Chrome";v="90"'
  }
  -- 返回self以便链式调用
  return self
end

-- 状态码定义规范
function LanzouyunAPI:codes()
  local status_codes = {
    SUCCESS = 200, -- 请求成功
    FOLDER_SUCCESS = 201, -- 文件夹获取成功
    LINK_SUCCESS = 202, -- 获取直链接成功
    REQUEST_TOO_FREQUENT = 400, -- 请求过于频繁或者需要密码
    PASSWORD_REQUIRED = 400, -- 密码需要
    NO_SEARCH_CONTENT = 401, -- 没有设置搜索内容
    LINK_FETCH_FAILED = 402, -- 获取直链接失败
    REQUEST_FAILED = 403, -- 请求失败，状态码:xx
    RESOURCE_NOT_FOUND = 404 -- 找不到资源
  }
  return status_codes
end

-- 设置User-Agent的函数，根据设备类型返回不同的User-Agent
function LanzouyunAPI:UserAgent(deviceType)
  local userAgentTemplate
  local releases = {"8.0", "8.1", "9", "10", "11", "12", "13", "14"}
  local Build = luajava.bindClass "android.os.Build"

  if deviceType == "mobile" then
    -- 移动设备UA模板
    local models = {
      "SM-N975F", "NX712J", "GE2AE", "V2218A", "NOP-AN00", "PGT-AN10",
      "V2266A", "2203121C", "MNA-AL00", "M2012K11AC", "2210132G", "NOP-AN00"
    }
    local webVer = luajava.bindClass("android.webkit.WebView").getCurrentWebViewPackage().versionName
    userAgentTemplate = string.format(
    "Mozilla/5.0 (Linux; Android %s; %s Build/%s) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s Mobile Safari/537.36",
    releases[math.random(#releases)], models[math.random(#models)], Build.ID, webVer
    )
   elseif deviceType == "ipad" then
    -- iPad UA模板
    userAgentTemplate = "Mozilla/5.0 (iPad; U; CPU OS 6_0 like Mac OS X; zh-CN; iPad2)"
   else
    -- 桌面设备UA模板
    local operatingSystems = {
      'Windows NT 10.0; Win64; x64', 'Macintosh; Intel Mac OS X 10_15_7', 'X11; Linux x86_64'
    }
    local browsers = {
      {name = 'Chrome', versions = {'113.0.0.0', '112.0.0.0'}},
      {name = 'Firefox', versions = {'86.0', '85.0.1'}}
    }
    local os = operatingSystems[math.random(#operatingSystems)]
    local browser = browsers[math.random(#browsers)]
    local browserVersion = browser.versions[math.random(#browser.versions)]
    userAgentTemplate = string.format(
    "Mozilla/5.0 (%s) AppleWebKit/537.36 (KHTML, like Gecko) %s/%s Safari/537.36",
    os, browser.name, browserVersion
    )
  end
  return userAgentTemplate
end


-- 生成签名key的函数，用于请求参数
function LanzouyunAPI:signkey(section)
  local params = {
    "pg="..tostring(self.page),
    "vip=0",
    "webfoldersign=",
    "pwd=" .. self.pwd
  }

  -- 列出所有需要匹配的键，动态生成上述参数
  local keys = {"lx", "fid", "uid", "rep", "up"}
  for _, key in ipairs(keys) do
    local pattern = string.format([['%s':(.-),]], key)
    local match = section:match(pattern) or ""
    table.insert(params, key .. "=" .. match)
  end

  -- 特殊处理t和k
  local t_key = section:match([['t':(.-),]])
  local k_key = section:match([['k':(.-),]])
  local t_match = t_key and section:match(t_key .. [[ = '(.-)';]]) or ""
  local k_match = k_key and section:match(k_key .. [[ = '(.-)';]]) or ""

  table.insert(params, "t=" .. t_match)
  table.insert(params, "k=" .. k_match)

  return table.concat(params, "&")
end

-- 生成签名sing的函数，用于请求参数
function LanzouyunAPI:sign(section)
  local params = {"wd=" .. self.wd}

  -- 直接匹配 'sign':'key' 的模式并生成参数
  local pattern = "'sign':'(.-)'"
  local match = section:match(pattern) or ""
  table.insert(params, "sign=" .. match)

  return table.concat(params, "&")
end

-- 提取属性函数
function LanzouyunAPI:extractAttribute(element, selector, attrName)
  local selectedElement = element.select(selector).first()
  return selectedElement and selectedElement.attr(attrName) or nil
end

-- 提取文本函数
function LanzouyunAPI:extractText(element, selector)
  local selectedElement = element.select(selector).first()
  return selectedElement and selectedElement.text() or nil
end

-- 更通用的提取文本方法
function LanzouyunAPI:findFirstText(selectors)
  for _, selector in ipairs(selectors) do
    local text = self:extractText(self.document, selector)
    if text then
      return text
    end
  end
  return ""
end

-- 获取文件夹信息，包括文件列表和文件夹列表
function LanzouyunAPI:folder()
  if self.appdata.info == "sucess" then
    local info = self.info
    info.folder = {}
    info.list = {}
    info.name = self:findFirstText({"title", "div.b", "div.user-title", "div.b div"})
    info.desc = self:findFirstText({"span:contains(说)", "span#filename", "div.user-radio"})

    local folders = self.document.select("#folder div.mbx.mbxfolder")
    if folders and folders.size() > 0 then
      for i = 0, folders.size() - 1 do
        local folder = folders.get(i)
        local folderInfo = {
          id = self:extractAttribute(folder, "a[href]", "href"),
          name = self:extractText(folder, "div.filename"),
          desc = self:extractText(folder, "div.filesize")
        }
        table.insert(info.folder, folderInfo)
      end
    end

    local list = info.list
    for _, item in ipairs(self.appdata.text) do
      table.insert(list, {
        id = item.id,
        ico = item.ico,
        icon = item.icon,
        p_ico = item.p_ico,
        name = item.name_all,
        size = item.size,
        time = item.time
      })
    end
    info.have_page = #self.appdata.text >= 50
    return self:response(self:codes()["FOLDER_SUCCESS"], "文件夹", self.info)
   else
    return self:response(self:codes()["PASSWORD_REQUIRED"], "错误:请求过于频繁或者需要密码", self.info)
  end
end

-- 定义构造局部函数
local function handleRequest(self,requestUrl,postdata,Extends,callback)
  self:request(requestUrl, "post", postdata, function(code, data)
    self.appdata = data
    local success = (self.appdata.info == "sucess")
    if not success then
      if callback then
        callback(Extends)
      end
     else
      if callback then
        callback(self:folder())
      end
    end
  end)
end

-- 定义构造局部函数
local function processRequest(self,url,requestUrl,Extends)
  local code, data = self:request(url, "get")
  local postdata = self:signkey(data)
  local delay = (self.auto and self.page == 1) and 0 or ((not self.auto) and 0 or (self.page * 1000))
  if delay > 0 then
    self.socket.sleep(delay/1000)
  end
  local code, data = self:request(requestUrl, "post", postdata)
  self.appdata = data
  local success = (self.appdata.info == "sucess")
  if not success then
    return Extends
   else
    return self:folder()
  end
end

-- 处理移动端请求，包括获取文件夹信息
function LanzouyunAPI:mobile(callback)
  self.headers['User-Agent'] = self:UserAgent("ipad") -- 比较稳定
  local url = self.host .. self.uid
  local requestUrl = self.host .. "filemoreajax.php"

  if callback then
    self:request(url, "get", nil, function(code, data)
      local postdata = self:signkey(data)
      local delay = (self.auto and self.page == 1) and 0 or ((not self.auto) and 0 or (self.page * 1000))
      if delay > 0 then
        task(delay,function()
          handleRequest(self,requestUrl,postdata,self:mobile_fileInfo(),callback)
        end)
       else
        handleRequest(self,requestUrl,postdata,self:mobile_fileInfo(),callback)
      end
    end)
   else
    return processRequest(self,url,requestUrl,self:mobile_fileInfo())
  end
end

-- 获取移动端文件的详细信息
function LanzouyunAPI:mobile_fileInfo()
  local info = self.info
  local str = {}
  -- 获取meta description内容
  local metaDescription = self.document.select("meta[name=description]").first()
  if metaDescription then
    str.fileinfo = metaDescription.attr("content") or ""
   else
    str.fileinfo = ""
  end

  -- 获取文件名
  local title = self.document.select("title").first()
  local appname = self.document.select(".appname").first()
  if appname then
    info.name = appname.text() or ""
   elseif title then
    info.name = title.text()
  end

  -- 正则表达式匹配获取
  local data = tostring(self.document)
  -- 获取文件大小
  local filesize = {}
  if string.find(str.fileinfo, '文件大小：(.-)|') then
    filesize = {string.match(str.fileinfo, '文件大小：(.-)|')}
    info.size = filesize[1]
  end

  -- 获取分享者
  local username = {}
  if string.find(data, '分享者:</span>(.-) ') then
    username = {string.match(data, '分享者:</span>(.-) ')}
    info.user = username[1]
   else
    local userNameElement = self.document.select(".user-name").first()
    if userNameElement then
      info.user = userNameElement.text() or nil
    end
  end

  -- 获取上传时间
  local filetime = {}
  if string.find(data, '<span class="mt2"></span>(.-)<span class="mt2">') then
    filetime = {string.match(data, '<span class="mt2"></span>(.-)<span class="mt2">')}
    info.time = filetime[1] and string.gsub(filetime[1], "^%s*(.-)%s*$", "%1") or nil
   else
    local timeElement = self.document.select(".appinfotime").first()
    if timeElement then
      info.time = timeElement.text() or nil
    end
  end

  -- 获取文件描述
  local filedesc = {}
  if string.find(str.fileinfo, '|(.-)$') then
    filedesc = {string.match(str.fileinfo, '|(.-)$')}
    info.desc = filedesc[1]
  end

  -- 获取应用图标URL
  local appIcon = self.document.select("div.appico").first()
  if appIcon then
    local style = appIcon.attr("style")
    local iconUrl = string.match(style, "url%((.-)%)")
    info.ico = iconUrl
  end

  -- 获取应用下载URL
  if not string.find(self.uid, "/tp") then
    local url = self.host.."tp/"..self.uid
    local code, data = self:request(url, "get")
    -- 清除所有单行注释
    local data = string.gsub(data, "//v.-", "")
    -- 提取 `submit.href` 拼接的部分
    local href_pattern = "submit%.href%s*=%s*(.-);"
    local href_expression = data:match(href_pattern)

    if href_expression then
      -- 提取 `submit.href` 中的变量
      local variables = {}
      for var in href_expression:gmatch("([%w_]+)") do
        table.insert(variables, var)
      end

      -- 动态获取变量的值
      local link = ""
      for _, var in ipairs(variables) do
        local value = data:match("var " .. var .. " = '(.-)';") or ""
        link = link .. value
      end

      -- 返回成功拼接的URL
      if #link > 0 then
        info.dom = link
        return self:response(self:codes()["LINK_SUCCESS"], "获取直链成功", info)
       else
        -- 错误处理
        return self:response(self:codes()["LINK_FETCH_FAILED"], "获取直链失败", info)
      end
    end
  end
  -- 如果 info 长度小于 3，返回请求过于频繁或需要密码的错误
  if #info < 3 then
    return self:response(self:codes()["REQUEST_TOO_FREQUENT"], "请求过于频繁或需要密码", self.appdata)
  end

end

-- 处理PC端请求
function LanzouyunAPI:pc(callback)
  self.headers['User-Agent'] = self:UserAgent("pc")
  local url = self.host..self.uid
  local code, data = self:request(url, "get")
  local postdata = self:signkey(data)
  local requestUrl = self.host.."filemoreajax.php"

  if callback then
    self:request(url, "get", nil, function(code, data)
      local postdata = self:signkey(data)
      local delay = (self.auto and self.page == 1) and 0 or ((not self.auto) and 0 or (self.page * 1000))
      if delay > 0 then
        task(delay,function()
          handleRequest(self,requestUrl,postdata,self:pc_fileInfo(),callback)
        end)
       else
        handleRequest(self,requestUrl,postdata,self:pc_fileInfo(),callback)
      end
    end)
   else
    return processRequest(self,url,requestUrl,self:pc_fileInfo())
  end
end

-- 获取PC端文件的详细信息
function LanzouyunAPI:pc_fileInfo()
  local info = self.info
  local str = {}
  -- 获取meta description内容
  local metaDescription = self.document.select("meta[name=description]").first()
  if metaDescription then
    str.fileinfo = metaDescription.attr("content") or ""
   else
    str.fileinfo = ""
  end

  -- 获取文件名
  local title = self.document.select("title").first()
  local n_box_3fn = self.document.select(".n_box_3fn").first()
  local styled_div = self.document.select("div[style=font-size: 30px;text-align: center;padding: 56px 0px 20px 0px;]").first()
  local span = self.document.select("span").first()
  if title then
    info.name = title.text()
   elseif n_box_3fn then
    info.name = n_box_3fn.text() or ""
   elseif styled_div then
    info.name = styled_div.text() or ""
   elseif span then
    info.name = span.text() or ""
   else
    info.name = nil
  end

  -- 获取文件大小
  local data = tostring(self.document)
  local filesize = {}
  if string.find(str.fileinfo, '文件大小：(.-)|') then
    filesize = {string.match(str.fileinfo, '文件大小：(.-)|')}
    info.size = filesize[1]
  end

  -- 获取分享者
  local user_name = self.document.select(".user-name").first()
  local font = self.document.select("font").first()
  if user_name then
    info.user = user_name.text() or ""
   elseif font then
    info.user = font.text() or ""
   else
    info.user = nil
  end

  -- 获取上传时间
  local data = tostring(self.document)
  local filetime = data:match('<span class="p7">上传时间：</span>(.-)<br>')
  local n_file_infos = self.document.select(".n_file_infos").first()
  if filetime then
    info.time = filetime
   elseif n_file_infos then
    info.time = n_file_infos.text() or ""
   else
    info.time = nil
  end

  -- 获取文件描述
  local data = tostring(self.document)
  local filedesc = data:match('|(.+)$')
  local n_box_des = self.document.select(".n_box_des").first()
  if n_box_des then
    info.desc = n_box_des.text() or ""
   elseif filedesc then
    info.desc = filedesc
   else
    info.desc = nil
  end

  -- 获取应用图标URL
  local filename_span = self.document.select("span.filename").first()
  if filename_span then
    local img = filename_span:select("img").first()
    if img then
      local iconUrl = img.attr("src")
      info.ico = iconUrl
    end
  end

  -- 获取应用下载URL
  local load_div = self.document.select("div.load#tourl").first()

  if load_div then
    local link = load_div:select("a").first()
    if link then
      local downloadUrl = link.attr("href")
      info.dom = downloadUrl
      return self:response(self:codes()["LINK_SUCCESS"],"获取直链成功",info)
     else
      return self:response(self:codes()["LINK_FETCH_FAILED"],"错误:获取直链失败",info)
    end
  end
  if #info < 3 then
    return self:response(self:codes()["REQUEST_TOO_FREQUENT"],"错误:请求过于频繁或者需要密码",self.appdata)
  end
end
-- 执行HTTP请求，支持GET和POST方法
function LanzouyunAPI:_request(url, method, postdata, callback)
  local cookie = nil
  local headers = self.headers

  if method:lower() == "get" then
    if callback then
      self.Http.get(url, cookie, self.headers['User-Agent'], headers, function(code,content,cookie,heafer)
        local doc = Jsoup.parse(content)
        self.document = doc
        local data = doc.select("script[type=text/javascript]").html() or ""
        callback(code,data)
      end)
     else
      local httpTask = self.Http.get(url,cookie, self.headers['User-Agent'], headers, function()end)
      local result=httpTask.get()
      local code,content=result[0],result[1]
      local doc = Jsoup.parse(content)
      self.document = doc
      local data = doc.select("script[type=text/javascript]").html() or ""
      return code,data
    end
   else
    if callback then
      self.Http.post(url, postdata, self.headers['User-Agent'], headers, function(code,content,cookie,heafer)
        local json = self.cjson.decode(content)
        callback(code,json)
      end)
     else
      local httpTask=self.Http.post(url, postdata, self.headers['User-Agent'], headers, function()end)
      local result=httpTask.get()
      local code,content=result[0],result[1]
      local json = self.cjson.decode(content)
      return code,json
    end
  end
end

-- 请求函数，执行HTTP请求
function LanzouyunAPI:request(url, method, postdata, callback)
  local method = method or "get"
  local postdata = postdata or {}
  return self:_request(url, method, postdata, callback)
end

-- 执行API请求，包括获取文件信息
function LanzouyunAPI:api(url, pwd, options)
  options = options or {}
  self.url = url
  self:UID()
  self.pwd = pwd or ""
  self.mode = options.mode or self.mode
  self.page = options.page or self.page
  self.host = options.host or self.host

  local callback = options.callback
  if callback then
    if self.mode == "pc" then
      self:pc(callback)
     else
      self:mobile(callback)
    end
   else
    if self.mode == "pc" then
      return self:mobile()
     else
      return self:pc()
    end
  end

end

function LanzouyunAPI:Mode(ft)
  if ft == nil then
    self.mode = "ipad"
   else
    self.mode = ft
  end
  return self
end

-- 设置请求的页码
function LanzouyunAPI:Page(i)
  self.page = i or self.page
  return self
end

-- 控制是否自动延迟响应时间
function LanzouyunAPI:Auto(ft)
  if ft == nil then
    self.auto = true
   else
    self.auto = ft
  end
  return self
end

-- 响应函数，返回json格式的响应
function LanzouyunAPI:response(code,mag,data)
  local json = {
    code = code,
    mag = mag,
    data = data
  }
  return self.cjson.encode(json)
end

function LanzouyunAPI:searchfolder()
  local info = self.info
  info.list = {}

  -- 检查 self.searchdata.item 是否存在、是否为表类型并且不为空
  if not self.searchdata.item or type(self.searchdata.item) ~= "table" or #self.searchdata.item == 0 then
    -- 如果不符合条件，直接返回错误提示
    return self:response(self:codes()["RESOURCE_NOT_FOUND"], "错误:请查询其他关键字", {})
   else
    -- 符合条件则继续处理数据
    info.total = self.searchdata.total
    local list = info.list

    -- 遍历 searchdata.item 并插入数据
    for _, item in ipairs(self.searchdata.item) do
      table.insert(list, {
        id = item.id,
        ico = item.ico,
        icon = item.icon,
        p_ico = item.p_ico,
        name = item.name_all,
        size = item.size,
        time = item.time
      })
    end

    -- 返回成功响应
    return self:response(self:codes()["FOLDER_SUCCESS"], "搜索列表", self.info)
  end
end


-- 执行搜索请求，包括获取文件列表
function LanzouyunAPI:search(url, pwd, options)
  self.url = url
  self:UID()
  self.pwd = pwd or ""

  options = options or {}
  self.mode = options.mode or self.mode
  self.host = options.host or self.host
  local search = options.search or self.wb
  local callback = options.callback
  if search == nil or search == "" then
    local response = self:response(self:codes()["NO_SEARCH_CONTENT"], "错误:没有设置搜索内容", {})
    if callback then
      callback(response)
     else
      return response
    end
   else
    self.wd = self.URLEncoder.encode(search)
    self.headers['User-Agent'] = self:UserAgent(self.mode)

    local request_url = self.host .. self.uid
    local requestUrl = self.host .. "search/s.php"

    -- 定义构造局部函数
    local function handleRequest(postdata)
      self:request(requestUrl, "post", postdata, function(code, data)
        self.searchdata = data
        local success = (self.searchdata.total ~= 0)
        if not success then
          if self.searchdata.msg == "Time out" then
            callback(self:response(self:codes()["REQUEST_TOO_FREQUENT"], "错误:请求过于频繁", {}))
           else
            callback(self:response(self:codes()["RESOURCE_NOT_FOUND"], "错误:请查询其他关键字", {}))
          end
         else
          callback(self:searchfolder())
        end
      end)
    end

    -- 定义构造局部函数
    local function processRequest()
      local code, data = self:request(request_url, "get")
      local postdata = self:sign(data)
      local code, data = self:request(requestUrl, "post", postdata)
      self.searchdata = data
      local success = (self.searchdata.total ~= 0)
      if not success then
        if self.searchdata.msg == "Time out" then
          return self:response(self:codes()["REQUEST_TOO_FREQUENT"], "错误:请求过于频繁", {})
         else
          return self:response(self:codes()["RESOURCE_NOT_FOUND"], "错误:请查询其他关键字", {})
        end
       else
        return self:searchfolder()
      end
    end

    if callback then
      self:request(request_url, "get", nil, function(code, data)
        local postdata = self:sign(data)
        handleRequest(postdata)
      end)
     else
      return processRequest()
    end
  end
end

function LanzouyunAPI:Text(t)
  self.wb = t or self.wb
  return self
end

return LanzouyunAPI