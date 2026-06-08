#include "hmi/schema/WidgetData.h"

#include <QJsonArray>

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
