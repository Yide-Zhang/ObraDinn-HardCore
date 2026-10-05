#!/usr/bin/env python3
"""启动难度补丁器界面。

    python run_patch_gui.py                 # 自动找端口并开窗口
    python run_patch_gui.py --no-browser    # 只起服务（调试用）
    python run_patch_gui.py --port 9000

为什么要写日志文件：用 PyInstaller `--windowed` 打包后，Windows 上
`sys.stdout/stderr` 是 None（macOS 上是 /dev/null），一旦出错就什么都没了，
所以这里把输出同时写进用户数据目录下的日志文件。
"""
from __future__ import annotations

import argparse
import sys
import traceback
from pathlib import Path

LOG_NAME = "ObraDinnDifficultyPatcher.log"
LOG_MAX = 256 * 1024


class _Tee:
    """把输出同时写给若干流；写不动就算了，绝不让日志拖垮程序。"""

    def __init__(self, *streams):
        self.streams = [s for s in streams if s is not None]

    def write(self, data):
        for s in self.streams:
            try:
                s.write(data)
                s.flush()
            except Exception:                                # noqa: BLE001
                pass
        return len(data)

    def flush(self):
        for s in self.streams:
            try:
                s.flush()
            except Exception:                                # noqa: BLE001
                pass

    def isatty(self):
        return False


def _rotated_log(path: Path):
    try:
        if path.is_file() and path.stat().st_size > LOG_MAX:
            path.replace(path.with_suffix(path.suffix + ".1"))
        return open(path, "a", encoding="utf-8", errors="replace")
    except OSError:
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description="《奥伯拉丁的回归》难度补丁")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--tab", action="store_true",
                    help="用普通标签页打开（不开 app 模式窗口）")
    a = ap.parse_args()

    from patcher import core, server

    logfile = _rotated_log(core.data_dir() / LOG_NAME)
    if logfile is not None:
        sys.stdout = _Tee(sys.__stdout__, logfile)
        sys.stderr = _Tee(sys.__stderr__, logfile)
        print("\n" + "=" * 66)
        print("启动 %s" % server.APP_TITLE)

    port = a.port or server.pick_port(server.DEFAULT_PORT)
    if not server._port_free(port):                          # noqa: SLF001
        port = server.pick_port(port + 1)

    try:
        server.serve(port, open_browser=not a.no_browser)
        return 0
    except Exception:                                        # noqa: BLE001
        traceback.print_exc()
        print("\n出错了。日志在：%s" % (core.data_dir() / LOG_NAME))
        try:
            input("按回车退出…")
        except EOFError:
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
