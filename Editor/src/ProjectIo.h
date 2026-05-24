#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

// QML から呼ばれる、Project の JSON 保存ヘルパー（Task 6）。
// Widget / Screen / Project の型と JSON I/O は Shared/Schema を唯一の真実とし、
// 本クラスは「QML 側で集めた Widget リスト → Shared/Schema の型 → 既存 toJson() →
// ファイル書き出し」の橋渡しのみを行う。
class ProjectIo : public QObject {
    Q_OBJECT
public:
    explicit ProjectIo(QObject *parent = nullptr);

    Q_INVOKABLE bool save(const QUrl &fileUrl,
                          const QString &projectName,
                          const QString &screenName,
                          const QVariantList &widgets);
};
