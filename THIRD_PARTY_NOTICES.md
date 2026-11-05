# Third-party notices / 依存ライブラリのライセンス

Atlas（hmi-platform）自体のコードは [MIT License](LICENSE) で公開している。
ここに挙げるライブラリはそれぞれのライセンスに従う。本リポジトリはソースコードだけを配布し、下のライブラリ本体は同梱していない。

## アプリにリンクされるもの

| ライブラリ | 使う場所 | ライセンス | 出典 |
|---|---|---|---|
| Qt 6（Core / Gui / Qml / Quick、QML の QtQuick.Controls / Dialogs / Layouts / Window） | Editor / Simulator / Runtime | LGPL-3.0 または GPL-2.0 / GPL-3.0（または Qt の商用ライセンス） | https://www.qt.io/licensing/open-source-lgpl-obligations |
| Qt Serial Bus / Qt Serial Port（と、そこから使う Qt Network） | Simulator / Runtime（Modbus TCP） | LGPL-3.0 または GPL-2.0（または商用） | https://doc.qt.io/qt-6/qtserialbus-index.html |
| Qt OPC UA | Simulator / Runtime（OPC-UA。導入されている場合だけ使う） | LGPL-3.0 または GPL-2.0（または商用） | https://doc.qt.io/qt-6/qtopcua-index.html |
| open62541 | Qt OPC UA のバックエンドとして間接的に使う。Qt OPC UA に同梱された版を使う場合は、Qt の attribution に載っているライセンスすべてが対象になる | MPL-2.0、CC0-1.0、CC-BY-SA-4.0、BSD-3-Clause、Apache-2.0、MIT | https://doc.qt.io/qt-6/qtopcua-attribution-open62541.html |
| Spix v0.14 | E2E テスト用の接続口。`HMI_ENABLE_E2E=ON`（Windows MinGW 以外の既定）のとき Editor / Simulator にリンクされる | MIT | https://github.com/faaxm/spix |
| AnyRPC | Spix が使う通信ライブラリ。Spix と一緒にリンクされる | MIT | https://github.com/sgieseking/anyrpc |

Spix と AnyRPC は CMake の FetchContent でビルド時に取得する。`-DHMI_ENABLE_E2E=OFF` でビルドすれば、どちらもリンクされない。

## テストとスクリプトだけで使うもの

| ライブラリ | 使う場所 | ライセンス | 出典 |
|---|---|---|---|
| Qt Test / Qt Quick Test | ユニットテスト | Qt 6 と同じ | 上と同じ |
| asyncua | OPC-UA の E2E テストとテスト用サーバ（Python） | LGPL-3.0 | https://github.com/FreeOpcUa/opcua-asyncio |
| pymodbus | Modbus の E2E テスト（Python） | BSD-3-Clause | https://github.com/pymodbus-dev/pymodbus |
| Pillow | README 用の画像生成スクリプト（Python） | MIT-CMU | https://github.com/python-pillow/Pillow |

## ビルドしたアプリを配布するとき

本リポジトリはビルド済みのバイナリを配布していない。自分でビルドしたアプリを配布するときは、次の条件を守る必要がある。詳しくは上の各出典を参照。

**Qt（LGPL-3.0）**

- 動的リンクするのが簡単。静的リンクする場合は、利用者が Qt を差し替えて再リンクできるよう、アプリのオブジェクトファイルなども提供する。
- Qt のソースコード（変更した場合は変更後のもの）を提供するか、提供すると書面で約束する。
- LGPL の本文と、LGPL のライブラリを使っている旨を添える。
- Qt 入りのアプリを機器に組み込んで配布する場合は、利用者が差し替えた Qt を機器に入れて動かす方法（インストール情報）も提供する。

**Spix と AnyRPC（MIT）**

- 既定の設定でビルドしたバイナリを配布するときは、両者の LICENSE にある著作権表示と許諾文を添える。
- E2E テストが不要なら、`-DHMI_ENABLE_E2E=OFF` でビルドすればこの条件はなくなる。
