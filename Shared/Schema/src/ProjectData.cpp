#include "hmi/schema/ProjectData.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonValue>

namespace hmi::schema {

QJsonObject ProjectData::toJson() const
{
    QJsonArray arr;
    for (const auto &s : screens) {
        arr.append(s.toJson());
    }
    QJsonObject obj;
    obj["project"] = project;
    obj["screens"] = arr;
    // Task 39: 変数定義は optional。空のとき省略（後方互換）。
    if (!variables.isEmpty()) {
        QJsonArray varsArr;
        for (const VariableData &v : variables) {
            varsArr.append(v.toJson());
        }
        obj["variables"] = varsArr;
    }
    // Phase 7 / MB-1: 接続定義も optional。空のとき省略（後方互換）。
    if (!connections.isEmpty()) {
        QJsonArray connArr;
        for (const ConnectionData &c : connections) {
            connArr.append(c.toJson());
        }
        obj["connections"] = connArr;
    }
    return obj;
}

ProjectData ProjectData::fromJson(const QJsonObject &obj)
{
    ProjectData p;
    p.project = obj.value("project").toString();
    const QJsonArray arr = obj.value("screens").toArray();
    p.screens.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        p.screens.append(ScreenData::fromJson(v.toObject()));
    }
    // Task 39: 変数定義配列（欠落時は空配列）。
    const QJsonArray varsArr = obj.value("variables").toArray();
    for (const QJsonValue &v : varsArr) {
        p.variables.append(VariableData::fromJson(v.toObject()));
    }
    // Phase 7 / MB-1: 接続定義配列（欠落時は空配列）。
    const QJsonArray connArr = obj.value("connections").toArray();
    for (const QJsonValue &c : connArr) {
        p.connections.append(ConnectionData::fromJson(c.toObject()));
    }
    return p;
}

bool ProjectData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("screens").isArray()) {
        return false;
    }
    const QJsonArray arr = obj.value("screens").toArray();
    if (arr.isEmpty()) {
        return false;
    }
    for (const QJsonValue &v : arr) {
        if (!v.isObject() || !ScreenData::isValidJson(v.toObject())) {
            return false;
        }
    }
    // Task 39（Codex PR #78 [P2]）：variables は optional だが、**存在する場合は**配列で
    // 各要素が VariableData として有効であることを要求する（不在は後方互換で許容）。
    // これで type:"float" や非 object の変数を含む JSON を load の入口で弾ける。
    if (obj.contains("variables")) {
        if (!obj.value("variables").isArray()) {
            return false;
        }
        const QJsonArray vars = obj.value("variables").toArray();
        for (const QJsonValue &v : vars) {
            if (!v.isObject() || !VariableData::isValidJson(v.toObject())) {
                return false;
            }
        }
    }
    // Phase 7 / MB-1: connections も optional。存在する場合は配列で各要素が
    // ConnectionData として有効（id 非空）であることを要求する（不在は後方互換で許容）。
    if (obj.contains("connections")) {
        if (!obj.value("connections").isArray()) {
            return false;
        }
        const QJsonArray conns = obj.value("connections").toArray();
        for (const QJsonValue &c : conns) {
            if (!c.isObject() || !ConnectionData::isValidJson(c.toObject())) {
                return false;
            }
        }
    }
    return true;
}

std::optional<ProjectData> ProjectData::parseValidated(const QByteArray &json)
{
    QJsonParseError parseErr{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parseErr);
    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        return std::nullopt;
    }
    const QJsonObject root = doc.object();
    if (!isValidJson(root)) {
        return std::nullopt;
    }
    return fromJson(root);
}

} // namespace hmi::schema
