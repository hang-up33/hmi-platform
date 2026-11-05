本番コード（C++ / QML のロジック）を新規作成・変更するときは、**契約 → テスト → 実装** の 3 段階で進める。導入計画と進捗は [Docs/dbc-tdd-plan.md](../../Docs/dbc-tdd-plan.md)。

## 3 段階と次へ進む条件

| 段階 | やること | 次へ進む条件 |
|---|---|---|
| ① 契約 | 変更する関数・クラスの宣言に、**当てはまる条件だけ**を書く（下の「どの条件を書くか」）。**新規関数**にはビルドを通すための空の仮実装（既定値を返すだけ）を置く。**既存関数は現行の実装をそのまま残す** | 条件が表で確認でき、`cmake --build` が通る |
| ② テスト | 条件 1 つにつき 1 本以上のテストを書く | `ctest` で新しいテストが**アサーション失敗**する（コンパイルエラーで落ちるのは失敗確認に数えない） |
| ③ 実装 | テストには触らずに本番コードを書く | `ctest` 全件成功 |

- **振る舞いを変えないリファクタリングは例外**：② では、既存の挙動を固定するテスト（変更前から成功するのが正しい）を先に書いて成功を確認し、③ の後も同じテストが成功することを条件にする。アサーション失敗の確認は、機能追加・不具合修正のときだけ必須。
- ③ でテストが間違っていると気付いたら、**テストを直さず ① か ② に戻る**（契約の見直しから）。
- ドキュメントのみ・ビルド設定のみの変更には適用しない。
- 各段階でのファイルの書き換えは Edit / Write で行い、Bash（`sed -i` やスクリプト）では書き換えない（段階ごとの編集範囲の確認を素通りさせないため）。

### どの条件を書くか

| 条件 | 書く対象 |
|---|---|
| `@post` | 変更・追加したすべての公開関数（戻り値・状態の変化・不正入力時の挙動） |
| `@pre` | 呼び出し側に守ってもらう約束が実際にある関数だけ（外部入力を受ける関数には書かない） |
| `@invariant` | どの状態でも成り立つ条件を持つクラスだけ（既定構築直後や不正 JSON 読込後も含めて成り立つこと）。値を入れておくだけの構造体には書かない |

## 記法

C++（ヘッダの宣言に付ける）：

```cpp
// 値を入れておくだけの構造体なので @invariant は書かない（既定構築直後は type が空）
struct VariableData {
    /// @post VariableData_fromJson_Post1 isValidJson(obj) が true なら、戻り値の name / type は obj の値と一致する
    static VariableData fromJson(const QJsonObject &obj);

    /// @post VariableData_isValidJson_Post1 name が空なら false を返す
    /// @post VariableData_isValidJson_Post2 type が 4 種以外なら false を返す
    static bool isValidJson(const QJsonObject &obj);
};
```

QML（関数の直前に付ける。下の `clampValue` は説明用の架空の関数）：

```qml
// @pre  HmiExample_clampValue_Pre1 min <= max
// @post HmiExample_clampValue_Post1 戻り値は [min, max] の範囲内
function clampValue(v, min, max) { ... }
```

- 各条件には**契約キー**（`@pre` / `@post` / `@invariant` の直後に書く識別子）を付ける。テスト名との照合に使い、**リポジトリ全体で一意**にする（CI が重複を検出する）。
  - 作り方は `<所属>_<関数>_<番号>`。番号は種類ごとに分けて、事前条件 `Pre1`, `Pre2`…、事後条件 `Post1`, `Post2`…とする（同じ関数の事前条件と事後条件が同じキーにならないように）。クラスの不変条件は `<所属>_Inv1` のように関数を省く。

| 対象 | `<所属>` | `<関数>` | 例 |
|---|---|---|---|
| クラス・構造体のメンバ | 型名 | 関数名 | `VariableData_isValidJson_Post1` |
| QML の関数 | コンポーネント名（ファイル名） | 関数名 | `HmiNumericField_commitValue_Post1` |
| 型に属さない関数 | `<ディレクトリ>_<ファイル名>`（同名ファイルが別の場所にもあるため） | 関数名 | `Editor_ScreenshotGrabber_installScreenshotGrabber_Post1` |
| デストラクタ | 型名 | `dtor` | `ModbusController_dtor_Post1` |
| オーバーロード | 型名 | 関数名に引数の型を足す | `Foo_load_QString_Post1` / `Foo_load_QJsonObject_Post1`（架空） |
- **外部入力（JSON・通信・ユーザー入力）は事前条件にしない**。「不正な入力なら〜を返す」という事後条件として書く。
- 事前条件はアプリ内部の呼び出し同士の約束だけに使う。

## テスト名で契約と結び付ける

| 対象 | テスト名の付け方 | 例 |
|---|---|---|
| C++（QtTest の private slot） | `<種類>_<契約キー>_<内容>`（種類は `pre` / `post` / `inv`） | `post_VariableData_isValidJson_Post1_rejectsEmptyName` |
| QML（Qt Quick Test は `test_` 始まりが必須） | `test_<種類>_<契約キー>_<内容>` | `test_post_HmiExample_clampValue_Post1_withinRange`（架空） |

- 1 つの契約キーに対して、そのキーを名前に含むテストが 1 本以上あること。CI は契約キーの一意性と、キーごとのテストの有無を照合する。

**Why:** ユーザーが 2026-10-04 に「コードの間違いをなくすため、契約による設計の 3 条件 → テスト → 実装の順で書く」と明示指示した。

**How to apply:** 本番コードを触る前に ① を済ませる。② の確認を省略しない（機能追加・不具合修正はアサーション失敗、振る舞いを変えないリファクタリングは変更前の成功を確認）。スキル `dbc-tdd` と段階制御の hook が入るまで（[計画](../../Docs/dbc-tdd-plan.md) DT-2/DT-3）は、この表を手で守る。

関連：[[feedback-continuous-improvement]] / [[feedback-plan-docs-consistency]]
