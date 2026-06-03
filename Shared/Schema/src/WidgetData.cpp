#include "hmi/schema/WidgetData.h"

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
    return w;
}

bool WidgetData::isValidJson(const QJsonObject &obj)
{
    return obj.value("id").isString()
        && obj.value("type").isString()
        && obj.value("width").isDouble()
        && obj.value("height").isDouble();
}

} // namespace hmi::schema
