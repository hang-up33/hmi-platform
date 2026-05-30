---
name: feedback-docs-style
description: ユーザーはドキュメント作成時に「Mermaid 図 + 最小限の説明」を強く好む。ASCII 図や詳細な散文は冗長と感じる
metadata: 
  type: feedback
---

ドキュメント（特に `Docs/` 配下の解説 .md）を新規作成する際は、最初から以下のスタイルで書く：

- **図は Mermaid** を使う（ASCII アート図ではなく）。GitHub が標準でレンダリングするため可読性が高い
- **散文は最小限**。問題提起・解決・分解表の 3 部構成程度に抑える
- セクション見出しを増やすより、表 1 つで済むものは表にする

**Why:** 初回に「冗長な ASCII 図 + 詳細な散文 + 6 セクション」のドキュメントを書いたところ、「Mermaid 使って、ずっと簡単な説明だけに改善」と明示的に減量を求められた（[Docs/qml-canvas-structure.md](../../Docs/qml-canvas-structure.md) の初版 → 改訂）。一度書いて減らす二度手間を避ける。

**How to apply:** `Docs/` や README 系の新規ドキュメントを書く前に、まず「Mermaid 図 + 表 + 短い説明」の骨組みで書き始める。詳細を足すのはユーザーから求められてからにする。コメント・コミットメッセージ・PR 本文には適用しない（あくまでドキュメントファイル本体の話）。

関連：[[user-language-japanese]]
