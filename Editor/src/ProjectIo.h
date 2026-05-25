#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// QML から呼ばれる、Project の JSON 保存 / 読込ヘルパー（Task 6 / 7）。
// Widget / Screen / Project の型と JSON I/O は Shared/Schema を唯一の真実とし、
// 本クラスは「QML 側 ↔ Shared/Schema の型 ↔ ファイル」間の橋渡しのみを行う。
class ProjectIo : public QObject {
    Q_OBJECT
public:
    explicit ProjectIo(QObject *parent = nullptr);

    Q_INVOKABLE bool save(const QUrl &fileUrl,
                          const QString &projectName,
                          const QString &screenName,
                          const QVariantList &widgets);

    // Task 7: 指定 JSON ファイルからプロジェクトを読み込む。
    // 戻り値は QML で扱いやすい QVariantMap。
    //   { ok: bool, project: string, screen: string, widgets: [ { id,type,x,y,width,height,text,tag }, ... ] }
    // ok が false の場合 widgets は空配列。
    Q_INVOKABLE QVariantMap load(const QUrl &fileUrl);
};
