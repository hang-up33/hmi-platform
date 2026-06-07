#pragma once

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QString>
#include <QTimer>
#include <QUrl>

// ヘッドレス動作証跡スクショ用ヘルパー。
//
// `--screenshot <path>` 指定時に、QML の root ウィンドウを 1 フレーム描画してから
// PNG を保存し、アプリを終了させる。Claude Code on the web のように
// ウィンドウシステムが無い環境で QT_QPA_PLATFORM=offscreen と組み合わせ、
// QQuickWindow::grabWindow() でオフスクリーン描画結果を取得する（Xvfb 不要）。
// 実機 i.MX8MP の VNC キャプチャ（scripts/yocto/vnc-capture.py）とは別経路。
//
// Editor / Simulator で同等のヘルパーが必要だが、CLAUDE.md「Editor / Simulator で
// 同等の C++ ヘルパーは Shared に移さず両方に独立して持つ」方針に従い、
// 各アプリの src/ に同内容のヘッダを置く（QObject 派生しない free function 実装
// なので moc 不要・ヘッダ 1 枚で完結する）。Simulator/ のソースは Runtime/ とも
// 共有されるため、hmi_runtime の PC ビルドでも同じ --screenshot が使える。
//
// 使い方（main.cpp 側）:
//   engine.loadFromModule(...) の **前** に installScreenshotGrabber() を呼ぶ。
//   objectCreated シグナルで root の QQuickWindow を捕まえ、delayMs 後に
//   1 枚撮って QCoreApplication::exit() する。delayMs は Component.onCompleted の
//   自動ロード（--open）が描画に反映されるまでの猶予。
inline void installScreenshotGrabber(QQmlApplicationEngine &engine,
                                     const QString &outputPath,
                                     int delayMs)
{
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &engine,
        [outputPath, delayMs](QObject *object, const QUrl &) {
            // object == nullptr は生成失敗。これは別途接続された
            // objectCreationFailed 側で exit(-1) されるのでここでは何もしない。
            if (object == nullptr) {
                return;
            }
            // root は loadFromModule の "Main"（QML の Window）= QQuickWindow。
            auto *window = qobject_cast<QQuickWindow *>(object);
            if (window == nullptr) {
                qWarning().noquote()
                    << "[screenshot] root が QQuickWindow ではないため撮影できません";
                QCoreApplication::exit(1);
                return;
            }
            // offscreen では明示的に可視化して描画パイプラインを起動する。
            window->setVisible(true);
            // delayMs 後に 1 枚撮って終了。QML の自動ロード完了を待つ猶予。
            QTimer::singleShot(delayMs, window, [window, outputPath]() {
                const QImage image = window->grabWindow();
                if (image.isNull()) {
                    qWarning().noquote()
                        << "[screenshot] grabWindow() が空画像を返しました";
                    QCoreApplication::exit(1);
                    return;
                }
                const QFileInfo fi(outputPath);
                const QDir outDir = fi.absoluteDir();
                if (!outDir.exists()) {
                    outDir.mkpath(QStringLiteral("."));
                }
                const QString absPath = fi.absoluteFilePath();
                if (!image.save(absPath, "PNG")) {
                    qWarning().noquote()
                        << "[screenshot] PNG 保存に失敗:" << absPath;
                    QCoreApplication::exit(1);
                    return;
                }
                qInfo().noquote()
                    << "[screenshot] 保存しました:" << absPath
                    << QStringLiteral("(%1x%2)")
                           .arg(image.width())
                           .arg(image.height());
                QCoreApplication::exit(0);
            });
        },
        Qt::QueuedConnection);
}
