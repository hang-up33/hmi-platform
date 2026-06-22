#include "hmi/schema/WidgetData.h"

#include "SchemaJsonIo_p.h"

namespace hmi::schema {

using namespace hmi::schema::detail;

QJsonObject WidgetData::toJson() const
{
    // 必須フィールドは常に書き出す。optional フィールドの「未指定なら省略」規則
    //（センチネル / presence フラグ / bool 既定値）は put* ヘルパーに集約済み
    //（設計の正本は .claude/rules/schema-conventions.md・各 phase plan）。
    QJsonObject obj;
    obj["id"] = id;
    obj["type"] = type;
    obj["x"] = x;
    obj["y"] = y;
    obj["width"] = width;
    obj["height"] = height;
    putString(obj, "text", text);
    putString(obj, "tag", tag);
    // Task 28/31/33/34: 静的スタイル（色・フォント・ボーダー・配置・不透明度）。
    putString(obj, "backgroundColor", backgroundColor);
    putString(obj, "textColor", textColor);
    putPositiveInt(obj, "fontSize", fontSize);
    putString(obj, "borderColor", borderColor);
    putSentinelInt(obj, "borderWidth", borderWidth);
    putSentinelInt(obj, "radius", radius);
    putFlag(obj, "fontBold", fontBold, false);
    putFlag(obj, "fontItalic", fontItalic, false);
    putString(obj, "fontFamily", fontFamily);
    putString(obj, "hAlign", hAlign);
    putString(obj, "vAlign", vAlign);
    putSentinelReal(obj, "opacity", opacity);
    // Task 42: 状態別スタイル（enabled は既定 true ＝ false のとき書く）。
    putFlag(obj, "enabled", enabled, true);
    putFlag(obj, "checkable", checkable, false);
    putFlag(obj, "checked", checked, false);
    // Task 54: 数値範囲（presence フラグ方式＝負値が正当なのでセンチネル不可）。
    putPresentReal(obj, "minValue", minValue, hasMinValue);
    putPresentReal(obj, "maxValue", maxValue, hasMaxValue);
    // Task T-A / 8B-A（Phase 8 / 8-B）: Trend 固有フィールド。yMin/yMax は presence フラグ方式
    //（**hasYMin/hasYMax という JSON キーは作らず** yMin/yMax キーの有無で presence を表す）。
    putPositiveInt(obj, "pointCount", pointCount);
    putPresentReal(obj, "yMin", yMin, hasYMin);
    putPresentReal(obj, "yMax", yMax, hasYMax);
    putString(obj, "lineColor", lineColor);
    putPositiveInt(obj, "sampleMs", sampleMs);
    putJsonArray(obj, "series", series);
    putFlag(obj, "showGrid", showGrid, false);
    putFlag(obj, "showLegend", showLegend, false);
    putPositiveInt(obj, "yTickCount", yTickCount);
    // Task 39: アクション（書き手）/ バインディング（読み手）。空のとき省略（後方互換）。
    putJsonArray(obj, "actions", actions);
    putJsonArray(obj, "bindings", bindings);
    return obj;
}

WidgetData WidgetData::fromJson(const QJsonObject &obj)
{
    WidgetData w;
    w.id = obj.value("id").toString();
    w.type = obj.value("type").toString();
    w.x = obj.value("x").toInt();
    w.y = obj.value("y").toInt();
    w.width = obj.value("width").toInt();
    w.height = obj.value("height").toInt();
    w.text = obj.value("text").toString();
    w.tag = obj.value("tag").toString();
    // Task 28: スタイルはキー欠落時に既定値（空 / 0 = 未指定）で埋める緩い設計。
    w.backgroundColor = obj.value("backgroundColor").toString();
    w.textColor = obj.value("textColor").toString();
    w.fontSize = obj.value("fontSize").toInt();
    // Task 31: 数値は **`toInt(-1)`**（欠落時 -1 = 未指定）で読む。`toInt()`〔欠落時 0〕を
    // コピペすると「キー欠落 = ボーダーなし（0）」と誤解され、HmiButton の既定値に
    // フォールバックしなくなる。色は欠落時に空文字（= 未指定）。
    w.borderColor = obj.value("borderColor").toString();
    w.borderWidth = obj.value("borderWidth").toInt(-1);
    w.radius = obj.value("radius").toInt(-1);
    // Task 33: bool は欠落時 false（toBool() の既定）。fontFamily は欠落時 空文字（= 未指定）。
    w.fontBold = obj.value("fontBold").toBool();
    w.fontItalic = obj.value("fontItalic").toBool();
    w.fontFamily = obj.value("fontFamily").toString();
    // Task 34: 配置は欠落時 空文字（= 未指定）。opacity は **`toDouble(-1)`**（欠落時
    // -1 = 未指定）で読む。`toDouble()`〔欠落時 0.0〕にすると「キー欠落 = 完全透明」と
    // 誤解され、HmiButton の既定（1.0）にフォールバックしなくなる（borderWidth と同じ罠）。
    w.hAlign = obj.value("hAlign").toString();
    w.vAlign = obj.value("vAlign").toString();
    w.opacity = obj.value("opacity").toDouble(-1.0);
    // Task 42: 状態別スタイル。**enabled は欠落時 true**（`toBool(true)`。`toBool()` の既定
    // false をコピペすると旧 JSON〔enabled キー無し〕が disabled 扱いになる）。
    // checkable / checked は欠落時 false。
    w.enabled = obj.value("enabled").toBool(true);
    w.checkable = obj.value("checkable").toBool();
    w.checked = obj.value("checked").toBool();
    // Task 54: 数値範囲。**presence は `obj.contains()` で判定**（数値センチネル不可：負値が
    // 正当なので「キーの有無」が唯一の未指定判定）。値はキーがある時のみ toDouble() で読む。
    w.hasMinValue = obj.contains("minValue");
    w.minValue = obj.value("minValue").toDouble();
    w.hasMaxValue = obj.contains("maxValue");
    w.maxValue = obj.value("maxValue").toDouble();
    // Task T-A（Phase 8）: Trend 固有フィールド。pointCount / sampleMs は **`toInt(0)`**
    // （欠落時 0 = 未指定。`0` センチネル）。yMin / yMax は **presence を `obj.contains()` で
    // 判定**（数値センチネル不可：負値が正当なので「キーの有無」が唯一の未指定判定。minValue/
    // maxValue と同じ）。値はキーがある時のみ toDouble() で読む。lineColor は欠落時 空文字（= 未指定）。
    w.pointCount = obj.value("pointCount").toInt(0);
    w.hasYMin = obj.contains("yMin");
    w.yMin = obj.value("yMin").toDouble();
    w.hasYMax = obj.contains("yMax");
    w.yMax = obj.value("yMax").toDouble();
    w.lineColor = obj.value("lineColor").toString();
    w.sampleMs = obj.value("sampleMs").toInt(0);
    // Task 8B-A（Phase 8-B）: Trend 拡張。series 配列（欠落時は空配列＝暗黙単系列）。
    // showGrid / showLegend は欠落時 false（toBool() の既定）。yTickCount は **`toInt(0)`**
    // （欠落時 0 = 未指定。`0` センチネル）。
    w.series = jsonArrayToList<TrendSeriesData>(obj.value("series"));
    w.showGrid = obj.value("showGrid").toBool();
    w.showLegend = obj.value("showLegend").toBool();
    w.yTickCount = obj.value("yTickCount").toInt(0);
    // Task 39: アクション / バインディング配列（欠落時は空配列）。
    w.actions = jsonArrayToList<ActionData>(obj.value("actions"));
    w.bindings = jsonArrayToList<BindingData>(obj.value("bindings"));
    return w;
}

QVariantMap WidgetData::toVariantMap() const
{
    // QML（delegate）が読む形へ全フィールドを素通しで詰める。既定外観への
    // フォールバックは描画側（HmiButton の resolved*）が持つため、ここでは
    // 未指定値（空文字 / 0 / -1）もそのまま渡す。従来 ProjectIo::load /
    // ProjectLoader::load が個別に組んでいたマップを Schema 1 箇所へ集約したもの。
    QVariantMap m;
    m.insert(QStringLiteral("id"), id);
    m.insert(QStringLiteral("type"), type);
    m.insert(QStringLiteral("x"), x);
    m.insert(QStringLiteral("y"), y);
    m.insert(QStringLiteral("width"), width);
    m.insert(QStringLiteral("height"), height);
    m.insert(QStringLiteral("text"), text);
    m.insert(QStringLiteral("tag"), tag);
    m.insert(QStringLiteral("backgroundColor"), backgroundColor);
    m.insert(QStringLiteral("textColor"), textColor);
    m.insert(QStringLiteral("fontSize"), fontSize);
    m.insert(QStringLiteral("borderColor"), borderColor);
    m.insert(QStringLiteral("borderWidth"), borderWidth);
    m.insert(QStringLiteral("radius"), radius);
    m.insert(QStringLiteral("fontBold"), fontBold);
    m.insert(QStringLiteral("fontItalic"), fontItalic);
    m.insert(QStringLiteral("fontFamily"), fontFamily);
    m.insert(QStringLiteral("hAlign"), hAlign);
    m.insert(QStringLiteral("vAlign"), vAlign);
    m.insert(QStringLiteral("opacity"), opacity);
    m.insert(QStringLiteral("enabled"), enabled);
    m.insert(QStringLiteral("checkable"), checkable);
    m.insert(QStringLiteral("checked"), checked);
    // Task 54: 数値範囲は値（minValue/maxValue）と presence（hasMinValue/hasMaxValue）を
    // 対で転写する。QML 側は hasMinValue を見て未指定（has*=false）を判定する。
    m.insert(QStringLiteral("minValue"), minValue);
    m.insert(QStringLiteral("maxValue"), maxValue);
    m.insert(QStringLiteral("hasMinValue"), hasMinValue);
    m.insert(QStringLiteral("hasMaxValue"), hasMaxValue);
    // Task T-A（Phase 8）: Trend 固有フィールド。pointCount / sampleMs / lineColor は素通し。
    // yMin / yMax は **min/max と同じく値 + presence（hasYMin/hasYMax）を対で転写**する。
    // QML 側は hasYMin を見て未指定（has*=false）を判定する（minValue/maxValue と同じ流儀。
    // 注：JSON 表現〔toJson/fromJson〕は presence をキーの有無で表すが、C++↔QML ブリッジの
    // QVariantMap では既存 min/max に倣い明示 bool キーを持つ）。
    m.insert(QStringLiteral("pointCount"), pointCount);
    m.insert(QStringLiteral("lineColor"), lineColor);
    m.insert(QStringLiteral("sampleMs"), sampleMs);
    m.insert(QStringLiteral("yMin"), yMin);
    m.insert(QStringLiteral("yMax"), yMax);
    m.insert(QStringLiteral("hasYMin"), hasYMin);
    m.insert(QStringLiteral("hasYMax"), hasYMax);
    // Task 8B-A（Phase 8-B）: Trend 拡張。series は QVariantList of QVariantMap で往復
    // （actions/bindings 同型）。showGrid/showLegend/yTickCount は素通し。
    m.insert(QStringLiteral("series"), listToVariantList(series));
    m.insert(QStringLiteral("showGrid"), showGrid);
    m.insert(QStringLiteral("showLegend"), showLegend);
    m.insert(QStringLiteral("yTickCount"), yTickCount);
    m.insert(QStringLiteral("actions"), listToVariantList(actions));
    m.insert(QStringLiteral("bindings"), listToVariantList(bindings));
    return m;
}

WidgetData WidgetData::fromVariantMap(const QVariantMap &map)
{
    // QML（Canvas の snapshotModel）由来マップから読む。キー欠落時の既定は fromJson と
    // 同じ規則：**`0` が正当値の数値（borderWidth / radius / opacity）は -1 / -1.0 を
    // 既定**にして「未指定」を区別し（`.toInt()` 既定 0 を使うと「ボーダーなし」と誤読）、
    // **enabled は既定 true**（`.toBool()` 既定 false を使うと旧マップが disabled 扱いに）。
    WidgetData w;
    w.id = map.value(QStringLiteral("id")).toString();
    w.type = map.value(QStringLiteral("type")).toString();
    w.x = map.value(QStringLiteral("x")).toInt();
    w.y = map.value(QStringLiteral("y")).toInt();
    w.width = map.value(QStringLiteral("width")).toInt();
    w.height = map.value(QStringLiteral("height")).toInt();
    w.text = map.value(QStringLiteral("text")).toString();
    w.tag = map.value(QStringLiteral("tag")).toString();
    w.backgroundColor = map.value(QStringLiteral("backgroundColor")).toString();
    w.textColor = map.value(QStringLiteral("textColor")).toString();
    w.fontSize = map.value(QStringLiteral("fontSize")).toInt();
    w.borderColor = map.value(QStringLiteral("borderColor")).toString();
    w.borderWidth = map.value(QStringLiteral("borderWidth"), -1).toInt();
    w.radius = map.value(QStringLiteral("radius"), -1).toInt();
    w.fontBold = map.value(QStringLiteral("fontBold")).toBool();
    w.fontItalic = map.value(QStringLiteral("fontItalic")).toBool();
    w.fontFamily = map.value(QStringLiteral("fontFamily")).toString();
    w.hAlign = map.value(QStringLiteral("hAlign")).toString();
    w.vAlign = map.value(QStringLiteral("vAlign")).toString();
    w.opacity = map.value(QStringLiteral("opacity"), -1.0).toDouble();
    w.enabled = map.value(QStringLiteral("enabled"), true).toBool();
    w.checkable = map.value(QStringLiteral("checkable")).toBool();
    w.checked = map.value(QStringLiteral("checked")).toBool();
    // Task 54: 数値範囲は presence（hasMinValue/hasMaxValue）と値（minValue/maxValue）を
    // 対で読む。presence はキー欠落時 false。値は対応 presence のとき意味を持つ。
    w.hasMinValue = map.value(QStringLiteral("hasMinValue")).toBool();
    w.minValue = map.value(QStringLiteral("minValue")).toDouble();
    w.hasMaxValue = map.value(QStringLiteral("hasMaxValue")).toBool();
    w.maxValue = map.value(QStringLiteral("maxValue")).toDouble();
    // Task T-A（Phase 8）: Trend 固有フィールド。pointCount / sampleMs は欠落時 0（= 未指定）。
    // 負値が来てもクランプしない（fontSize 前例と同じ＝下流の HmiTrend が `> 0` のときだけ採用し、
    // `0`/負はいずれも既定へ解決する。toJson が `> 0` でしか書かないため JSON には負値は残らない）。
    // yMin / yMax は **min/max と同じく presence（hasYMin/hasYMax）と値を対で読む**（presence は
    // キー欠落時 false）。lineColor は欠落時 空文字（= 未指定）。
    w.pointCount = map.value(QStringLiteral("pointCount")).toInt();
    w.hasYMin = map.value(QStringLiteral("hasYMin")).toBool();
    w.yMin = map.value(QStringLiteral("yMin")).toDouble();
    w.hasYMax = map.value(QStringLiteral("hasYMax")).toBool();
    w.yMax = map.value(QStringLiteral("yMax")).toDouble();
    w.lineColor = map.value(QStringLiteral("lineColor")).toString();
    w.sampleMs = map.value(QStringLiteral("sampleMs")).toInt();
    // Task 8B-A（Phase 8-B）: Trend 拡張。series はリストから子型を読む。
    // showGrid/showLegend は欠落時 false、yTickCount は欠落時 0（= 未指定）。
    w.series = variantListToList<TrendSeriesData>(map.value(QStringLiteral("series")));
    w.showGrid = map.value(QStringLiteral("showGrid")).toBool();
    w.showLegend = map.value(QStringLiteral("showLegend")).toBool();
    w.yTickCount = map.value(QStringLiteral("yTickCount")).toInt();
    w.actions = variantListToList<ActionData>(map.value(QStringLiteral("actions")));
    w.bindings = variantListToList<BindingData>(map.value(QStringLiteral("bindings")));
    return w;
}

bool WidgetData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("id").isString()
        || !obj.value("type").isString()
        || !obj.value("width").isDouble()
        || !obj.value("height").isDouble()) {
        return false;
    }
    // Task 39 / 8B-A（Codex PR #78 [P2]）：actions / bindings / series は optional だが、
    // **存在する場合は**配列で各要素が子型として有効であることを要求する（不在は後方互換で
    // 許容）。これで target / variable 欠落の不正な要素を load の入口で弾ける。
    return isValidOptionalArray<ActionData>(obj, "actions")
        && isValidOptionalArray<BindingData>(obj, "bindings")
        && isValidOptionalArray<TrendSeriesData>(obj, "series");
}

} // namespace hmi::schema
