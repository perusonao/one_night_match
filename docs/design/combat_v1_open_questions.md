# Combat Ver.1 — 未決定事項一覧

- ステータス: Phase 0（設計確定セッション）完了時点の一覧
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_phase1_design.md`](combat_v1_phase1_design.md)（Phase 1技術設計）

各項目には「ステータス」「関連章」「解決が必要な時期」を記す。Phase 1着手前に解決が必要な項目と、
後続Phaseまで保留してよい項目を分けている。

---

## Phase 0時点で解決した項目（今回のセッションで確定）

以下は前回セッション終了時点で「Phase 1実装前に決める必要がある」としていたが、今回のプロンプトで
明示的に確定した。

| # | 項目 | 確定内容 | 関連章 |
|---|---|---|---|
| A | `docs/combat_rules_v1.md`の不在 | 本セッションで正式作成した | SSOT全体 |
| B | ワイルド(＊)ENERGYの多属性不足時の解決方式 | 具体属性を先に使用→不足分を属性横断で合算→＊残量と比較する1パス方式で確定 | `combat_rules_v1.md` 5.1章 |
| C | 不正なCommand呼び出し時の挙動 | silent no-opではなく`CombatV1IllegalActionException`を送出するfail-fast方式で確定 | `combat_rules_v1.md` 1章、`combat_v1_phase1_design.md` 4章 |
| D | HP初期値の扱い | 全レスラー共通固定150（Phase1ではレスラーごとの上書きを行わない）で確定 | `combat_rules_v1.md` 2・14章 |
| E | KOC/PINカードをPhase1のPlayerStateに含めるか | 含める（初期化のみ、ロジックはPhase5）で確定 | `combat_rules_v1.md` 8・9章 |
| F | FinisherTypeの表現方法 | `directPin`/`submissionHold`からの導出ではなく、独立enum`CombatV1FinisherType`で確定 | `combat_rules_v1.md` 13章 |
| G | `finisherType`と`directPin`/`submissionHold`の優先順位ルール | `category == finisher`の場合は`finisherType`が決着方式を決定し、`directPin`/`submissionHold`は参照しない。`category != finisher`（NORMAL/SIGNATURE）の場合は`directPin`/`submissionHold`のみが意味を持ち、`finisherType`は`null`とする、で確定 | `combat_rules_v1.md` 13章、`combat_v1_phase1_design.md` 2.4章 |

---

## Phase 1実装前に必要な項目

**現時点で該当なし。** 前回時点でブロッカーだった項目（A〜D）はすべて今回のセッションで解決した。
Phase 1のCore Skeleton実装は、現在のSSOT（`combat_rules_v1.md`）と技術設計
（`combat_v1_phase1_design.md`）だけで着手可能と判断する。

---

## Phase 4時点で解決した項目（Phase 4セッションで確定）

以下は前回（Phase 0）時点で「Phase 4着手前に決める必要がある」としていたが、Phase 4セッションで
明示的に確定した。

| # | 項目 | 確定内容 | 関連章 |
|---|---|---|---|
| H | 技系統（TechniqueFamily）の正式taxonomy | 30 family（STRIKE8／AERIAL3／THROW8／SUBMISSION9／FOUL2）と、それをまとめる技系統グループ（TechniqueFamilyGroup、5 group）を確定。familyはgroupを保持せず`family.group`で導出する方式で確定 | `combat_rules_v1.md` 23章 |
| I | COUNTER時の＊(ワイルド)ENERGY使用ポリシー | `CombatV1RulesConfig.counterAllowsWildSubstitution`（既定値`false`）として確定。TECHNIQUE支払いとは独立したポリシーとして扱い、既存の`resolveEnergyPayment`をそのまま再利用する | `combat_rules_v1.md` 5.2章 |

---

## Phase 5時点で解決した項目（Phase 5セッションで確定）

以下は前回（Phase 0）時点で「Phase 5着手前に決める必要がある」としていたが、Phase 5セッションで
明示的に確定した。`combat_rules_v1.md`本文（一次資料由来）には記載がなかったため、Phase
5実装セッション内でユーザーへ確認したうえで正式仕様として採用した。

| # | 項目 | 確定内容 | 関連章 |
|---|---|---|---|
| J | PINカード「共有4枚」の管理構造・移動の主体と向き | 中央poolは持たず各`CombatV1PlayerState.pinCardsHeld`で管理し、`playerA.pinCardsHeld + playerB.pinCardsHeld == 4`をmatch-level invariantとして保証する（構造面はPhase1時点の想定どおり）。移動の主体と向きは、攻撃側が自分のPINカードを1枚使用してPINを開始し、1／2カウントでkick outされた場合にそのカードが攻撃側→防御側へ移動する、で確定した | `combat_rules_v1.md` 8.1章 |
| K | PINカウントの決定方式 | 段階応答（`pinResponsePending`のような多段階の入力待ち）ではなく、PIN開始時点の防御側KOCから最終カウントを一括で決定する方式で確定した | `combat_rules_v1.md` 8.2章 |
| L | KICK OUTの方式 | 自動（防御側が必要KOCを保有していれば必ずkick outし、「保有していてもあえて支払わない」という選択肢は存在しない）で確定した | `combat_rules_v1.md` 8.2章 |
| M | kick out後の展開（phase/activePlayerIndex） | 1／2カウントは攻撃側のターンを終了し防御側へ主導権を移す（`endTurn`と同じ内部処理）。2.9カウントは攻撃側が`action`フェーズへ戻り攻撃を継続できる（`activePlayerIndex`不変）、で確定した | `combat_rules_v1.md` 8.3章 |

---

## 後続Phaseまで保留可能な項目

### 1. PINカード「共有4枚」の管理構造

**Phase 5で解決済み（J番）。上記「Phase 5時点で解決した項目」参照。**

### 2. ジャックのデッキ配分（SIGNATURE/FINISHER/COUNTER内訳）

- 関連章: `combat_rules_v1.md` 21章
- 内容: 一次資料（docx）にはアカリ・レイナ・ミサキの3人について
  「SIGNATURE各×2、FINISHER各×1、COUNTER各×2」という内訳が明記されているが、ジャックについては
  NORMAL18枚（うちROUGH5枚）の基準のみが記載され、SIGNATURE/FINISHER/COUNTERの内訳が示されていない。
  推測で補完していない。
- 解決が必要な時期: **Phase 10（4レスラー正式デッキ実装）着手前**。

### 3. アカリ・レイナの技データ（全12技の詳細数値）

- 関連章: `combat_rules_v1.md` 22章
- 内容: 一次資料に記載がなく、本セッションでも意図的に確定させていない（ユーザー指示により推測補完を
  行っていない）。
- 解決が必要な時期: **Phase 10着手前**。ユーザーからの追加仕様提供待ち。

### 4. 技系統（TechniqueFamily）の正式taxonomy

**Phase 4で解決済み（H番）。上記「Phase 4時点で解決した項目」参照。**

### 5. COUNTER時の＊(ワイルド)ENERGY使用ポリシー

**Phase 4で解決済み（I番）。上記「Phase 4時点で解決した項目」参照。**

### 6. `CombatV1MatchState`への集計系フィールドの要否

- 関連章: `combat_v1_phase1_design.md` 2.6章
- 内容: `winner`/`isOver`はPhase1では追加しないことを確定していた。**Phase 5で解決済み**:
  PINによる3カウント決着が初めて発生しうるようになったため、`winnerPlayerIndex: int?`と、
  そこから導出する`isOver`getterを`CombatV1MatchState`へ正式追加した（勝者名stringの重複保存は
  しない）。技術設計の詳細は`combat_v1_phase1_design.md`「14.5章」参照。
- 解決が必要な時期: ~~各該当Phase（5・6・9のいずれか）着手時~~ → Phase 5で解決済み。

### 7. Legacy Engine Removal Gate通過後の資産移植範囲の詳細

- 関連章: `combat_rules_v1.md` 27.3章
- 内容: 「Playtest Analytics、Simulatorの設計、Report、Diagnosticsなど再利用価値のある資産を削除前に
  評価する」という方針は確定したが、具体的にどのファイル・どのクラスを移植するかはGate通過が近づいた
  時点（Phase 9〜13のいずれか）で個別に棚卸しする。
- 解決が必要な時期: Legacy Engine Removal Gate直前。

---

## 実行環境に関する既知の制約（仕様事項ではないが記録）

- 本セッションの実行環境には Flutter/Dart SDK がインストールされておらず、`flutter analyze` /
  `flutter test` を実行できなかった（`git status`によるコード無変更の確認のみで代替した）。
  Phase 1でテストコードを実装する際は、Flutter SDKが利用可能な環境で `flutter analyze` / `flutter test`
  を実行して確認する必要がある。
