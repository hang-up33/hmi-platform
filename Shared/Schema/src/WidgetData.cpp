#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QVariantList>

namespace hmi::schema {

QJsonObject WidgetData::toJson() const
{
    QJsonObject obj;
    obj["id"] = id;
    obj["type"] = type;
    obj["x"] = x;
    obj["y"] = y;
    obj["width"] = width;
    obj["height"] = height;
    if (!text.isEmpty()) {
        obj["text"] = text;
    }
    if (!tag.isEmpty()) {
        obj["tag"] = tag;
    }
    // Task 28: スタイルは既定値（空 / 0 = 未指定）のとき省略して書き出す。
    // これにより Phase 1〜3-B で保存した旧 JSON と同形を保ち、後方互換になる。
    if (!backgroundColor.isEmpty()) {
        obj["backgroundColor"] = backgroundColor;
    }
    if (!textColor.isEmpty()) {
        obj["textColor"] = textColor;
    }
    if (fontSize > 0) {
        obj["fontSize"] = fontSize;
    }
    // Task 31: ボーダー＋角丸。色は空のとき省略。数値は **`>= 0`** で書き出す
    // （fontSize の `> 0` と違い `0` も明示的な値〔ボーダーなし / 角丸なし〕として保存する）。
    // 未指定のセンチネル `-1` のときだけ省略し、旧 JSON と後方互換を保つ。
    if (!borderColor.isEmpty()) {
        obj["borderColor"] = borderColor;
    }
    if (borderWidth >= 0) {
        obj["borderWidth"] = borderWidth;
    }
    if (radius >= 0) {
        obj["radius"] = radius;
    }
    // Task 33: フォント詳細。bool は **既定値（false）と異なる時だけ書く**（true のみ書き、
    // false は省略）。一律 true 書き出しでも本フィールドは既定 false なので等価だが、
    // 既定 true のフラグ（後続 Task の enabled 等）と規則を揃えるためこの形にする。
    // fontFamily は空（= 未指定）のとき省略し、旧 JSON と後方互換を保つ。
    if (fontBold) {
        obj["fontBold"] = fontBold;
    }
    if (fontItalic) {
        obj["fontItalic"] = fontItalic;
    }
    if (!fontFamily.isEmpty()) {
        obj["fontFamily"] = fontFamily;
    }
    // Task 34: 配置は空（= 未指定）のとき省略。opacity は **`>= 0.0`** で書き出す
    // （borderWidth の int センチネルと同型の real 版。`0.0` = 完全透明も明示値として
    // 保存し、未指定の `-1.0` のときだけ省略する）。後方互換のため旧 JSON は据え置き。
    if (!hAlign.isEmpty()) {
        obj["hAlign"] = hAlign;
    }
    if (!vAlign.isEmpty()) {
        obj["vAlign"] = vAlign;
    }
    if (opacity >= 0.0) {
        obj["opacity"] = opacity;
    }
    // Task 42: 状態別スタイル。**enabled は既定 true なので false のとき書く**（一律 true
    // 書き出しだと false が保存されず disabled の round-trip が壊れる）。checkable / checked は
    // 既定 false なので true のとき書く。いずれも未指定（既定値）のとき省略し後方互換を保つ。
    if (!enabled) {
        obj["enabled"] = enabled;
    }
    if (checkable) {
        obj["checkable"] = checkable;
    }
    if (checked) {
        obj["checked"] = checked;
    }
    // Task 54: 数値範囲（NumericField の clamp 用）。**負値が正当**なのでセンチネル不可、
    // presence フラグ方式で表す：hasMinValue / hasMaxValue が true のときだけ minValue /
    // maxValue を書く（未指定はキー省略＝後方互換。旧 JSON は min/max キーを持たない）。
    if (hasMinValue) {
        obj["minValue"] = minValue;
    }
    if (hasMaxValue) {
        obj["maxValue"] = maxValue;
    }
    // Task T-A（Phase 8）: Trend 固有フィールド。pointCount / sampleMs は **`> 0`** で書く
    // （fontSize と同型の `0` センチネル＝0 は未指定）。yMin / yMax は **負値が正当**なので
    // presence フラグ方式：hasYMin / hasYMax が true のときだけ書く（未指定はキー省略＝
    // 後方互換。minValue/maxValue と同じ）。lineColor は空（= 未指定）のとき省略。
    // **hasYMin / hasYMax という JSON キーは作らない**（presence は yMin/yMax キーの有無で表す）。
    if (pointCount > 0) {
        obj["pointCount"] = pointCount;
    }
    if (hasYMin) {
        obj["yMin"] = yMin;
    }
    if (hasYMax) {
        obj["yMax"] = yMax;
    }
    if (!lineColor.isEmpty()) {
        obj["lineColor"] = lineColor;
    }
    if (sampleMs > 0) {
        obj["sampleMs"] = sampleMs;
    }
    // Task 39: アクション / バインディングは optional 配列。空のとき省略（後方互換）。
    if (!actions.isEmpty()) {
        QJsonArray actionsArr;
        for (const ActionData &a : actions) {
            actionsArr.append(a.toJson());
        }
        obj["actions"] = actionsArr;
    }
    if (!bindings.isEmpty()) {
        QJsonArray bindingsArr;
        for (const BindingData &b : bindings) {
            bindingsArr.append(b.toJson());
        }
        obj["bindings"] = bindingsArr;
    }
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
    // Task 39: アクション / バインディング配列（欠落時は空配列）。
    const QJsonArray actionsArr = obj.value("actions").toArray();
    for (const QJsonValue &v : actionsArr) {
        w.actions.append(ActionData::fromJson(v.toObject()));
    }
    const QJsonArray bindingsArr = obj.value("bindings").toArray();
    for (const QJsonValue &v : bindingsArr) {
        w.bindings.append(BindingData::fromJson(v.toObject()));
    }
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
    QVariantList actionsVar;
    actionsVar.reserve(actions.size());
    for (const ActionData &a : actions) {
        actionsVar.append(a.toVariantMap());
    }
    m.insert(QStringLiteral("actions"), actionsVar);
    QVariantList bindingsVar;
    bindingsVar.reserve(bindings.size());
    for (const BindingData &b : bindings) {
        bindingsVar.append(b.toVariantMap());
    }
    m.insert(QStringLiteral("bindings"), bindingsVar);
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
    const QVariantList actionsVar = map.value(QStringLiteral("actions")).toList();
    for (const QVariant &v : actionsVar) {
        w.actions.append(ActionData::fromVariantMap(v.toMap()));
    }
    const QVariantList bindingsVar = map.value(QStringLiteral("bindings")).toList();
    for (const QVariant &v : bindingsVar) {
        w.bindings.append(BindingData::fromVariantMap(v.toMap()));
    }
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
    // Task 39（Codex PR #78 [P2]）：actions / bindings は optional だが、**存在する場合は**
    // 配列で各要素が子型として有効であることを要求する（不在は後方互換で許容）。これで
    // target / variable 欠落の不正アクション・バインディングを load の入口で弾ける。
    if (obj.contains("actions")) {
        if (!obj.value("actions").isArray()) {
            return false;
        }
        const QJsonArray actionsArr = obj.value("actions").toArray();
        for (const QJsonValue &v : actionsArr) {
            if (!v.isObject() || !ActionData::isValidJson(v.toObject())) {
                return false;
            }
        }
    }
    if (obj.contains("bindings")) {
        if (!obj.value("bindings").isArray()) {
            return false;
        }
        const QJsonArray bindingsArr = obj.value("bindings").toArray();
        for (const QJsonValue &v : bindingsArr) {
            if (!v.isObject() || !BindingData::isValidJson(v.toObject())) {
                return false;
            }
        }
    }
    return true;
}

} // namespace hmi::schema
