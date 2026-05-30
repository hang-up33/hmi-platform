---
name: reference-context7-mcp
description: Context7 MCP（HTTPトランスポート、ユーザースコープ）が利用可能。最新ライブラリドキュメント参照用
metadata: 
  type: reference
---

Context7 MCP がユーザースコープで導入済み（`https://mcp.context7.com/mcp`、HTTP）。

ライブラリの**最新ドキュメント**（Qt6 / QML / C++ 標準ライブラリ / npm / pip パッケージなど）を参照したい時に使用する。`resolve-library-id` でライブラリ ID を解決してから `get-library-docs` で取得する流れ。

特に本プロジェクト（Qt6 + QML + CMake）では：
- Qt6 / QML の新しい API や挙動を確認したい時
- CMake の `qt_add_qml_module` 等の最新オプションを確認したい時
- 学習データにない最近のリリース内容を確認したい時

設定ファイル：`~/.claude.json`（ユーザースコープ）
