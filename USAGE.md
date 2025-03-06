# LanzouyunAPI 使用方法

LanzouyunAPI 支持多种解析行为，包括：
- **文件夹解析**
- **应用列表**
- **搜索列表**
- **直链解析**

目前使用 **submit.href** 表达式获取下载链接，通常情况下都很稳定。

---

## **1. 基本用法**
使用 API 获取文件夹内的文件列表：

```lua
LanzouyunAPI:new():Page(1):api('s/0023', "", {
  mode = "pc", -- "pc" 切换到桌面 UA，其他选项如 "ipad"、"mobile" 适用于手机 UA
  callback = function(data)
    print(dump(data))
  end
})
```

---

## **2. 搜索文件**
通过 API 在蓝奏云文件夹内搜索 **"小说"**：

```lua
LanzouyunAPI:new():Page(1):search('s/0023', "", {
  mode = "pc",
  search = "小说", -- 搜索关键字
  callback = function(data)
    print(dump(data))
  end
})
```

---

## **3. 获取直链**
解析蓝奏云直链，获取最终下载地址：

```lua
LanzouyunAPI:new():Page(1):api('https://fxjd.lanzn.com/iVVpa28wk20f', "", {
  callback = function(data)
    print(dump(data))
  end
})
```

---

## **参数说明**
| 参数名       | 说明 |
|-------------|----------------|
| `mode`   | 选择 UA，支持 "pc"（桌面版）、"ipad"、"mobile" |
| `search` | 搜索关键字，仅适用于 `search()` 方法 |
| `callback` | 异步回调函数，解析成功后返回数据 |
| `Page(n)` | 选择分页，n 为页码 |

---

## **注意事项**
- **该 API 依赖 `submit.href` 解析，通常较为稳定。**
- **"mode" 参数决定使用 PC 端或移动端访问方式。**
- **"callback" 参数为异步方法，数据将通过回调函数返回。**

---

## **未来计划**
- 可能移除对 `jsoup` 库的依赖，以简化使用流程。

---
