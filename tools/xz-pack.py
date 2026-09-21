#!/usr/bin/env python3
"""xz-pack.py -- 在 PC 上把 rootfs tar 压成 tar.xz（换掉 APK 里的 asset）

用法： python tools/xz-pack.py <in.tar> <out.tar.xz> [preset]

说明：Windows 上没有 xz.exe，Python 自带 lzma（liblzma）就够了。
preset 默认 9e（极端模式，dict 64MB）；想快点就传 6。
"""
import lzma
import os
import sys
import time


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    preset_arg = sys.argv[3] if len(sys.argv) > 3 else "9e"
    if preset_arg == "9e":
        preset = 9 | lzma.PRESET_EXTREME
    else:
        preset = int(preset_arg)

    filters = [{"id": lzma.FILTER_LZMA2, "preset": preset, "dict_size": 1 << 26}]
    total = os.path.getsize(src)
    print(f"[xz] {src}  {total / 1048576:.1f} MiB  preset={preset_arg} dict=64MiB")

    t0 = time.time()
    done = 0
    last = 0.0
    with open(src, "rb") as fin, lzma.open(dst, "wb", format=lzma.FORMAT_XZ, filters=filters) as fout:
        while True:
            chunk = fin.read(1 << 22)
            if not chunk:
                break
            fout.write(chunk)
            done += len(chunk)
            now = time.time()
            if now - last >= 20:
                last = now
                pct = done * 100.0 / total
                rate = done / 1048576.0 / max(now - t0, 0.001)
                eta = (total - done) / 1048576.0 / max(rate, 0.001)
                print(f"  {pct:5.1f}%  {rate:5.2f} MiB/s  剩余约 {eta / 60:.1f} 分钟", flush=True)

    out = os.path.getsize(dst)
    print(f"[xz] 完成：{out} 字节 = {out / 1048576:.2f} MiB，"
          f"压缩率 {out * 100.0 / total:.1f}%，用时 {(time.time() - t0) / 60:.1f} 分钟")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
