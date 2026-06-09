#pragma once

#include "hmi/schema/ActionData.h"
#include "hmi/schema/BindingData.h"

#include <QJsonObject>
#include <QList>
#include <QString>

namespace hmi::schema {

struct WidgetData {
    QString id;
    QString type;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    QString text;
    QString tag;

    // Task 28: スタイル属性（縦スライス）。いずれも optional（既定値は「未指定」を表し、
    // toJson で省略書き出し、fromJson で既定値埋め）。後方互換のため isValidJson の
    // 必須集合（id/type/width/height）には含めない。値の表現は HmiButton が解釈できる
    // 形式に合わせる：色は "#RRGGBB" 文字列（空 = 未指定）、fontSize は int px（0 = 未指定）。
    // 実際の既定外観（#4cc9f0 / white / 14px）は描画の唯一の真実である HmiButton 側に持つ。
    QString backgroundColor;
    QString textColor;
    int fontSize = 0;

    // Task 31: ボーダー＋角丸（静的スタイル拡充の第 2 バンドル）。Task 28 と同じく
    // optional だが、**`0` が正当値**（borderWidth=0 = ボーダーなし、radius=0 = 角を
    // 丸めない）である点が fontSize（0 = 未指定）と決定的に違う。そこで数値は
    // **`-1` をセンチネル**（未指定）にし、`toJson` は `>= 0` で書き出し（0 も書く）、
    // `fromJson` は `toInt(-1)`（欠落時 -1）で読む。色は backgroundColor 等と同じく
    // 空文字 = 未指定。既定外観（#1d3557 / 太さ 1 / 角丸 4）は HmiButton 側に集約する。
    QString borderColor;
    int borderWidth = -1;
    int radius = -1;

    // Task 33: フォント詳細（静的スタイル拡充の第 3 バンドル）。bool は
    // **既定値（false）と異なる時だけ書き出す**：fontBold / fontItalic は既定 false
    // なので true のときのみ toJson に書き、fromJson は欠落時 false で埋める。
    // fontFamily は空文字 = 未指定（システム既定フォント）で、空のとき省略する。
    // 既定外観（bold/italic なし・システム既定フォント）は HmiButton 側に集約する。
    bool fontBold = false;
    bool fontItalic = false;
    QString fontFamily;

    // Task 34: テキスト配置（hAlign/vAlign）+ 不透明度（opacity）。配置は enum を
    // 人間可読な **文字列**で持つ（hAlign: "left"/"center"/"right"、vAlign:
    // "top"/"middle"/"bottom"。空 = 未指定）。HmiButton 側で `Text.horizontalAlignment`
    // 等へマッピングし、不正値・空はフォールバック（中央）になる。
    // opacity は qreal で **`-1` をセンチネル**（未指定）にする：borderWidth の int
    // センチネルと同型だが real 版で、`0.0`（完全透明）が正当値のため 0 を未指定に使えない。
    // `toJson` は `>= 0.0` で書き出し（0.0 も書く）、`fromJson` は `toDouble(-1)`。
    // 既定（中央寄せ・不透明度 1.0）は HmiButton 側に集約する。
    QString hAlign;
    QString vAlign;
    qreal opacity = -1.0;

    // Task 42: 状態別スタイル（pressed / disabled / checked）。bool 3 つ：
    //   enabled   : **既定 true**（false で淡色 + クリック無効）。toJson は **false のとき書く**、
    //               fromJson は欠落時 true。既定 true のフラグを一律 true 書き出しすると false が
    //               保存されず disabled の round-trip が壊れるため（bool optional の規則）。
    //   checkable : 既定 false（トグル可能か）。true のとき書く、欠落時 false。
    //   checked   : 既定 false（初期トグル状態を永続化）。true のとき書く、欠落時 false。
    //               実行時はアクション（toggleVariable）+ Binding(property:"checked") で変数連動も可能。
    // pressed は状態を持たず HmiButton が押下中に既存の Qt.darker 導出で表現する（保存対象外）。
    // 既定外観は描画の唯一の真実である HmiButton 側に集約する。
    bool enabled = true;
    bool checkable = false;
    bool checked = false;

    // Task 39: アクション（書き手）/ バインディング（読み手）。いずれも optional 配列で、
    // 空のとき toJson で省略（後方互換）。実行 / 描画への反映は T41 以降で、本タスクでは
    // 型と保存（round-trip）のみ。isValidJson の必須集合には含めない（後方互換）。
    QList<ActionData> actions;
    QList<BindingData> bindings;

    QJsonObject toJson() const;
    static WidgetData fromJson(const QJsonObject &obj);

    // JSON が Widget 形式として有効か（id / type / width / height が必要な型で
    // 揃っているか）を判定する。fromJson はキー欠落時に既定値で埋める緩い設計の
    // ため、読込時に「正しい形式かどうか」を判定する際はこちらを使う。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
