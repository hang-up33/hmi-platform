# hmi-platform（Atlas）

GUI で HMI 画面を作図 → JSON で保存 → PC でも組込み実機でも同じ画面を描画する、Qt6 ベースの HMI 開発プラットフォーム。

- **Editor** … マウスで Widget を並べて画面を作る作画ツール
- **Simulator** … 同じ JSON を PC で描画して動作確認する試験環境
- **Runtime** … その JSON を i.MX8M Plus などの実機（Yocto / Qt6）で描画するランタイム

> コードネーム **Atlas**（天空を支える巨神 ＝ Editor / Simulator / Runtime / Shared を束ねる基盤の意）。正式なリポジトリ名は `hmi-platform`。

![HMI Editor](Docs/screenshots/editor.png)

Editor。ツールバーで Widget 追加（ボタン / ラベル / 数値入力）・JSON 開く / 保存・編集補助（スナップ・コピペ・undo / redo）、右のインスペクタでスタイル・配置・アクション・バインディングを編集できる。数値入力（NumericField）は変数の型（int / real）を引き継ぎ、インスペクタ「詳細」の範囲（最小値 / 最大値）で入力 clamp の境界を指定できる（図は real 変数 temperature を bind した選択中の例）。**Phase 7（Modbus TCP）着手に伴い、変数パネル（ツールバー「変数」トグル）の各変数に「PLC レジスタに割当」を追加**：チェックすると接続先（ホスト / ポート / Unit ID）とレジスタ写像（レジスタ種別 coil/discrete/input/holding・アドレス・ポーリング間隔 ms）を編集でき、JSON に保存される（MB-1 は定義の保存のみ＝実通信は後続タスク。ヒーロー図の既定ビューは変数パネル非表示のため不変）。

![HMI Simulator](Docs/screenshots/simulator.png)

Simulator（読み取り専用）。同じ JSON を描画し、変数・クリックアクション・バインディングも動く（ボタン操作や数値入力で変数が変わると、それを参照する Widget が追従）。ツールバーの「変数」トグルで、実行時のタグ（変数）現在値をライブ表示するデバッグパネルを開ける（右）。

## できること

- ドラッグ＆ドロップで Widget を配置・リサイズ・整列（複数選択・スナップ・コピペ・undo / redo）
- Widget 種別: **Button / Label / NumericField**（型分岐で順次拡張中）
- スタイル: 背景色 / 文字色 / フォント（名・サイズ・太字・斜体）/ テキスト配置 / ボーダー / 角丸 / 不透明度
- 状態とロジック: 変数ストア・クリックアクション・読み書きバインディング（入力で変数を書き、他 Widget が追従）
- 1 つの JSON を Editor / Simulator / 実機 Runtime で共有（`Shared/Schema` が唯一の真実）

## 必要要件

- Qt **6.8 以上**（macOS 14+ では Qt 6.7 以前は `AGL.framework` 不在でリンク不可）
- CMake **3.21 以上**、C++17 対応コンパイラ

## ビルドと起動

### macOS

```sh
brew install qt
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

### Windows（PowerShell）

Qt Online Installer で **Qt 6.11.0 MinGW 64-bit** kit（付属 MinGW / Ninja / CMake）を入れて:

```powershell
.\scripts\windows\build.ps1     # configure + build → build-mingw\ に出力
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
```

新しいシェルからは `. .\scripts\windows\setup-env.ps1` で PATH を通す。Explorer から起動したい場合は `.\scripts\windows\deploy.ps1`（windeployqt で DLL 同梱）。ビルドの詳細・既知の罠は開発ノート [.claude/skills/qt6-build/SKILL.md](.claude/skills/qt6-build/SKILL.md) を参照。

### Simulator / Runtime に JSON を渡す

```sh
hmi_simulator --open path/to/project.json
hmi_runtime   --open path/to/project.json
```

## プロジェクトファイル形式

`Shared/Schema` を唯一の真実とし、project / screen / widget を JSON で表す:

```json
{
  "project": "Sample",
  "screens": [
    {
      "name": "Main",
      "widgets": [
        { "id": "btn001", "type": "Button", "x": 100, "y": 50,
          "width": 120, "height": 40, "text": "Start",
          "backgroundColor": "#e63946", "textColor": "#ffffff", "fontSize": 22 }
      ]
    }
  ]
}
```

- 必須: `id` / `type` / `width` / `height`
- `x` / `y` は省略可（欠落時は `0` として扱う）
- 色・フォント等のスタイル属性は省略可（省略時は Widget の既定外観にフォールバック＝旧 JSON も後方互換で描画）

## フォルダ構成

```text
hmi-platform/
├─ Editor/        作画アプリ（Qt6 + QML）
├─ Simulator/     試験アプリ（読み取り専用）
├─ Runtime/       実機向け。Simulator/ のソースを共有して hmi_runtime を生成
├─ Shared/
│   ├─ Schema/    JSON スキーマ・C++ データモデル（唯一の真実）
│   └─ Widgets/   共通 QML Widget（Button / Label / NumericField …）
├─ Docs/          設計・開発ドキュメント
└─ CMakeLists.txt ルート CMake
```

## 実機（i.MX8M Plus / Yocto）

`hmi_runtime` だけを aarch64 にクロスビルドして実機へ転送・起動する（PC ビルドには影響しない）:

```sh
./scripts/yocto/cross-build.sh          # WSL2 内。meta-toolchain-qt6 の Qt6 クロス SDK を使用
scp -O ~/build-yocto/Runtime/hmi_runtime root@<board-ip>:/tmp/hmi_runtime
```

SDK 生成・実機 scp・起動（weston）・キャプチャの全手順と罠は [scripts/yocto/README.md](scripts/yocto/README.md) を参照。下は i.MX8MP 実機（scarthgap / Qt6 / weston）で Editor 由来の JSON を描画した様子:

![hmi_runtime on i.MX8MP](Docs/screenshots/task-43-runtime-action.png)

## ステータスとドキュメント

- **現在地**: **Phase 7 / Modbus TCP 通信を実装中**（2026-06-16 承認）。MB-1〔変数ソース Schema（`ConnectionData` + `VariableData.source`）+ Editor 接続編集 UI・実通信なし〕完了（PR #119）。MB-2〔PC 読込ポーリング：Simulator/Runtime が `QModbusTcpClient` で PLC レジスタを周期読込 →変数ストア + binding 経路へ。pymodbus ソフトスレーブ E2E〕実装中。直近完了は Phase 6-B / NumericField 拡張（Task 53〜55・PR #112〜#114）。MB-3/5/6（実 PLC・実機）はローカル専用。進捗の正本は [Docs/phase7-modbus-plan.md](Docs/phase7-modbus-plan.md)。
- 開発の時系列（各タスクの目的 / PR / 学び）: [Docs/development-history.md](Docs/development-history.md)
- 各フェーズの計画と進捗表（正本）: [Docs/](Docs/) の `phase*-plan.md`
- 開発ガイド・ビルドの罠・ルール: [CLAUDE.md](CLAUDE.md)

## ライセンス

（未定）
