#include "ProjectIo.h"

#include "hmi/schema/ConnectionData.h"
#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/SourceData.h"
#include "hmi/schema/VariableData.h"
#include "hmi/schema/WidgetData.h"

#include <QFile>
#include <QFileInfo>
#include <QDebug>
#include <QHash>
#include <QJsonDocument>
#include <QMetaType>
#include <QSaveFile>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <optional>

// QVariantMap（QML 由来）↔ Schema 型の相互変換は **Schema 側に集約**した（各型の
// toVariantMap() / fromVariantMap()）。アクション / バインディングは WidgetData の
// 変換が内部で面倒を見るため、ここでは widget と変数定義を回すだけでよい。
// 従来は Editor / Simulator の C++ ブリッジに同形ヘルパーを重複保持していた。

ProjectIo::ProjectIo(QObject *parent) : QObject(parent) {}

bool ProjectIo::save(const QUrl &fileUrl,
                     const QString &projectName,
                     const QString &screenName,
                     const QVariantList &widgets,
                     const QVariantList &variables)
{
    using namespace hmi::schema;

    ProjectData proj;
    proj.project = projectName;
    // Task 39: Project レベルの変数定義（optional。空可）。
    // Phase 7 / MB-1: QML 側の variable.source は接続詳細（connection / host / port / unitId /
    // reg / address / poll）をインラインで持つ。ここで connections[] へ dedup 集約し、
    // variable.source からは接続詳細（host/port/unitId）を落として {connection,reg,address,poll}
    // に絞る（計画書の正準＝connections[] 参照方式の JSON に round-trip する）。
    proj.variables.reserve(variables.size());
    QHash<QString, int> connIndexById;  // connection id → proj.connections の index
    for (const QVariant &v : variables) {
        const QVariantMap vmap = v.toMap();
        VariableData var = VariableData::fromVariantMap(vmap);
        const QVariant sourceVar = vmap.value(QStringLiteral("source"));
        if (sourceVar.typeId() == QMetaType::QVariantMap && var.source) {
            // 不完全 / 不正な source（connection 空・reg 不正など）は **内部変数へ戻す**
            // （= source を落とす）。これをしないと SourceData::isValidJson が弾く不正 JSON
            // が書き出され、再読込で parseValidated に拒否される（CodeRabbit PR #119 [重大]）。
            if (!SourceData::isValidJson(var.source->toJson())) {
                var.source = std::nullopt;
            } else {
                const QVariantMap smap = sourceVar.toMap();
                // 接続詳細から ConnectionData を組み、connections[] に dedup 登録する。
                ConnectionData conn;
                conn.id = var.source->connection;  // 有効＝非空が保証される。
                const QString proto = smap.value(QStringLiteral("proto")).toString();
                conn.proto = proto.isEmpty() ? QStringLiteral("modbusTcp") : proto;
                conn.host = smap.value(QStringLiteral("host")).toString();
                conn.port = smap.value(QStringLiteral("port"), 502).toInt();
                conn.unitId = smap.value(QStringLiteral("unitId"), 1).toInt();
                // 同一 id は **最初の定義を採用**（connections[] は id で一意）。MB-1 は
                // 接続 id を "plc1" 固定なので実際には 1 件だが、将来複数変数が同 id で
                // 異なる host/port/unitId を持つ source を定義しうる。その場合は最初の定義を
                // 使い後続を捨てるが、設定ミスを隠さないよう不一致を警告する（CodeRabbit PR #119）。
                if (!connIndexById.contains(conn.id)) {
                    connIndexById.insert(conn.id, proj.connections.size());
                    proj.connections.append(conn);
                } else {
                    const ConnectionData &existing = proj.connections.at(connIndexById.value(conn.id));
                    if (existing.host != conn.host || existing.port != conn.port
                        || existing.unitId != conn.unitId || existing.proto != conn.proto) {
                        qWarning() << "ProjectIo::save: connection id" << conn.id
                                   << "に異なる接続詳細が複数定義されています。最初の定義を採用します。";
                    }
                }
            }
        }
        proj.variables.append(var);
    }

    ScreenData screen;
    screen.name = screenName;
    screen.widgets.reserve(widgets.size());

    // 全フィールドの転写は WidgetData::fromVariantMap（Schema）に集約済み。スタイル属性を
    // 増やしてもここは変更不要（従来は属性ごとに手書きコピーが必要な「取りこぼしやすい箇所」だった）。
    for (const QVariant &v : widgets) {
        screen.widgets.append(WidgetData::fromVariantMap(v.toMap()));
    }

    proj.screens.append(screen);

    const QJsonDocument doc(proj.toJson());

    // QML の FileDialog は file:/// 形式の QUrl を返す。toLocalFile で OS パスへ変換する。
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (localPath.isEmpty()) {
        return false;
    }

    QSaveFile file(localPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    if (file.write(doc.toJson(QJsonDocument::Indented)) < 0) {
        return false;
    }
    return file.commit();
}

QVariantMap ProjectIo::load(const QUrl &fileUrl)
{
    using namespace hmi::schema;

    QVariantMap result;
    result.insert(QStringLiteral("ok"), false);
    result.insert(QStringLiteral("widgets"), QVariantList{});
    // 失敗時も widgets と対称に variables の既定（空配列）を入れておく。これがないと
    // QML 側が ok を確認する前に result.variables を読んだとき undefined になる（CodeRabbit 指摘）。
    result.insert(QStringLiteral("variables"), QVariantList{});

    // FileDialog から渡される file:/// 形式の QUrl を OS パスへ変換する（Task 6 の save と同方針）。
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
    // 唯一の真実とする方針に従い、ProjectData::parseValidated に委ねる。fromJson は
    // キー欠落時に既定値で埋める緩い設計のため、検証を通さないと `{}` や別形式の JSON でも
    // 成功扱いになる。「検証してから fromJson」は Schema 側 1 箇所に強制済み。
    const std::optional<ProjectData> parsed = ProjectData::parseValidated(data);
    if (!parsed) {
        return result;
    }
    const ProjectData proj = *parsed;

    // isValidJson が screens 配列に最低 1 件含まれていることを保証している。
    // MVP では先頭スクリーンのみを編集対象とする（save 側も "Main" 単一スクリーン構成）。
    const ScreenData screen = proj.screens.first();

    // 全フィールドの転写は WidgetData::toVariantMap（Schema）に集約済み。delegate が読む
    // QVariantMap を 1 行で得る（従来は属性ごとに手書き insert していた）。
    QVariantList widgetsVar;
    widgetsVar.reserve(screen.widgets.size());
    for (const WidgetData &w : screen.widgets) {
        widgetsVar.append(w.toVariantMap());
    }

    // Phase 7 / MB-1: connection id → ConnectionData の引き当て表を作り、各変数の source に
    // 接続詳細（host / port / unitId / proto）を戻して Editor UI が再表示できるようにする
    // （save 時に variable.source からは接続詳細を落としたため）。
    QHash<QString, ConnectionData> connById;
    for (const ConnectionData &c : proj.connections) {
        connById.insert(c.id, c);
    }

    QVariantList variablesVar;
    variablesVar.reserve(proj.variables.size());
    for (const VariableData &var : proj.variables) {
        QVariantMap vmap = var.toVariantMap();
        if (var.source) {
            QVariantMap smap = var.source->toVariantMap();
            const auto it = connById.constFind(var.source->connection);
            if (it != connById.constEnd()) {
                smap.insert(QStringLiteral("host"), it->host);
                smap.insert(QStringLiteral("port"), it->port);
                smap.insert(QStringLiteral("unitId"), it->unitId);
                smap.insert(QStringLiteral("proto"), it->proto);
            } else {
                // connections[] に対応 id が無い（壊れた JSON 等）。host/port/unitId は
                // 補完できず Editor では既定表示になる。診断のため警告する（CodeRabbit PR #119）。
                qWarning() << "ProjectIo::load: connection id not found:"
                           << var.source->connection;
            }
            vmap.insert(QStringLiteral("source"), smap);
        }
        variablesVar.append(vmap);
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    // Task 39: Project レベルの変数定義も QML へ届ける（T40 の編集 / T41 の実行ストア初期化が読む）。
    result.insert(QStringLiteral("variables"), variablesVar);
    return result;
}
