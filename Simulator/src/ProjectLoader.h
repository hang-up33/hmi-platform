#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>

// QML から呼ばれる、Project JSON 読込ヘルパー（Task 8）。
// Simulator は読み取り専用なので Editor 側 ProjectIo の save 部分は持たず、
// load のみを提供する。Widget / Screen / Project の型と JSON I/O は
// Shared/Schema を唯一の真実とし、本クラスは「ファイル → Shared/Schema の
// 型（ProjectData::isValidJson + fromJson） → QML 用 QVariantMap」の
// 橋渡しのみを行う。
//
// CLAUDE.md「QML 連携クラスは利用側アプリ（Editor / Simulator）に置く」
// 方針に従い、Shared には移さず Simulator 配下に置く（Editor 側 ProjectIo
// と load の実装は重複するが、save が無いぶん責務が異なる）。
class ProjectLoader : public QObject {
    Q_OBJECT
public:
    explicit ProjectLoader(QObject *parent = nullptr);

    // 指定 JSON ファイルからプロジェクトを読み込む。
    // 戻り値は QML で扱いやすい QVariantMap：
    //   { ok: bool, project: string, screen: string, widgets: [ { id,type,x,y,width,height,text,tag }, ... ] }
    // ok が false の場合 widgets は空配列。
    Q_INVOKABLE QVariantMap load(const QUrl &fileUrl);
};
