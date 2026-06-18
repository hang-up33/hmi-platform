# CI 復活計画 — self-hosted runner（Proxmox）で課金ゼロの自動 CI

> **位置づけ**：2026-06-10 に GitHub Actions の課金回避で自動 CI（`pull_request` / `push` トリガ）を停止し、`workflow_dispatch`（手動）のみにした（[ci.yml](../.github/workflows/ci.yml) 冒頭コメント / [dev-environment.md](../.claude/rules/dev-environment.md)「リポジトリ運用の注意」）。これを **Proxmox 上の self-hosted runner で課金ゼロのまま自動 CI に戻す**ための計画。
>
> **本書は計画のみ**。**CI はまだ off のまま**（`ci.yml` は変更しない）。**Proxmox に runner が立って動作確認が取れてから** `ci.yml` を改修して自動トリガを復活させる。
> **進捗の正本は本ファイル「進捗」表**。

---

## 現状と課題

| 項目 | 現状 |
|---|---|
| CI トリガ | `workflow_dispatch`（手動）のみ。PR / main push では一切走らない＝**自動の緑ゲートが無い** |
| 止めた理由 | GitHub Actions の課金（main push 毎に **macOS=10x / Windows=2x** ジョブが走り無料枠を消費） |
| 当面のテスト担保 | Web セッション内 `ctest`（unit + e2e）。CI 緑ではない（手動・属人的） |
| 既存 `ci.yml` の構造 | **Linux=主ゲート（1x）**＋ **desktop（mac/win）= `ci-desktop` ラベル + main push + 手動限定**。設計は良好で流用できる |

**狙い**：日常 PR の緑ゲートを**自前マシン（Proxmox）で無料・自動**に戻す。課金の主因 mac(10x) は自動化しない。

---

## 方針 — 二段構え（Linux=self-hosted / desktop=GitHub-hosted）

| ジョブ | 実行場所 | トリガ | 課金 |
|---|---|---|---|
| **linux**（主ゲート） | **Proxmox の self-hosted runner** | 毎 PR / main push（自動） | **0 円** |
| **desktop**（mac / win） | GitHub-hosted（据え置き） | **`ci-desktop` ラベル + 手動のみ**（main push を除外） | 必要時のみ |

- 日常 PR は self-hosted Linux で unit + e2e（offscreen）を毎回自動チェック＝**緑ゲート復活**。
- 実機 2 OS（mac/win）の確認は従来どおり必要時だけ GitHub-hosted で（10x の自動消費を避ける）。
- **⚠️ desktop ジョブの `if` も直す必要がある**（Codex PR #133 P2 指摘）。現行 `ci.yml:106-108` の `if: github.event_name != 'pull_request' || ...ci-desktop...` は **main push でも desktop（mac 10x / win 2x）が走る**。自動トリガで `push: main` を復活させると、main merge 毎に mac/win が自動起動して「課金ゼロ・mac 自動化しない」目的に反する。よって **desktop の `if` を「workflow_dispatch（手動）+ `ci-desktop` ラベル」限定に変える**（main push を除外）。
- `ci.yml` の変更は **①linux ジョブの `runs-on`** ＋ **②自動トリガのコメント解除** ＋ **③desktop ジョブの `if` を main push 除外**の 3 点。

```mermaid
flowchart LR
    PR["PR / main push"] --> GH["GitHub Actions"]
    GH -->|linux job| RUN["self-hosted runner<br/>(Proxmox LXC / Ubuntu 24.04)"]
    GH -->|desktop job<br/>ラベル/手動時のみ| HOSTED["GitHub-hosted<br/>macOS / Windows"]
    RUN --> RESULT["unit 8 + e2e 5 = 13/13<br/>offscreen / 課金 0"]
```

---

## 構築手順（Proxmox 側 — 君の手元で実施）

> runner 登録には **registration token**（リポジトリ Settings で都度発行・短命）が要るため、この部分は Web からは実施できない。

### 1. LXC コンテナ作成（Ubuntu 24.04）
- **OS**：Ubuntu 24.04（**本書執筆時点で** GitHub の `ubuntu-latest` = 24.04。`scripts/web/setup.sh` と同じ前提）。`ubuntu-latest` の実体は将来更新されうるので、ズレたら [GitHub runner-images](https://github.com/actions/runner-images) で現行版を確認して LXC を揃える。
- **スペック目安**：2〜4 vCPU / 4GB+ RAM / 30GB+ disk。
- **Docker は当面不要**＝LXC で十分（将来 runner 内で Docker を回すなら `features: nesting=1` を付けるか VM に切替）。

### 2. CI 依存を入れる（[ci.yml](../.github/workflows/ci.yml) の Linux deps + α）
```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  libgl1 libegl1 libegl-mesa0 libxkbcommon0 libfontconfig1 libfreetype6 libdbus-1-3 \
  libglib2.0-0t64 libx11-6 libxcb1 \
  libgl-dev libglx-dev libopengl-dev libegl-dev mesa-common-dev \
  ninja-build fonts-dejavu-core fonts-noto-cjk \
  cmake build-essential curl git python3 python3-pip
```
- **末尾の `cmake build-essential curl git python3 python3-pip` は `ci.yml` の apt 一覧には無い**が、これは**意図的な差分**：GitHub-hosted の `ubuntu-latest` イメージにはこれらが**プリインストール済み**なので ci.yml は列挙しないが、**素の LXC には入っていない**ため明示導入が要る。内訳：
  - **`cmake` / `build-essential`（= `g++` 等）**：ci.yml は直後に `cmake --version` / `g++ --version` / configure / build を実行する（[ci.yml](../.github/workflows/ci.yml) の Linux ジョブ）。`install-qt-action` も `ninja-build` もコンパイラ・cmake は供給しないため、無いと **テストの前に configure/build が落ちる**。
  - **`curl` / `git`**：runner 取得・checkout。**`python3` / `pip`**：E2E harness と `setup-python` の土台。
  - それ以外（libgl 〜 fonts）は ci.yml の Linux deps と同一。
- Qt 本体は **`ci.yml` 内の `jurplel/install-qt-action` で取得**（self-hosted でも動く。初回 DL・persistent runner なのでキャッシュで2回目以降速い）。**ただし下記「⚠️ SerialBus」の通り `modules` 追加が要る**。
- 外向きネットワークで **`download.qt.io` に到達できること**（Qt 取得）。Proxmox の LAN がそのまま出られるなら OK。
- **⚠️ SerialBus アドオンが要る**：root `CMakeLists.txt` は `find_package(Qt6 ... SerialBus)` を **REQUIRED** にしている（Phase 7 / Modbus）。一方で現行 `ci.yml` の `install-qt-action` は **`modules: ""`（SerialBus 無し）**のままなので、`runs-on` を変えるだけでは **configure 時に `Qt6SerialBus` が見つからず CI が復活しない**。下記「`ci.yml` 改修案」で **`modules: "qtserialbus qtserialport"` を追加**する（`scripts/web/setup.sh` も同じ addon を別途導入している前提と揃える）。

### 2.5. runner ユーザーに passwordless sudo を付与
ci.yml の Linux deps ステップが `sudo apt-get` を非対話で実行するため、runner 実行ユーザー（例 `runner`）に NOPASSWD sudo を付ける：
```sh
sudo useradd -m -s /bin/bash runner   # 既存なら不要
# ci.yml が要る sudo は apt-get のみ＝最小権限で絞る（NOPASSWD:ALL は付けない）
echo 'runner ALL=(ALL) NOPASSWD: /usr/bin/apt-get' | sudo tee /etc/sudoers.d/runner-nopasswd
sudo chmod 0440 /etc/sudoers.d/runner-nopasswd
sudo visudo -cf /etc/sudoers.d/runner-nopasswd   # 構文チェック
```
> 隔離 LXC で許容するなら `NOPASSWD:ALL` でも動くが、**最小権限（apt-get のみ）が推奨**。将来 deps を増やして別コマンドの sudo が要るようになったら、その実行ファイルを列挙に足す。
> deps を LXC イメージに焼き込んで ci.yml 側の apt ステップを self-hosted では skip する運用なら、この sudo 付与は省ける（その場合は deps を §2 で事前導入済みにしておく）。

### 3. GitHub Actions runner を登録
- リポジトリ → **Settings → Actions → Runners → New self-hosted runner（Linux x64）** に出るコマンドを LXC で実行（`./config.sh ...`（token 込み）→ `./run.sh`）。
- **ラベル**：既定の `self-hosted` `Linux` `X64` に加え、必要なら `qt` 等を付与（`ci.yml` 側の `runs-on` と一致させる）。
- **常駐化（root 権限で）**：`sudo ./svc.sh install runner && sudo ./svc.sh start` で systemd サービス化（LXC 起動で自動復帰）。systemd unit の作成・起動には root が要る（GitHub 公式手順も `sudo ./svc.sh ...`）。
  - **§2.5 の `NOPASSWD: /usr/bin/apt-get` 制限とは衝突しない**：あの最小権限は **runner プロセスがジョブ実行中に使う sudo**（＝ci.yml の apt ステップ）用。**この `svc.sh` 常駐化は一度きりのセットアップ**で、LXC の **root もしくはフル sudo 権限を持つ管理ユーザー**で実行する（制限付き `runner` ユーザーの sudoers では通らないので、root シェルか別の admin sudo で行う）。

### 4. 動作確認
- **テスト用ブランチで `ci.yml` を次のように変えてから** `workflow_dispatch` を打つ → linux ジョブが **self-hosted runner に割り当たって完走**し 13/13 緑を確認する：
  - **linux の `runs-on`** を `[self-hosted, linux]` に。
  - **install-qt-action の `modules`** に `qtserialbus qtserialport` を追加（無いと SerialBus で configure 落ち。§2「⚠️ SerialBus」参照）。
  - **⚠️ desktop ジョブを `if: false` でハード無効化する**：現行 desktop の `if`（`github.event_name != 'pull_request'`）も、改修案 ③ の `if`（`workflow_dispatch` + `ci-desktop` ラベル）も、**どちらも `workflow_dispatch` を許可**しているため、`if` を改修案③に差し替えるだけでは **手動 dispatch で mac(10x)/win(2x) が走り課金が出る**。linux だけ確認したいこの検証では、テストブランチで **desktop の `if` を一時的に `if: false` に固定**して dispatch する（＝検証中は desktop を確実に止める。確認後に改修案③の `if` へ戻す。Codex PR #133 P2）。
  - 現状の `ci.yml`（`runs-on: ubuntu-latest`）のまま手動実行しても linux は **GitHub-hosted に流れる**ため、self-hosted の確認にはならない。
  - 確認できたら、このテストブランチをそのまま下記「`ci.yml` 改修案」の PR に発展させてよい（revert は不要）。

---

## `ci.yml` 改修案（runner 動作確認後に別 PR で適用）

**まだ適用しない**。runner が緑で回ったらこの差分を入れて CI on にする。

```yaml
# on: のコメントアウトを解除（自動トリガ復活）
on:
  workflow_dispatch:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, labeled]
  push:
    branches: [main]

jobs:
  linux:
    name: Linux / Qt 6.10
    runs-on: [self-hosted, linux]   # ← ① ubuntu-latest から変更
    steps:
      ...
      - name: Install Qt
        uses: jurplel/install-qt-action@v4
        with:
          version: "6.10.0"
          # ④ SerialBus/SerialPort を追加（CMakeLists が SerialBus 必須）
          modules: "qtserialbus qtserialport"   # ← "" から変更
          ...
      ...

  desktop:
    name: ${{ matrix.name }}
    # ③ main push を除外し、手動 + ci-desktop ラベルのときだけ走らせる
    # （変更前は `github.event_name != 'pull_request'` で main push でも mac/win が走った）
    if: >-
      github.event_name == 'workflow_dispatch'
      || contains(github.event.pull_request.labels.*.name, 'ci-desktop')
    ...
```

- **①linux ジョブの `runs-on`** `ubuntu-latest` → `[self-hosted, linux]`。
- **②自動トリガ**（`pull_request` / `push`）のコメント解除。
- **③desktop ジョブの `if`** を `workflow_dispatch` + `ci-desktop` ラベル限定に変更し **main push を除外**（main merge 毎の mac 10x / win 2x 自動課金を防ぐ。Codex PR #133 P2）。desktop の steps 自体は無改変。
- **④install-qt-action の `modules`** を `""` → `"qtserialbus qtserialport"` に（CMakeLists が SerialBus 必須。無いと configure で `Qt6SerialBus` 未検出。Codex PR #133 P2）。linux / desktop 両ジョブとも。
- apt の Linux deps ステップは **self-hosted でも冪等に通る**（既導入なら skip 扱い）。passwordless sudo を runner ユーザーに付けておく。
- 復活したら [dev-environment.md](../.claude/rules/dev-environment.md)「リポジトリ運用の注意」の「CI は手動のみ」記述も更新する。

---

## セキュリティ注意

- **self-hosted runner は public リポだと fork PR が任意コード実行できて危険**。本リポが **private なら問題なし**。public 化する場合は fork PR を self-hosted に流さず GitHub-hosted へ振り分ける。具体策のいずれか：
  - **設定で塞ぐ（推奨）**：Settings → Actions → General の **"Fork pull request workflows from outside collaborators"** を「require approval for all external collaborators」にし、未承認の fork PR で workflow を起動させない。
  - **ジョブ条件で振り分け**：linux ジョブを `runs-on: ${{ github.event.pull_request.head.repo.fork && 'ubuntu-latest' || fromJSON('["self-hosted","linux"]') }}` のように **fork なら GitHub-hosted・自リポ PR なら self-hosted** に分岐する（fork のコードを self-hosted で実行しない）。
- runner は専用 LXC に隔離し、不要な権限（host の Proxmox 操作等）を持たせない。

---

## 非スコープ（別途承認）

CI を回す箱（self-hosted）ができた後の **上積み候補**。今回はやらない。

| 候補 | メモ |
|---|---|
| **cppcheck**（静的解析） | C++ が薄く今は低 ROI。やるなら Modbus（`ModbusController`）保険として最小から |
| **clang-tidy** | moc/autogen 除外など設定コスト高。後回し |
| **カバレッジ**（gcovr → HTML artifact） | テストがあるのは `Shared/Schema` のみ＝「Schema の回帰防止」と割り切れば可 |
| **SonarQube（Proxmox 自前）** | 静的解析 + カバレッジ + 履歴トレンドを Web ダッシュボードに一元化。常駐 Java+DB で運用重 |

---

## 進捗

| ステップ | 状態 | メモ |
|---|---|---|
| 計画書作成 | ✅ 本書 | CI は off のまま。`ci.yml` 未変更 |
| Proxmox LXC 作成 + CI 依存導入 | ⬜ 未 | 君の手元（手順は本書「構築手順」§1〜2） |
| self-hosted runner 登録・常駐化 | ⬜ 未 | registration token は Web 不可（手元で） |
| runner で手動実行 → 13/13 緑確認 | ⬜ 未 | §4 |
| `ci.yml` 改修（①linux=self-hosted ②自動トリガ復活 ③desktop=main push 除外 ④modules=qtserialbus qtserialport）+ dev-environment.md 更新 | ⬜ 未 | runner 緑確認後に別 PR |
