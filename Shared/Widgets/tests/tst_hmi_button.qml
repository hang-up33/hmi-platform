import QtQuick
import QtTest
import HmiWidgets

// Task 13: HmiButton のプロパティ反映・クリックシグナル検証。
//
// 観点：
//   - デフォルトプロパティ（text="Button", tag="", width=120, height=40）
//   - text を変更すると内部の Text 要素にも反映される
//   - tag プロパティの設定・取得
//   - MouseArea のクリックで clicked シグナルが発火する
//
// 重要：TestCase に visible: true を明示すること。
//   TestCase は内部的に QQuickView 上に配置されるが、デフォルトでは
//   visible: false で生成されるため、子要素の effective visible も false
//   になり、MouseArea がクリックイベントを受けない。visible: true を
//   明示すると、TestCase 配下の Item ツリー全体が visible になり、
//   when: windowShown 完了後に mouseClick が正しく届くようになる。
//
//   QQuickView 自体（btn.Window.window.visibility）は visible で active
//   になっているが、その上の TestCase が visible: false だと階層的に
//   ブロックされる。Task 12 の smoke は MouseArea を持たないため
//   この問題に当たらなかった。Task 14 以降の QML テストでも同じ対処が要る。
TestCase {
    id: testCase
    name: "HmiButton"
    when: windowShown
    visible: true
    width: 200
    height: 100

    HmiButton {
        id: btn
        x: 0
        y: 0
    }

    SignalSpy {
        id: clickedSpy
        target: btn
        signalName: "clicked"
    }

    function init() {
        // 各 test_* 実行前にプロパティをリセット
        btn.text = "Button";
        btn.tag = "";
        btn.width = 120;
        btn.height = 40;
        // Task 31: ボーダー＋角丸の入力も既定（未指定）へ戻す。
        btn.borderColor = "";
        btn.borderWidth = -1;
        btn.cornerRadius = -1;
        // PR #109: 状態（checkable / checked）も既定へ戻す。
        btn.checkable = false;
        btn.checked = false;
        clickedSpy.clear();
    }

    function test_default_properties() {
        compare(btn.text, "Button");
        compare(btn.tag, "");
        compare(btn.width, 120);
        compare(btn.height, 40);
    }

    function test_text_property_is_reflected() {
        btn.text = "Start";
        compare(btn.text, "Start");

        // 内部の Text 要素が text プロパティに追従するか確認
        const innerText = findChildOfType(btn, "QQuickText");
        verify(innerText !== null);
        compare(innerText.text, "Start");

        btn.text = "Stop";
        compare(innerText.text, "Stop");
    }

    function test_tag_property_is_settable() {
        btn.tag = "PLC.START";
        compare(btn.tag, "PLC.START");

        btn.tag = "PLC.STOP";
        compare(btn.tag, "PLC.STOP");
    }

    function test_click_emits_clicked_signal() {
        compare(clickedSpy.count, 0);

        mouseClick(btn, btn.width / 2, btn.height / 2);
        compare(clickedSpy.count, 1);

        mouseClick(btn, btn.width / 2, btn.height / 2);
        compare(clickedSpy.count, 2);
    }

    // Task 31: 未指定（空 / -1）のとき resolved* が既定外観（#1d3557 / 1 / 4）に
    // フォールバックし、root Rectangle の border/radius に反映されること。既定値の
    // 単一ソースが HmiButton にあることを固定する。
    function test_border_radius_defaults_when_unspecified() {
        compare(btn.resolvedBorderWidth, 1);
        compare(btn.resolvedCornerRadius, 4);
        // border.width / radius は root Rectangle 自身のプロパティ。
        compare(btn.border.width, 1);
        compare(btn.radius, 4);
    }

    // Task 31: 明示値（0 含む）が resolved* と描画へ反映される。**borderWidth=0 /
    // cornerRadius=0 は「ボーダー / 角丸なし」の正当値**であり、未指定（既定 1 / 4）に
    // フォールバックしてはいけない（`>= 0` 判定であることを固定する）。
    function test_border_radius_explicit_values_including_zero() {
        btn.borderWidth = 5;
        btn.cornerRadius = 10;
        compare(btn.resolvedBorderWidth, 5);
        compare(btn.resolvedCornerRadius, 10);
        compare(btn.border.width, 5);
        compare(btn.radius, 10);

        btn.borderWidth = 0;
        btn.cornerRadius = 0;
        compare(btn.resolvedBorderWidth, 0);
        compare(btn.resolvedCornerRadius, 0);
        compare(btn.border.width, 0);
        compare(btn.radius, 0);
    }

    // PR #109: checked（ON）の見た目（背景を暗く + ボーダー +2）は **checkable に依存せず
    // checked 単独で出る**こと。`checked` を変数バインドして状態表示に使うとき、対象が
    // checkable:false（トグルOFF）でも見た目が変わらない不具合を防ぐ回帰固定。
    function test_checked_visual_is_independent_of_checkable() {
        const base = btn.resolvedBackgroundColor;
        const onColor = Qt.darker(base, 1.15);
        const baseWidth = btn.resolvedBorderWidth;

        // 既定（checked=false）：素の背景・素のボーダー幅。
        compare(btn.checked, false);
        compare(btn.color, base);
        compare(btn.border.width, baseWidth);

        // checkable:false のまま checked のみ true → ON 見た目になる（暗転 + ボーダー +2）。
        btn.checkable = false;
        btn.checked = true;
        compare(btn.color, onColor);
        compare(btn.border.width, baseWidth + 2);

        // checkable:true でも同じ ON 見た目（checkable に依存しない）。
        btn.checkable = true;
        compare(btn.color, onColor);
        compare(btn.border.width, baseWidth + 2);

        // checked を戻すと素の見た目へ。
        btn.checked = false;
        compare(btn.color, base);
        compare(btn.border.width, baseWidth);
    }

    // QQuickItem ツリーから指定された型名（"QQuickText" 等）の最初の子を再帰的に探す。
    function findChildOfType(item, typeName) {
        if (!item)
            return null;
        const items = item.children;
        for (let i = 0; i < items.length; ++i) {
            const c = items[i];
            // toString() は "QQuickText(0x...)" 等を返す
            if (c.toString().indexOf(typeName) === 0)
                return c;
            const nested = findChildOfType(c, typeName);
            if (nested)
                return nested;
        }
        return null;
    }
}
