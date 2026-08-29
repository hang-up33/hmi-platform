# Canvas.qml の構造

> **⚠️ この文書は 2026-05-24 時点（Task 7 相当）の Canvas.qml を説明したもので、現在の実装とは一致しません。**
> 当時 41 行程度だった `Editor/qml/Canvas.qml` は現在 1,244 行あり、本文が中心に据える
> `default property alias content: widgetLayer.data` は既に存在しません（選択・複数選択・D&D・グリッドスナップ等の増築で構造が変わったため）。
> 現在の構造は [architecture.md](../architecture.md) と実コードを参照してください。書き直しは [refactoring-plan.md](../refactoring-plan.md) の RF タスク完了後が適切です。

[Editor/qml/Canvas.qml](../../Editor/qml/Canvas.qml) は 3 段の入れ子で構成されている。

```mermaid
graph TD
    root["Item (root)<br/>外殻・サイズ"]
    bg["Rectangle (background)<br/>白背景＋枠線"]
    layer["Item (widgetLayer)<br/>Widget の置き場所"]
    root --> bg --> layer
```

---

## `default property alias content: widgetLayer.data` の役割

利用側で `Canvas { HmiButton {} }` と書いたとき、`HmiButton` を **内側の `widgetLayer` に転送する** ための配線。

```mermaid
flowchart LR
    user["Canvas {<br/>　HmiButton {}<br/>}"]
    content["content<br/>(default)"]
    layer["widgetLayer.data"]
    user -- "子要素は default に入る" --> content
    content -- "alias で転送" --> layer
```

これが無いと `HmiButton` は最外殻の `root` の子になり、枠線の外に置かれてしまう。

---

## 1 行の分解

| キーワード | 役割 |
|---|---|
| `default` | プロパティ名を書かずに子要素を並べられる |
| `property alias` | 別プロパティへの透過参照（値を持たない） |
| `content` | プロパティ名（任意） |
| `widgetLayer.data` | 転送先（QML 標準の子要素リスト） |

`QtQuick.Controls` の `Frame` / `Pane` などにも使われている定番イディオム。
