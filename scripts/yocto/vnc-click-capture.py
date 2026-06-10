#!/usr/bin/env python3
"""i.MX8MP 実機の Qt 描画に VNC 経由で「クリックを送り、前後を digital capture」する
最小 RFB(VNC) クライアント（Phase 4 / Task 43 で確立）。

`vnc-capture.py` は framebuffer を 1 枚読むだけ（読み取り専用）だが、Task 43 の
「アクション（クリック → 変数更新 → バインディング追従）」を実機で動作証跡化するには
**実際にクリックを送って状態が変わる前後を撮る**必要がある。Qt 内蔵 VNC（QVncServer,
port 5900, security None）は RFB の PointerEvent をマウス入力として QML シーンへ
配送するため、本スクリプトでクリックを 1 回送って before / after を保存する。

HDMI 未接続でも撮れる理由・送信元 IF 固定の罠などは vnc-capture.py / dev-environment.md
と同じ。stdlib のみ・依存なし。

使い方（Windows 母艦から。link-local IF を送信元に固定する）:
    # 実機側（ssh 経由で）:
    #   QT_QPA_PLATFORM='vnc:size=1024x768' nohup ./hmi_runtime --open x.json &
    python scripts/yocto/vnc-click-capture.py <board-ip> 5900 \
        before.png after.png <click_x> <click_y> [<source-ip>]

クリック座標はウィンドウ（VNC framebuffer）左上原点の画面ピクセル。Simulator/Runtime は
1024x768 ウィンドウに 800x600 キャンバスを centerIn するので、キャンバス座標 (cx, cy) は
画面 (112 + cx, 84 + cy)。
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


def handshake(s):
    """RFB 3.3 / security None で接続し、(fb_w, fb_h) を返す。"""
    sys.stderr.write(f"server version: {recvn(s, 12)!r}\n")
    s.sendall(b"RFB 003.003\n")
    sectype = struct.unpack(">I", recvn(s, 4))[0]
    if sectype == 0:
        rlen = struct.unpack(">I", recvn(s, 4))[0]
        raise RuntimeError(f"server refused: {recvn(s, rlen)!r}")
    if sectype != 1:
        raise RuntimeError(f"unsupported security type {sectype} (expected 1=None)")
    s.sendall(b"\x01")  # ClientInit shared=1
    si = recvn(s, 24)
    fb_w, fb_h = struct.unpack(">HH", si[0:4])
    name = recvn(s, struct.unpack(">I", si[20:24])[0])
    sys.stderr.write(f"framebuffer {fb_w}x{fb_h} name={name!r}\n")
    # SetPixelFormat: 32bpp little-endian true-colour, メモリ [B,G,R,pad]
    pf = struct.pack(">BBBB HHH BBB xxx", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    s.sendall(struct.pack(">Bxxx", 0) + pf)
    # SetEncodings: RAW(0) のみ
    s.sendall(struct.pack(">BxH", 2, 1) + struct.pack(">i", 0))
    return fb_w, fb_h


def apply_updates(s, frame, fb_w, fb_h, want_px, timeout_s):
    """FramebufferUpdate を読み、frame（RGB バッファ）へ RAW rect を反映する。
    指定ピクセル数を塗るか timeout までループ。塗った総ピクセル数を返す。"""
    painted = 0
    deadline = time.monotonic() + timeout_s
    while painted < want_px and time.monotonic() < deadline:
        mt = recvn(s, 1)[0]
        if mt != 0:
            if mt == 2:
                continue
            if mt == 3:  # ServerCutText
                recvn(s, 3)
                recvn(s, struct.unpack(">I", recvn(s, 4))[0])
                continue
            raise RuntimeError(f"unexpected server message type {mt}")
        recvn(s, 1)
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


def request_update(s, fb_w, fb_h, incremental):
    s.sendall(struct.pack(">BBHHHH", 3, 1 if incremental else 0, 0, 0, fb_w, fb_h))


def pointer(s, mask, x, y):
    s.sendall(struct.pack(">BBHH", 5, mask, x, y))


def main():
    if len(sys.argv) < 7:
        sys.stderr.write(__doc__)
        return 2
    host, port = sys.argv[1], int(sys.argv[2])
    before_path, after_path = sys.argv[3], sys.argv[4]
    click_x, click_y = int(sys.argv[5]), int(sys.argv[6])
    src = sys.argv[7] if len(sys.argv) > 7 else None

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if src:
        s.bind((src, 0))
    s.settimeout(10)
    s.connect((host, port))
    s.settimeout(15)

    fb_w, fb_h = handshake(s)
    frame = bytearray(fb_w * fb_h * 3)

    # 1) before: 全面（non-incremental）を取得
    request_update(s, fb_w, fb_h, incremental=False)
    painted = apply_updates(s, frame, fb_w, fb_h, fb_w * fb_h, timeout_s=12)
    write_png(before_path, fb_w, fb_h, frame)
    sys.stderr.write(f"saved {before_path} ({fb_w}x{fb_h}), painted {painted} px\n")

    # 2) クリックを 1 回送る（press → release）。Qt がアクション実行 + binding 追従する。
    pointer(s, 1, click_x, click_y)
    time.sleep(0.05)
    pointer(s, 0, click_x, click_y)
    sys.stderr.write(f"clicked at ({click_x},{click_y})\n")
    time.sleep(0.8)  # アクション実行 + 再描画を待つ

    # 3) after: 全面（non-incremental）を再取得する。incremental 要求は「変化が無いと
    #    サーバが応答を保留 → recv がブロックして socket timeout」になり扱いづらいため、
    #    必ず全面が返る non-incremental で撮り直す（QVnc は要求領域の全画素を返す）。
    request_update(s, fb_w, fb_h, incremental=False)
    painted2 = apply_updates(s, frame, fb_w, fb_h, fb_w * fb_h, timeout_s=12)
    write_png(after_path, fb_w, fb_h, frame)
    sys.stderr.write(f"saved {after_path} ({fb_w}x{fb_h}), painted {painted2} px after click\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
