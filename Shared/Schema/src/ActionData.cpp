#include "hmi/schema/ActionData.h"

#include <QJsonValue>

namespace hmi::schema {

namespace {
// Task 39（Codex PR #78 [P2]）：value は文字列表現の契約。非文字列（bool/int）も値を
// 失わないよう文字列へ正規化する（VariableData.initial と同じ方針）。
QString jsonValueToString(const QJsonValue &v)
{
    if (v.isString()) {
        return v.toString();
    }
    if (v.isBool()) {
        return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    }
    if (v.isDouble()) {
        const double d = v.toDouble();
        const long long asInt = static_cast<long long>(d);
        if (static_cast<double>(asInt) == d) {
            return QString::number(asInt);
        }
        return QString::number(d);
    }
    return QString();
}
} // namespace

QJsonObject ActionData::toJson() const
{
    QJsonObject obj;
    obj["trigger"] = trigger;
    obj["op"] = op;
    obj["target"] = target;
    // value は setVariable 時のみ意味を持つが、round-trip 安定のため常に書き出す
    // （toggleVariable では空文字）。
    obj["value"] = value;
    return obj;
}

ActionData ActionData::fromJson(const QJsonObject &obj)
{
    ActionData a;
    // trigger は欠落時 "onClick" へ正規化（現状サポートする唯一のトリガ）。
    a.trigger = obj.value("trigger").toString();
    if (a.trigger.isEmpty()) {
        a.trigger = QStringLiteral("onClick");
    }
    a.op = obj.value("op").toString();
    a.target = obj.value("target").toString();
    a.value = jsonValueToString(obj.value("value"));
    return a;
}

bool ActionData::isValidJson(const QJsonObject &obj)
{
    // Task 39（Codex PR #78 [P2]）：op は定義済みの種別（setVariable / toggleVariable）に
    // 限定する（VariableData.type と同じ許可リスト方式）。未知 op を load 成功扱いにすると
    // T41 の実行でアクションだけ無反応になる壊れたプロジェクトを招くため、入口で弾く。
    const QString op = obj.value("op").toString();
    if (op != QStringLiteral("setVariable") && op != QStringLiteral("toggleVariable")) {
        return false;
    }
    // Task 39（Codex PR #78 [P2]）：trigger は欠落時 "onClick" を許容するが、存在する場合は
    // 文字列かつ現在サポートする "onClick" に限定する（onRelease 等の未対応 trigger を
    // load 成功にすると T41 実行で無反応になるため入口で弾く）。
    if (obj.contains("trigger")) {
        const QJsonValue t = obj.value("trigger");
        if (!t.isString() || t.toString() != QStringLiteral("onClick")) {
            return false;
        }
    }
    return obj.value("target").isString() && !obj.value("target").toString().isEmpty();
}

} // namespace hmi::schema
