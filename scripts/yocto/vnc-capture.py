#!/usr/bin/env python3
"""i.MX8MP 実機の Qt 描画を「ディスプレイ未接続でも」digital capture する最小 RFB(VNC) クライアント。

Phase 4 / Task 30 で確立。実機の HDMI が未接続だと weston に wl_output が無く
（`DRM: head 'HDMI-A-1' ... is disconnected`）、Qt は "fake screen" に描画して
`weston-screenshooter` でも何も撮れない。そこで **`QT_QPA_PLATFORM=vnc` で hmi_runtime を
起動 → Qt 内蔵 VNC サーバ（QVncServer, port 5900, security None）の framebuffer を
本スクリプトで 1 枚取得 → PNG 保存** する。実機 GPU/CPU での styled 描画を物理モニタ無しで
動作証跡化できる（stdlib のみ・依存なし）。

使い方（Windows 母艦から。link-local IF を送信元に固定する）:
    # 実機側（ssh 経由で）: QT_QPA_PLATFORM='vnc:size=1280x720' nohup ./hmi_runtime --open x.json &
    python scripts/yocto/vnc-capture.py <board-ip> 5900 out.png [<source-ip>]

注意・既知の罠（dev-environment.md / scripts/yocto/README.md にも記載）:
- 実機を ssh 越しに止める時、`pkill -f hmi_runtime` は **ssh のリモートシェル自身の
  コマンドラインにも "hmi_runtime" が含まれる**ため自分の親シェルを kill して ssh が
  exit 255 で即死する。必ず `pkill -x hmi_runtime`（実行ファイル名完全一致）を使う。
- 母艦に複数の link-local IF があると 169.254.x.x の宛先 IF 選択がぶれて到達不能になる。
  ssh/scp は `-b <source-ip>`、本スクリプトは第 4 引数 `<source-ip>` で送信元を固定する。
"""
import socket
import struct
import sys
import time
import zlib


def recvn(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise RuntimeError(f"connection closed (got {len(buf)}/{n} bytes)")
        buf += chunk
    return bytes(buf)


def write_png(path, w, h, rgb):
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)  # 8bit, colour type 2 = RGB
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)  # filter: none
        raw += rgb[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    src = sys.argv[4] if len(sys.argv) > 4 else None
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if src:
        s.bind((src, 0))
    s.settimeout(10)
    s.connect((host, port))
    s.settimeout(15)

    # 1) ProtocolVersion: 3.3 で応答（security None を単純化）
    sys.stderr.write(f"server version: {recvn(s, 12)!r}\n")
    s.sendall(b"RFB 003.003\n")

    # 2) Security (3.3): uint32 の security type
    sectype = struct.unpack(">I", recvn(s, 4))[0]
    if sectype == 0:
        rlen = struct.unpack(">I", recvn(s, 4))[0]
        raise RuntimeError(f"server refused: {recvn(s, rlen)!r}")
    if sectype != 1:
        raise RuntimeError(f"unsupported security type {sectype} (expected 1=None)")

    # 3) ClientInit（shared=1）→ 4) ServerInit
    s.sendall(b"\x01")
    si = recvn(s, 24)
    fb_w, fb_h = struct.unpack(">HH", si[0:4])
    name = recvn(s, struct.unpack(">I", si[20:24])[0])
    sys.stderr.write(f"framebuffer {fb_w}x{fb_h} name={name!r}\n")

    # 5) SetPixelFormat: 32bpp little-endian true-colour, R<<16 G<<8 B<<0（メモリ [B,G,R,pad]）
    pf = struct.pack(">BBBB HHH BBB xxx", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    s.sendall(struct.pack(">Bxxx", 0) + pf)

    # 6) SetEncodings: RAW(0) のみ
    s.sendall(struct.pack(">BxH", 2, 1) + struct.pack(">i", 0))

    # 7) FramebufferUpdateRequest（full）→ RAW rect を組み立てて RGB 化
    s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, fb_w, fb_h))
    frame = bytearray(fb_w * fb_h * 3)

    def read_update():
        mt = recvn(s, 1)[0]
        if mt != 0:
            if mt == 2:
                return 0
            if mt == 3:  # ServerCutText
                recvn(s, 3)
                recvn(s, struct.unpack(">I", recvn(s, 4))[0])
                return 0
            raise RuntimeError(f"unexpected server message type {mt}")
        recvn(s, 1)
        painted = 0
        for _ in range(struct.unpack(">H", recvn(s, 2))[0]):
            rx, ry, rw, rh, enc = struct.unpack(">HHHHi", recvn(s, 12))
            if enc != 0:
                raise RuntimeError(f"unsupported encoding {enc} (RAW only)")
            data = recvn(s, rw * rh * 4)
            for row in range(rh):
                src_i = row * rw * 4
                dst = ((ry + row) * fb_w + rx) * 3
                for _col in range(rw):
                    frame[dst] = data[src_i + 2]      # R
                    frame[dst + 1] = data[src_i + 1]  # G
                    frame[dst + 2] = data[src_i]      # B
                    src_i += 4
                    dst += 3
            painted += rw * rh
        return painted

    total = 0
    deadline = time.monotonic() + 12
    while total < fb_w * fb_h and time.monotonic() < deadline:
        total += read_update()
    write_png(out, fb_w, fb_h, frame)
    sys.stderr.write(f"saved {out} ({fb_w}x{fb_h}), painted {total} px\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
