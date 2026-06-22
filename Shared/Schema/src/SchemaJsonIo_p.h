#pragma once

// Shared/Schema 内部専用の JSON / QVariantMap I/O ヘルパー（private header）。
// 各データ型の toJson / fromJson / toVariantMap / fromVariantMap / isValidJson に散在していた
// 「optional フィールドの省略書き出し」「子型配列の相互変換」「optional 配列の検証」を 1 箇所へ
// 集約し、`>= 0` と `> 0` の取り違えや `.toArray()` ループの手書きコピーといった取りこぼしを防ぐ。
// 公開 API ではないので include/ には置かず src/ に閉じる（hmi_schema は引き続き QML 非依存）。
// 設計規約の正本は .claude/rules/schema-conventions.md。

#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QList>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

namespace hmi::schema::detail {

// --- JSON 書き出し：optional フィールドの「未指定なら省略」規則をヘルパに集約 ---

// optional 文字列：空 = 未指定。空のときキーを書かない（後方互換）。
inline void putString(QJsonObject &obj, const QString &key, const QString &value)
{
    if (!value.isEmpty()) {
        obj[key] = value;
    }
}

// `0` が正当値の int（borderWidth / radius）：-1 センチネル。`>= 0` で書く（0 も保存）。
inline void putSentinelInt(QJsonObject &obj, const QString &key, int value)
{
    if (value >= 0) {
        obj[key] = value;
    }
}

// `0` = 未指定の int（fontSize / pointCount / sampleMs / yTickCount）：`> 0` で書く。
inline void putPositiveInt(QJsonObject &obj, const QString &key, int value)
{
    if (value > 0) {
        obj[key] = value;
    }
}

// real センチネル（opacity）：-1.0 = 未指定。`>= 0.0` で書く（0.0 = 完全透明も保存）。
inline void putSentinelReal(QJsonObject &obj, const QString &key, double value)
{
    if (value >= 0.0) {
        obj[key] = value;
    }
}

// bool optional：既定値（defaultValue）と異なる時だけ書く。enabled（既定 true）の false や
// fontBold（既定 false）の true を保存しつつ、既定値は省略して後方互換を保つ。
inline void putFlag(QJsonObject &obj, const QString &key, bool value, bool defaultValue)
{
    if (value != defaultValue) {
        obj[key] = value;
    }
}

// presence フラグ方式の double（minValue / maxValue / yMin / yMax）：負値が正当なので
// センチネル不可。present のときだけ値を書き、未指定はキー省略で表す（後方互換）。
inline void putPresentReal(QJsonObject &obj, const QString &key, double value, bool present)
{
    if (present) {
        obj[key] = value;
    }
}

// --- 子型配列の相互変換：空のとき省略（後方互換）。子型は toJson / fromJson /
//     toVariantMap / fromVariantMap を持つ前提（schema-conventions の配列規約）---

template <typename T>
void putJsonArray(QJsonObject &obj, const QString &key, const QList<T> &list)
{
    if (list.isEmpty()) {
        return;
    }
    QJsonArray arr;
    for (const T &item : list) {
        arr.append(item.toJson());
    }
    obj[key] = arr;
}

template <typename T>
QList<T> jsonArrayToList(const QJsonValue &value)
{
    QList<T> out;
    const QJsonArray arr = value.toArray();
    out.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        out.append(T::fromJson(v.toObject()));
    }
    return out;
}

template <typename T>
QVariantList listToVariantList(const QList<T> &list)
{
    QVariantList out;
    out.reserve(list.size());
    for (const T &item : list) {
        out.append(item.toVariantMap());
    }
    return out;
}

template <typename T>
QList<T> variantListToList(const QVariant &value)
{
    QList<T> out;
    const QVariantList in = value.toList();
    out.reserve(in.size());
    for (const QVariant &v : in) {
        out.append(T::fromVariantMap(v.toMap()));
    }
    return out;
}

// optional な子型配列の検証：不在は後方互換で許容。存在するなら配列かつ各要素が
// 子型 isValidJson を満たすことを要求する（不正な要素を load の入口で弾く）。
template <typename T>
bool isValidOptionalArray(const QJsonObject &obj, const QString &key)
{
    if (!obj.contains(key)) {
        return true;
    }
    if (!obj.value(key).isArray()) {
        return false;
    }
    const QJsonArray arr = obj.value(key).toArray();
    for (const QJsonValue &v : arr) {
        if (!v.isObject() || !T::isValidJson(v.toObject())) {
            return false;
        }
    }
    return true;
}

} // namespace hmi::schema::detail
