#include "ProjectLoader.h"

#include "hmi/schema/ConnectionData.h"
#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QFile>
#include <QVariantList>
#include <QVariantMap>

#include <optional>

#include "hmi/schema/VariableData.h"

// Schema 型 → QVariantMap の変換は **Schema 側に集約**した（各型の toVariantMap()）。
// 読み取り専用の Simulator / Runtime は load 方向のみ使う。従来は Editor の ProjectIo と
// 同形のヘルパーをここにも重複保持していたが、転写ロジックは Schema の唯一の真実へ寄せた
//（クラス自体は責務が違うため従来どおり Editor / Simulator で独立保持する）。

ProjectLoader::ProjectLoader(QObject *parent) : QObject(parent) {}

QVariantMap ProjectLoader::load(const QUrl &fileUrl)
{
    using namespace hmi::schema;

    QVariantMap result;
    result.insert(QStringLiteral("ok"), false);
    result.insert(QStringLiteral("widgets"), QVariantList{});
    // 失敗時も widgets と対称に variables の既定（空配列）を入れておく。これがないと
    // QML 側が ok を確認する前に result.variables を読んだとき undefined になる（CodeRabbit 指摘）。
    result.insert(QStringLiteral("variables"), QVariantList{});
    // Phase 7 / MB-2: 接続定義も同様に既定（空配列）を入れておく（Modbus 通信に使う）。
    result.insert(QStringLiteral("connections"), QVariantList{});

    // QML の FileDialog は file:/// 形式の QUrl を返す。toLocalFile で OS パスへ変換する。
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (localPath.isEmpty()) {
        return result;
    }

    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return result;
    }
    const QByteArray data = file.readAll();
    file.close();

    // JSON のパースと妥当性検証（再帰的に Screen / Widget まで）は Shared/Schema を
    // 唯一の真実とする方針に従い、ProjectData::parseValidated に委ねる（Editor の
    // ProjectIo::load と同じ検証パスを共用する。「検証してから fromJson」は Schema 1 箇所に強制）。
    const std::optional<ProjectData> parsed = ProjectData::parseValidated(data);
    if (!parsed) {
        return result;
    }
    const ProjectData proj = *parsed;

    // isValidJson が screens 配列に最低 1 件含まれていることを保証している。
    // MVP では先頭スクリーンのみを表示対象とする。
    const ScreenData screen = proj.screens.first();

    // 全フィールドの転写は WidgetData::toVariantMap（Schema）に集約済み（Editor の
    // ProjectIo::load と同じ変換を共用する）。delegate が読む QVariantMap を 1 行で得る。
    QVariantList widgetsVar;
    widgetsVar.reserve(screen.widgets.size());
    for (const WidgetData &w : screen.widgets) {
        widgetsVar.append(w.toVariantMap());
    }

    QVariantList variablesVar;
    variablesVar.reserve(proj.variables.size());
    for (const VariableData &var : proj.variables) {
        variablesVar.append(var.toVariantMap());
    }

    // Phase 7 / MB-2: 接続定義を QML へ届ける。Modbus マスタ（ModbusController）が
    // 各 variable の source.connection からこの id を引いて host/port/unitId を決める。
    QVariantList connectionsVar;
    connectionsVar.reserve(proj.connections.size());
    for (const ConnectionData &conn : proj.connections) {
        connectionsVar.append(conn.toVariantMap());
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    // Task 39: 変数定義も QML へ届ける（T41 で実行ストアの初期化に使う）。
    result.insert(QStringLiteral("variables"), variablesVar);
    // Phase 7 / MB-2: 接続定義も届ける（Modbus 通信に使う）。
    result.insert(QStringLiteral("connections"), connectionsVar);
    return result;
}
