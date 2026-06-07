# Claude Code on the web で開発する（Qt6 を導入する）

これまで「Web 版は非対応」としていた理由は **Qt をインストールできない** ことだったが、原因は
コンテナの**ネットワークアクセスが既定の `Trusted`** で `download.qt.io` を遮断していた点にあった。
**ポリシーを `Full` にすれば CI と同じ `aqtinstall` がそのまま通り、Web でもビルド〜テストできる**。

GUI ディスプレイは不要：ビルド・ユニット・E2E は `-platform offscreen`、スクショは `QT_QPA_PLATFORM=vnc`
で成立する（CI が毎回実証）。詳細な経緯・代替案は本ドキュメント末尾。

## セットアップ手順

```mermaid
flowchart LR
    A["環境設定<br/>Network = Full"] --> B["Setup script 欄に<br/>bash scripts/web/setup.sh"]
    B --> C["初回セッションで<br/>Qt 6.10.0 を /opt/Qt に導入"]
    C --> D["スナップショットに<br/>キャッシュ（~7日）"]
    D --> E["SessionStart hook が<br/>CMAKE_PREFIX_PATH を設定"]
    E --> F["cmake --build / ctest が通る"]
```

| 手順 | 操作 | 補足 |
|---|---|---|
| 1 | 環境設定で **Network access = Full** | 既定 `Trusted` は Qt ミラーを 403 で遮断。`Full`（任意ドメイン）が必要。`Custom` + `*.qt.io` 等でも可 |
| 2 | **Setup script** 欄に `bash scripts/web/setup.sh` | 初回のみ実行→**スナップショットにキャッシュ**され 2 回目以降は即起動（約 7 日保持） |
| 3 | （自動）SessionStart hook が `CMAKE_PREFIX_PATH` を設定 | `.claude/settings.json` + `scripts/web/session-env.sh`。ローカルでは `CLAUDE_CODE_REMOTE!=true` で no-op |

## 関与ファイル

| ファイル | 役割 | 実行場所 |
|---|---|---|
| `scripts/web/setup.sh` | apt 依存 + `aqtinstall` で Qt 6.10.0（`linux_gcc_64`）を `/opt/Qt` へ。冪等 | 環境の Setup script（キャッシュ） |
| `scripts/web/session-env.sh` | `/opt/Qt/*/gcc_64` を探し `CMAKE_PREFIX_PATH` を `$CLAUDE_ENV_FILE` に書く | SessionStart hook（毎回・即 no-op 判定あり） |
| `.claude/settings.json` | 上記 hook の登録 | — |

## ビルド・テスト（Web）

```sh
# SessionStart hook が CMAKE_PREFIX_PATH を入れているので明示不要。手動なら下記を渡す:
#   -DCMAKE_PREFIX_PATH=/opt/Qt/6.10.0/gcc_64
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure          # ユニット（QML テストは -platform offscreen 済み）
ctest --test-dir build -L e2e --output-on-failure    # E2E（harness.py が QT_QPA_PLATFORM=offscreen を設定）
```

## なぜ GUI が無くても良いか

| 用途 | 仕組み | 既存の使用箇所 |
|---|---|---|
| ユニット / QML テスト | `-platform offscreen` | `Editor/tests/`, `Shared/Widgets/tests/` |
| E2E（Spix） | `QT_QPA_PLATFORM=offscreen` | `tests/e2e/harness.py` |
| スクショ証跡 | `QT_QPA_PLATFORM=vnc` | `scripts/yocto/vnc-capture.py` |

ただし offscreen には限界がある：Spix の実マウスドラッグ（`mouseBeginDrag/EndDrag`）は drag 閾値に
届かず、座標変更は `setStringProperty` で代替している（`Docs/development-history.md` 参照）。
真の手動操作検証は引き続きローカル / 実機で行う。

## 代替案（ポリシーを変えられない場合）

`Full` にできない事情があるときは、`Trusted` のまま **Qt 一式を tar に固めて GitHub Release に置く**手もある
（`release-assets.githubusercontent.com` は Trusted の既定許可に含まれる）。Setup script でその tar を取得・展開し、
`CMAKE_PREFIX_PATH` を同様に通す。Qt blob を用意・ホストする手間がかかるため、まずは `Full` + `aqtinstall` を推奨。

## 注意

- ネットワークアクセスと Setup script 欄は **Web UI でのみ設定**でき、コンテナ内からは変更できない（手順 1・2 は人手）。
- Setup script / 環境変数は環境設定に保存され、その環境を編集できる人に見える。秘匿情報は置かない。
- `aqtinstall` の Qt バージョンは CI（`jurplel/install-qt-action@v4`）と合わせ **6.10.0**。`HMI_QT_VERSION` で上書き可。
