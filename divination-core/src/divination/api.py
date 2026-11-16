"""api —— 对外总机：平台层（Swift / 网页）唯一需要知道的入口。

把一条 JSON 请求路由到对应功能，返回 JSON 响应。
以后加新命令 / 新术数，只在这里加分支，C 桥和 Swift 都不用动。

请求： {"cmd": "<命令>", ...参数}
响应： 命令决定（卦象 JSON，或 {"error": "..."}）
"""
import json

from divination.iching import service as iching_service
from divination.ganzhi import service as ganzhi_service
from divination.meihua import service as meihua_service
from divination.bazi import service as bazi_service
from divination import plugins

import importlib
import pkgutil

_SERVICES = (iching_service, ganzhi_service, meihua_service, bazi_service)

_HANDLERS: dict = {}
for _module in _SERVICES:
    _HANDLERS.update(_module.COMMANDS)
for _info in pkgutil.iter_modules(plugins.__path__, plugins.__name__ + "."):
    _plugin = importlib.import_module(_info.name)
    _HANDLERS.update(_plugin.COMMANDS)

def handle(request_json: str) -> str:
    try:
        req = json.loads(request_json)
        cmd = req.get("cmd")
        handler = _HANDLERS.get(cmd)
        if handler is None:
            return _error(f"unknown cmd: {cmd!r}")
        return handler(req)
    except Exception as e:
        return _error(f"{type(e).__name__}: {e}")


def _error(message: str) -> str:
    return json.dumps({"error": message}, ensure_ascii=False)