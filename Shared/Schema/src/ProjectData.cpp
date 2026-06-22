#include "hmi/schema/ProjectData.h"

#include "SchemaJsonIo_p.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonValue>

namespace hmi::schema {

using namespace hmi::schema::detail;

QJsonObject ProjectData::toJson() const
{
    // screens は（空でも）必須キーとして常に書き出す。variables / connections は
    // optional ＝空のとき省略（putJsonArray が後方互換の省略規則を担う）。
    QJsonArray arr;
    for (const auto &s : screens) {
        arr.append(s.toJson());
    }
    QJsonObject obj;
    obj["project"] = project;
    obj["screens"] = arr;
    putJsonArray(obj, "variables", variables);   // Task 39
    putJsonArray(obj, "connections", connections); // Phase 7 / MB-1
    return obj;
}

ProjectData ProjectData::fromJson(const QJsonObject &obj)
{
    ProjectData p;
    p.project = obj.value("project").toString();
    p.screens = jsonArrayToList<ScreenData>(obj.value("screens"));
    // Task 39 / MB-1: 変数定義・接続定義配列（欠落時は空配列）。
    p.variables = jsonArrayToList<VariableData>(obj.value("variables"));
    p.connections = jsonArrayToList<ConnectionData>(obj.value("connections"));
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
    // Task 39 / MB-1（Codex PR #78 [P2]）：variables / connections は optional だが、
    // **存在する場合は**配列で各要素が子型として有効であることを要求する（不在は後方互換で
    // 許容）。これで type:"float" の変数や id 欠落の接続を含む JSON を load の入口で弾ける。
    return isValidOptionalArray<VariableData>(obj, "variables")
        && isValidOptionalArray<ConnectionData>(obj, "connections");
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
