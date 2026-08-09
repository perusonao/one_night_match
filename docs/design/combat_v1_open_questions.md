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

---

## Phase 1実装前に必要な項目

**現時点で該当なし。** 前回時点でブロッカーだった項目（A〜D）はすべて今回のセッションで解決した。
Phase 1のCore Skeleton実装は、現在のSSOT（`combat_rules_v1.md`）と技術設計
（`combat_v1_phase1_design.md`）だけで着手可能と判断する。

---

## 後続Phaseまで保留可能な項目

### 1. `finisherType`と`directPin`/`submissionHold`の優先順位ルール

- 関連章: `combat_rules_v1.md` 13章、`combat_v1_phase1_design.md` 2.4章
- 内容: `category == finisher`のカードでは`finisherType`が決着方式を決定し、`directPin`/`submissionHold`は
  参照しない、という優先順位ルールを本設計セッションの中で暫定的に定めた（ユーザー指示には優先順位の
  明示までは含まれていなかったため、設計上の解釈として採用）。
- 影響: Phase1では技モデルにフィールドを保持するのみで判定に使わないため、Phase1の実装には影響しない。
- 解決が必要な時期: **Phase 9（FINISHER実装）着手前**。矛盾する値（例: `finisherType=submission`だが
  `submissionHold=false`）を許容するか、データ投入時にバリデーションで防ぐかも含めて確認が必要。

### 2. PINカード「共有4枚」の管理構造

- 関連章: `combat_rules_v1.md` 8.1章
- 内容: Phase1では`CombatV1PlayerState.pinCardsHeld`を各プレイヤーが独立して持つ単純な`int`として
  初期化するのみ。「共有4枚」という制約（`playerA.pinCardsHeld + playerB.pinCardsHeld == 4`が常に
  成り立つべきという不変条件）を`CombatV1MatchState`側で検証・保証する仕組みを持たせるかどうかは未検討。
- 解決が必要な時期: **Phase 5（PIN/KOC実装）着手前**。

### 3. ジャックのデッキ配分（SIGNATURE/FINISHER/COUNTER内訳）

- 関連章: `combat_rules_v1.md` 21章
- 内容: 一次資料（docx）にはアカリ・レイナ・ミサキの3人について
  「SIGNATURE各×2、FINISHER各×1、COUNTER各×2」という内訳が明記されているが、ジャックについては
  NORMAL18枚（うちROUGH5枚）の基準のみが記載され、SIGNATURE/FINISHER/COUNTERの内訳が示されていない。
  推測で補完していない。
- 解決が必要な時期: **Phase 10（4レスラー正式デッキ実装）着手前**。

### 4. アカリ・レイナの技データ（全12技の詳細数値）

- 関連章: `combat_rules_v1.md` 22章
- 内容: 一次資料に記載がなく、本セッションでも意図的に確定させていない（ユーザー指示により推測補完を
  行っていない）。
- 解決が必要な時期: **Phase 10着手前**。ユーザーからの追加仕様提供待ち。

### 5. 技系統（TechniqueFamily）の正式taxonomy

- 関連章: `combat_rules_v1.md` 23章
- 内容: COUNTER成立判定に使う「技系統」の正式な分類（例: バックドロップ系、スープレックス系等）は
  未確定。Phase1では`familyId: String?`という暫定構造のみ用意する。
- 解決が必要な時期: **Phase 4（COUNTER実装）着手前**。

### 6. COUNTER時の＊(ワイルド)ENERGY使用ポリシー

- 関連章: `combat_rules_v1.md` 5.1章、7章
- 内容: TECHNIQUE支払い時のワイルド解決方式（B番の通り確定済み）とは別に、COUNTER支払い時に＊を
  同様に使ってよいか、レート・条件が異なるかは未確定。ユーザー方針により意図的に保留されている。
- 解決が必要な時期: **Phase 4（COUNTER実装）着手前**。

### 7. `CombatV1MatchState`への集計系フィールドの要否

- 関連章: `combat_v1_phase1_design.md` 2.6章
- 内容: `winner`/`isOver`はPhase1では追加しないことを確定した。ただしPhase5〜9のどのタイミングで、
  どのような形（`winnerIndex: int?`、`winReason: String?`等）で追加するかは各Phase着手時に個別判断する。
- 解決が必要な時期: 各該当Phase（5・6・9のいずれか）着手時。

### 8. Legacy Engine Removal Gate通過後の資産移植範囲の詳細

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
