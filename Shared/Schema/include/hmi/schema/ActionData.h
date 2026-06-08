#pragma once

#include <QJsonObject>
#include <QString>

namespace hmi::schema {

// Task 39: Widget のアクション定義（「書き手」）。トリガ発火時に変数を操作する。
// WidgetData に optional 配列で持つ。実行（変数更新）は Simulator / Runtime（T41）。
//   trigger : "onClick"（将来 "onPress" 等に拡張）
//   op      : "setVariable"（value を target へ代入） / "toggleVariable"（bool 反転）
//   target  : 対象の変数名
//   value   : setVariable 時の値（文字列表現。toggleVariable では未使用）
struct ActionData {
    QString trigger;
    QString op;
    QString target;
    QString value;

    QJsonObject toJson() const;
    static ActionData fromJson(const QJsonObject &obj);

    // op と target が非空なら有効（trigger 既定は "onClick"）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
