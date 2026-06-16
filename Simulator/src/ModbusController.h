#pragma once

#include <QHash>
#include <QList>
#include <QModbusDataUnit>
#include <QModbusDevice>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

QT_BEGIN_NAMESPACE
class QModbusTcpClient;
class QTimer;
QT_END_NAMESPACE

// Phase 7 / MB-2: PC（Simulator）/ 実機（Runtime）が Modbus TCP マスタになり、
// PLC のレジスタを周期ポーリング（read）して既存の変数ストア + binding 経路へ流す。
//
// 本クラスは **Simulator 共有ソース**に置く（Runtime が CMake glue でソース共有して
// 自動的に継承する）。Editor は `Qt6::SerialBus` を一切リンクしないので Editor には
// 載らない（接続定義を JSON に書くだけ＝通信しない）。`hmi_schema` には絶対に置かない
// （Schema は通信を知らない）。CLAUDE.md「QML 連携クラスは利用側アプリに置く」方針。
//
// 設計：
//   - 接続ごとに 1 つの QModbusTcpClient を用意し connectDevice()。
//   - source（{connection,reg,address,poll}）を持つ変数ごとに poll[ms] 周期の QTimer を
//     回し、read を発行する。read 結果は variableUpdated(name, value) で emit し、QML 側
//     が VariableStore.setValue(name, value) へ接続する。
//   - 非同期前提（QModbusReply::finished）で UI を塞がない。reply は UI スレッドで
//     finished するので worker スレッドは使わない（MVP）。
//   - 読込のみ（書込・接続状態 UI は MB-4）。接続失敗 / read エラーは qWarning() に記録
//     して落ちない（再接続の作り込みは MB-4 スコープ）。
class ModbusController : public QObject {
    Q_OBJECT
    // Phase 7 / MB-4: 接続 id → 状態文字列（"connected"/"connecting"/"disconnected"/
    // "error"）のマップ。QML が接続状態をラベル等へ最小表示できるよう公開する。
    Q_PROPERTY(QVariantMap connectionStates READ connectionStates NOTIFY connectionStatesChanged)
public:
    explicit ModbusController(QObject *parent = nullptr);
    ~ModbusController() override;

    // プロジェクトの connections[] と source 付き variables[] を受け取り、接続を確立して
    // 周期ポーリングを開始する。各 connection は {id,host,port,unitId,...} の QVariantMap、
    // 各 variable は {name,type,source:{connection,reg,address,poll}} の QVariantMap。
    // source を持たない変数は無視する（内部変数のまま＝後方互換）。
    Q_INVOKABLE void configure(const QVariantList &connections, const QVariantList &variables);

    // 全タイマ停止・全接続切断（再 configure や終了時に呼ぶ）。
    Q_INVOKABLE void stop();

    // Phase 7 / MB-4: HMI 操作（NumericField 確定 / Button アクション）由来の変数更新を
    // PLC へ書き込む。name が書込可能な source（coil / holding のみ）を持つ変数なら、
    // 対応接続の QModbusTcpClient で sendWriteRequest を発行する。source 無し / 読取専用
    // レジスタ（discrete / input）は no-op + 警告（呼ぶ側は気にせず呼べる）。
    // 読込（variableUpdated→setValue）由来の変化では呼ばないこと（読込ループ回避）。
    Q_INVOKABLE void writeVariable(const QString &name, const QVariant &value);

    // 接続 id → 状態文字列のマップ（Q_PROPERTY READ）。
    QVariantMap connectionStates() const { return m_connectionStates; }

    // reg 種別が書込可能か（coil / holding のみ true）。write 表構築と unit テストで共用。
    static bool isWritableRegister(QModbusDataUnit::RegisterType type);

    // reg 文字列（"coil"/"discrete"/"input"/"holding"）→ QModbusDataUnit::RegisterType。
    // 不正 / 空は QModbusDataUnit::Invalid を返す。read 発行と unit テストで共用する純関数。
    static QModbusDataUnit::RegisterType registerTypeFromString(const QString &reg);

    // reg が bool 系（coil/discrete）かどうか。値を 0/1 に正規化するため read 結果処理で使う。
    static bool isBooleanRegister(QModbusDataUnit::RegisterType type);

signals:
    // ポーリングで読んだレジスタ値を変数名付きで通知する。QML 側が VariableStore.setValue へ接続。
    void variableUpdated(const QString &name, const QVariant &value);

    // Phase 7 / MB-4: 接続状態マップが変化したときに通知する。
    void connectionStatesChanged();

private:
    // 1 つのポーリング対象（変数 → 接続/レジスタ写像）。
    struct PollItem {
        QString name;
        QString connectionId;
        QModbusDataUnit::RegisterType regType = QModbusDataUnit::Invalid;
        int address = 0;
        int poll = 1000;
    };

    // Phase 7 / MB-4: 書込対象（変数名 → 接続/レジスタ写像）。coil / holding のみ登録する。
    struct WriteItem {
        QString connectionId;
        QModbusDataUnit::RegisterType regType = QModbusDataUnit::Invalid;
        int address = 0;
    };

    void startPolling();
    void pollOne(const PollItem &item);
    // Phase 7 / MB-4: 接続状態の更新（重複通知を避けつつ connectionStatesChanged を emit）。
    void setConnectionState(const QString &id, QModbusDevice::State state);
    // Phase 7 / MB-4: 切断 / エラー時の再接続を一定間隔で試みるタイマを開始する。
    void scheduleReconnect(const QString &id);

    // 接続 id → クライアント / unitId。
    QHash<QString, QPointer<QModbusTcpClient>> m_clients;
    QHash<QString, int> m_unitIds;
    QList<PollItem> m_items;
    QList<QTimer *> m_timers;
    // Phase 7 / MB-4: 変数名 → 書込写像（coil / holding のみ）。writeVariable で引く。
    QHash<QString, WriteItem> m_writeItems;
    // Phase 7 / MB-4: 接続 id → 状態文字列（QML 公開用）。
    QVariantMap m_connectionStates;
    // Phase 7 / MB-4: 接続 id → 再接続タイマ。stop() / configure() で確実に止める。
    QHash<QString, QTimer *> m_reconnectTimers;
    // 再接続の試行間隔（ミリ秒）。poll とは独立した固定値。
    static constexpr int kReconnectIntervalMs = 4000;
    // Phase 7 / MB-2: configure()/stop() ごとに増やす世代カウンタ。非同期 reply の
    // finished ラムダが capture した世代と一致する時だけ emit し、プロジェクト切替後に
    // 旧 reply が古い値を VariableStore へ混入させるのを防ぐ（CodeRabbit PR #121）。
    quint64 m_generation = 0;
};
