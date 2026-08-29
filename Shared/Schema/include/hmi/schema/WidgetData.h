#pragma once

#include "hmi/schema/ActionData.h"
#include "hmi/schema/BindingData.h"
#include "hmi/schema/TrendSeriesData.h"

#include <QJsonObject>
#include <QList>
#include <QString>
#include <QVariantMap>

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

    // Task 54: 数値範囲（NumericField の入力 clamp 用）。**負値が正当**（例 min=-100）なので
    // borderWidth の `-1` センチネルや opacity の `-1.0` センチネルが使えない。そこで
    // **presence フラグ方式**を採る：値（double）と「指定されているか」（bool）を対で持つ。
    //   toJson    : hasMinValue のときだけ minValue を書く（未指定はキー省略＝後方互換）。
    //   fromJson  : hasMinValue = obj.contains("minValue")、値は toDouble()。
    //   toVariantMap/fromVariantMap も同じ presence 規則で対転写する。
    // 型は double（int レンジを内包し real レンジ〔0.5 等〕も表せる）。NumericField 側で
    // int 変数なら IntValidator の bottom/top へ丸めて渡す。isValidJson の必須集合には
    // 含めない（optional ＝後方互換）。
    double minValue = 0.0;
    double maxValue = 0.0;
    bool hasMinValue = false;
    bool hasMaxValue = false;

    // Task T-A（Phase 8）: Trend（トレンドグラフ）固有フィールド。設計の正本は
    // Docs/archive/phase8-trend-plan.md「§Task A」。すべて optional ＝ isValidJson 必須集合に含めない（後方互換）。
    //   pointCount(N) / sampleMs[ms] : `0` センチネル（= 未指定）。toJson は `> 0` のときだけ書く。
    //     `0`/負値はいずれも下流（HmiTrend）が「未指定」として既定へ解決するためクランプしない。
    //   yMin/hasYMin・yMax/hasYMax : Y 軸範囲。**負値が正当**なのでセンチネル不可 → presence フラグ方式
    //     （minValue/maxValue の前例踏襲）。**JSON は hasYMin キーを作らず yMin キーの有無で presence を
    //     表す**が、**C++↔QML ブリッジの QVariantMap は既存 min/max に倣い明示 bool キー hasYMin/hasYMax を持つ**。
    //   lineColor : `""` センチネル（= 未指定）。非空のときだけ書く（backgroundColor 同型）。
    // 既定外観（既定 N / 既定線色 / 既定背景）は描画の唯一の真実である HmiTrend 側に集約する。
    int pointCount = 0;
    double yMin = 0.0;
    double yMax = 0.0;
    bool hasYMin = false;
    bool hasYMax = false;
    QString lineColor;
    int sampleMs = 0;

    // Task 8B-A（Phase 8-B）: Trend 拡張。複数系列 + 軸目盛り/凡例。すべて optional ＝
    // isValidJson 必須集合に含めない（後方互換）。設計の正本は
    // Docs/archive/phase8b-trend-extend-plan.md「§Task 8B-A」。
    //   series      : N 本の折れ線（子型 TrendSeriesData {variable, color, label} の配列）。
    //     空のとき toJson 省略（actions/bindings 同型）。**series 空＝Phase 8 単系列の暗黙 1 系列**
    //     （既存 value バインド + lineColor）として下流の HmiTrend が後方互換で 1 本描く。
    //   showGrid / showLegend : グリッド線 / 凡例の表示。**既定 false** ＝ bool optional の規則で
    //     true のときだけ toJson に書き、欠落時 false（fontBold 同型）。
    //   yTickCount  : Y 軸目盛りの分割数。`0` センチネル（= 未指定。HmiTrend が既定へ解決。
    //     `0` は「目盛り 0 本」の正当値を持たない＝pointCount/fontSize 同型）。toJson は `> 0` で書く。
    QList<TrendSeriesData> series;
    bool showGrid = false;
    bool showLegend = false;
    int yTickCount = 0;

    // Task M-A（Phase 10）: Meter（スピードメーター風＝円弧＋針）固有フィールド。設計の正本は
    // Docs/archive/phase10-meter-plan.md「§Task M-A」。すべて optional ＝ isValidJson 必須集合に含めない（後方互換）。
    //   meterMin/hasMeterMin・meterMax/hasMeterMax : スケール範囲（値→角度マッピングの定義域）。
    //     **負値が正当**（例 -20℃）なのでセンチネル不可 → presence フラグ方式（minValue/yMin の前例踏襲）。
    //     **JSON は hasMeterMin キーを作らず meterMin キーの有無で presence を表す**が、
    //     **C++↔QML ブリッジの QVariantMap は既存 min/max・yMin/yMax に倣い明示 bool キーを持つ**。
    //     NumericField の入力 clamp 用 minValue/maxValue とは意味が異なる（Trend が yMin/yMax を
    //     独立に持ったのと同じく Meter は独立した meterMin/meterMax を持つ）。
    //   arcColor / needleColor : 弧色 / 針色。`""` センチネル（= 未指定）。非空のときだけ書く（lineColor 同型）。
    //   tickCount : 目盛りの本数。`0` センチネル（= 未指定。`0` は「目盛り 0 本」の正当値を持たない
    //     ＝pointCount/yTickCount 同型）。toJson は `> 0` のときだけ書く。
    //   unit : 中央数値の単位（例 "km/h"）。`""` センチネル（= 未指定＝単位表示なし）。非空のときだけ書く。
    // 既定外観（既定範囲 0..100 / 既定弧色 / 既定針色 / 既定目盛り数）は描画の唯一の真実である HmiMeter 側に集約する。
    double meterMin = 0.0;
    double meterMax = 0.0;
    bool hasMeterMin = false;
    bool hasMeterMax = false;
    QString arcColor;
    QString needleColor;
    int tickCount = 0;
    QString unit;

    // Task W-A（Phase 11）: SimpleButton（ベゼル無しシンプルボタン）固有フィールド。設計の正本は
    // Docs/archive/phase11-widget-palette-plan.md「§Schema 拡張」。すべて optional ＝ isValidJson 必須集合に
    // 含めない（後方互換）。ON/OFF 状態は既存 checked を再利用する（新規フィールドではない）。
    //   shape / theme : 人間可読な **文字列**（hAlign 同型）。`""` センチネル（= 未指定）。
    //     shape="circle"/"square"（既定 circle へ解決）、theme="light"/"dark"（既定 light へ解決）。
    //     不正値・空は下流（HmiSimpleButton）が既定へフォールバックする。非空のときだけ書く。
    //   accentColor : 差し色。`""` センチネル（= 未指定＝既定の緑へ解決）。"#RRGGBB"/空
    //     （backgroundColor / arcColor 同型）。非空のときだけ書く。ブランド差し替え用。
    //   holdMs : 長押し確定に要する時間[ms]。`0` センチネル（= 未指定。`0` は「長押し 0ms」の
    //     正当値を持たない ＝ fontSize / tickCount 同型）。`> 0` のときだけ書く。
    // 既定外観（既定 circle / light / 緑 / 既定 holdMs）は描画の唯一の真実である HmiSimpleButton 側に集約する。
    QString shape;
    QString theme;
    QString accentColor;
    int holdMs = 0;

    // Task 39: アクション（書き手）/ バインディング（読み手）。いずれも optional 配列で、
    // 空のとき toJson で省略（後方互換）。実行 / 描画への反映は T41 以降で、本タスクでは
    // 型と保存（round-trip）のみ。isValidJson の必須集合には含めない（後方互換）。
    QList<ActionData> actions;
    QList<BindingData> bindings;

    QJsonObject toJson() const;
    static WidgetData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する。Editor の ProjectIo
    // （save: fromVariantMap / load: toVariantMap）と Simulator の ProjectLoader
    // （load: toVariantMap）が共用し、全フィールドの転写を **この Schema 1 箇所**へ
    // 集約する（従来は両 C++ ブリッジに手書きで重複し「縦スライスで一番取りこぼし
    // やすい箇所」だった）。fromVariantMap は QML 由来マップのキー欠落時に、各フィールドの
    // 既定（数値センチネル -1 / enabled は true 等）を fromJson と同じ規則で埋める。
    // actions / bindings は QVariantList of QVariantMap で往復する。QVariantMap は
    // QtCore（QtQml 非依存）なので hmi_schema は引き続き QML を一切 import しない。
    QVariantMap toVariantMap() const;
    static WidgetData fromVariantMap(const QVariantMap &map);

    // JSON が Widget 形式として有効か（id / type / width / height が必要な型で
    // 揃っているか）を判定する。fromJson はキー欠落時に既定値で埋める緩い設計の
    // ため、読込時に「正しい形式かどうか」を判定する際はこちらを使う。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
