# Python 对接

脚本在手机上运行时，连接本机 `127.0.0.1` 的 `6000` 端口。在电脑上远程控制时，把地址换成手机的 IP。安装包装好的 Python 模块在手机上，脚本里直接 `import`。

手机上的 Python 是 3.9。脚本里不要写 `match`，也不要写 `list[str]` 这种写法。

## 脚本目录

每个脚本是一个以 `.bdl` 结尾的文件夹，放在：

`/var/mobile/Library/ZXTouch/scripts/`

文件夹里要有入口文件和 `info.plist`。`Entry` 填要执行的 py 文件名。

```xml
<key>Entry</key>
<string>main.py</string>
```

RootHide 上，这个目录和越狱环境里看到的目录不一定是同一个。脚本要复制到 ZXTouch 实际读取的那一份，文件属主用 `mobile`，文件权限 `644`。

## 连接

多数方法返回 `(成功, 结果)`。失败时第一项是 `False`，第二项是错误文字。用完要断开。

```python
from zxtouch.client import zxtouch
from zxtouch.touchtypes import TOUCH_DOWN, TOUCH_UP
from zxtouch.toasttypes import TOAST_MESSAGE

device = zxtouch("127.0.0.1")
try:
    ok, size = device.get_screen_size()
    if not ok:
        raise RuntimeError(size)
finally:
    device.disconnect()
```

## 坐标

`get_screen_size()` 返回的就是像素，例如 iPhone 13 是 `1170 x 2532`。点击、扫描、自定义提示位置都用这套像素。

`get_screen_scale()` 是另外一项，iPhone 13 上是 `3`。不要把上面的宽高再乘一次，也不要把坐标再除一次。

## 扫描文字

```python
ok, items = device.ocr(
    (0, 0, width, height),
    recognition_level=0,
    languages=["zh-Hans", "en-US"],
)
```

`region` 是 `(x, y, width, height)`，单位是像素。

`recognition_level`：`0` 是准确模式，能认中文；`1` 是快速模式，中文经常认错。中文用 `zh-Hans`，繁体是 `zh-Hant`。有哪些语言可以用 `get_supported_ocr_languages(0)` 看。

成功时 `items` 是一组字典：

```python
{"text": "同意并继续", "x": "482", "y": "1591", "width": "221", "height": "44"}
```

这里的 `x`、`y` 已经是屏幕坐标。区域不是从 `(0, 0)` 开始时，也不要再把区域的起点加回去。

区域高度超过 640 像素时，安装包会在内部按 640 高、每段下移 560 来分段识别，脚本仍然只调用一次 `ocr`。返回的各行已经按文字和位置合并过。整屏准确识别不要在脚本里再拆成多次调用。

比对按钮时用整句相等，不要用包含关系去点一个更短的字。

```python
def find_exact(items, text):
    for item in items:
        if item.get("text") == text:
            return item
    return None
```

## 点击

同一个手指先按下，再抬起。坐标用像素。

```python
def tap(device, x, y):
    device.touch(TOUCH_DOWN, 1, x, y)
    device.touch(TOUCH_UP, 1, x, y)
```

扫描结果里的 `x`、`y` 是文字框左上角。要点中心时，加上宽高的一半。

## 提示

```python
device.show_toast(TOAST_MESSAGE, "当前 首页", 8, 0, 18, -1, 312)
```

参数依次是类型、文字、秒数、位置、字号、左边、顶边。

位置 `0` 是靠上，`1` 是靠下。字号单位是点。`x`、`y` 是像素，`-1` 表示沿用原来的位置。`y` 大于等于 `0` 时，顶边就是这个像素，不会再往下加一截安全区。

类型从 `zxtouch.toasttypes` 引入：`TOAST_MESSAGE`、`TOAST_SUCCESS`、`TOAST_ERROR`、`TOAST_WARNING`。旧版安装包没有最后两个坐标参数，多传会报 `TypeError`，可以接住后再用原来的五个参数调用一次。

## 输入和切换应用

```python
device.switch_to_app("com.apple.Preferences")
device.insert_text("13800138000")
```

`switch_to_app` 的参数是包名。`insert_text` 把文字打进当前输入框。`\b` 会删一个字。

弹窗用 `show_alert_box(标题, 内容, 秒数)`。需要用户打字时用 `prompt_input`。
