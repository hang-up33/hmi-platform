#pragma once

#include <QJsonObject>
#include <QString>

namespace hmi::schema {

// Task 39: Widget のデータバインディング定義（「読み手」）。指定 property を変数に
// 追従させる。WidgetData に optional 配列で持つ。読み取り専用の Simulator / Runtime は
// 保存 JSON のこの定義だけから「変数変化 → property 変化」を再現する（T41/T43 の前提）。
//   property : "visible" / "backgroundColor" / "text" 等（追従させる Widget プロパティ名）
//   variable : 追従元の変数名
struct BindingData {
    QString property;
    QString variable;

    QJsonObject toJson() const;
    static BindingData fromJson(const QJsonObject &obj);

    // property と variable が非空なら有効。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
