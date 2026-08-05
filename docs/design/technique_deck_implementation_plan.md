# Technique Deck Rules — 段階実装計画

- ステータス: **Phase 7A（レスラーカード・技カード・モデルデッキ実装）
  完了時点**（Phase 7.5終了後、ユーザー指示により「ゲームバランス調整では
  なく4人分の正式な基準データを実装する」専用ラウンドを実施。
  `TechniqueDeckWrestlerProfile`へレスラーカードの各種フィールドを追加、
  技カード48枚（4人×12枚）を正式名称で追加、エスケープ・リバーサルを
  含まない30枚構成のPhase 7Aモデルデッキを4人分追加、Technique Deck
  Builderへのモデルデッキ一括読込ボタン、Technique Matchのデッキ解決
  優先度を「保存済み→モデルデッキ→AutoGenerator」へ変更。
  `TechniqueMatchEngine`・ダメージ計算等の実戦ロジックは無改修
  （詳細はPhase 7Aの章を参照）。Phase 7.5時点で判明していた「検証Botの
  構造的限界（“今使う価値＝温存判断”を評価できない）」への対応は、
  引き続きPhase 8の正式CPU実装に委ねる。Phase 8のCPU設計書
  （[`technique_deck_cpu_design.md`](technique_deck_cpu_design.md)）は
  完成済みだが、実装（Phase 8.0以降）は未着手）
- 対象仕様: [`technique_deck_rules.md`](../rules/technique_deck_rules.md)
- 未決定事項: [`technique_deck_open_questions.md`](technique_deck_open_questions.md)
- CPU設計: [`technique_deck_cpu_design.md`](technique_deck_cpu_design.md)

## 非目標（Non-Goals）

本計画のいずれのPhaseにおいても、以下は対象外とする。

- 現行 `classic` モード（`MatchResourceMode.classic`）のロジック・バランス変更
- 現行 `energy` モード（`MatchResourceMode.energy`、Ver.0.9〜1.1で正式採用済みの
  `signatureOncePerMatch` / `BasicCardPolicy` / `EnergySurplusPolicy` /
  `CpuDifficulty` / エンドゲームAI等）のロジック・バランス変更
- 既存の `LevelMatchEngine` / `LevelMatchState` の破壊的変更（新モードは独立した
  状態・エンジンとして設計し、既存クラスへの新モード専用フィールドの直接追加は
  最小限に留める。詳細な分離方針はPhase 1で確定する）
- 既存 `Deck Simulator`（`lib/src/level_match/deck_balance_*.dart`）の結果に
  影響を与える変更

## 現行モードとの差分表

[`technique_deck_rules.md` 2章](../rules/technique_deck_rules.md#2-現行ルールとの違い) を参照。

## 将来拡張項目（本計画の対象外）

[`technique_deck_rules.md` 15章](../rules/technique_deck_rules.md#15-将来のアクションカード) の
アクションカード・位置システム（ロープ／場外／コーナー／トップロープ／エプロン）は
Phase 10として本計画の末尾にのみ記載し、Phase 1〜9では一切実装しない。

---

## Phase 0：仕様保存（本作業）

**ステータス: 完了**

成果物:

- ルール仕様書（[`technique_deck_rules.md`](../rules/technique_deck_rules.md)）
- 未決定事項一覧（[`technique_deck_open_questions.md`](technique_deck_open_questions.md)）
- 実装ロードマップ（本書）
- 現行モードとの差分表（仕様書2章）
- 新モードの非目標（本書冒頭）
- 将来拡張項目（仕様書15章）

この段階ではゲームロジックを一切変更しない。`classic` / `energy` の
コード・テストは無変更であることを確認する（結果は本書のPhase 0完了報告を参照）。

**依存関係**: なし（起点）。

---

## Phase 1：データモデル基盤

**ステータス: 完了**

成果物: `lib/src/technique_deck/technique_deck_models.dart` /
`lib/src/technique_deck/technique_deck_validation.dart` /
`test/technique_deck_models_test.dart`（34テスト）。

実際に採用した型・モデル名:

- `TechniqueDeckResourceMode { disabled, techniqueDeck }` — 新ルールモード識別子。
  既存 `MatchResourceMode`（classic/energy）へは追加せず、独立enumとした
  （理由は `technique_deck_models.dart` 内の設計メモ、および本書「設計判断の記録」
  を参照）。既定値 `disabled`。
- `TechniqueCardCategory { normal, signature, finisher }` — 技カード種別。
  既存 `MoveCategory` は拡張せず、独立enumとした（仕様書3章 案B採用）。
- `TechniqueDeckCardType { technique, energy, escape, reversal, kickOut,
  ropeBreak, action }` — カード種別。
- `WrestlerPosture { stand, down, fatigued }`（`displayLabel` 拡張つき）、
  `TechniqueTargetState { any, stand, down }`。
- `TechniqueDeckTechniqueCard` — 技カード本体（`attackEnergyCost` /
  `reversalEnergyCost` / `targetState` / `causesDown` / `kickOutThreshold` /
  `kickOutHpRate` / `giveUpThreshold` / `giveUpHpCost` / `finisherRequirements` /
  `sourceMoveId` 等、仕様書7章に準拠したフィールドを保持）。
- `TechniqueEnergyCard` — 技エネルギーカード（ready/used状態は保持しない、
  定義のみ）。
- `TechniqueDefenseCard` — Escape/Reversal/KickOut/RopeBreak共通の最小モデル。
- `TechniqueDeckWrestlerProfile` — レスラー別 `recoveryPower` 等（既存
  `WrestlerDefinition` は変更せず分離）。
- `TechniqueDeckCardCatalog` — ID検索・種別検索・重複ID検出を持つ定義コンテナ
  （デッキ生成・30枚検証はPhase 2）。
- `TechniqueDeckValidationIssue` / `validateTechniqueCard` などの軽量検証
  （デッキ枚数・同名制限はPhase 2の対象）。

JSON入出力は全モデルで「未知の値は安全な既定値へフォールバックし、例外を
投げない」方針を徹底した（`enumOrDefault` / `_intOrNull` / `_doubleOrNull` /
`_boolOrDefault` / `_stringOrDefault` 等の専用ヘルパーで実現。既存の
`enumValue()` は未知値で例外を投げる仕様のため転用していない）。

wrestler_editor側のエディタUIは今回追加していない（案A採用: JSON I/O・
バリデーション・テストのみ）。理由は本書「設計判断の記録」を参照。

この段階では実戦ロジック（`LevelMatchEngine` 相当のTechnique Deck版）へは
一切接続していない。`classic`/`energy` モードのコード・テストへの変更もゼロ
（`lib/src/level_match/`・`lib/src/wrestler_editor/` は無変更）。

**依存関係**: Phase 0（仕様確定）。

### 設計判断の記録（Phase 1）

- **モード識別子を独立enumにした理由**: `MatchResourceMode` は
  `LevelMatchEngine`/`LevelMatchState` 内の数十箇所の網羅的 `switch` で
  使われており、値を追加すると既存の classic/energy 分岐にも新caseへの
  対応を要求するリスクがある。Technique Deck専用の `TechniqueDeckResourceMode`
  として独立させることで既存コードへの影響をゼロに保った。実戦エンジンへ
  接続する段階（Phase 4以降）で `MatchResourceMode` へ正式統合するかは
  改めて判断する。
- **技カード種別を独立enumにした理由**: 案Bを採用。既存 `MoveCategory` は
  classic/energyモードの実装・テスト資産と強く結び付いており、ここへ
  Technique Deck専用の分類を混在させると将来的な分岐の混乱を招くため。
- **エディタUIを追加しなかった理由**: 案Aを採用。Phase 1はJSON I/O・
  バリデーション・テストの土台整備が目的であり、UIから編集可能にする前に
  デッキ生成・検証（Phase 2）でモデルの使われ方が固まってから着手する方が
  手戻りが少ないと判断した。

---

## Phase 2：新デッキ生成・デッキ検証

**ステータス: 完了。**

推奨実装順（前半・後半とも完了）:

1. ✅ 手動定義したデッキの検証
2. ✅ JSON保存・読込
3. ✅ デッキプレビュー
4. ✅ 最低限の自動生成
5. ✅ 構成不足時の理由表示

最初から強い自動生成AIを作るのではなく、まず「正しいデッキとは何か」を
検証ロジックとして固め（前半）、その上に確認用UI・診断表示・暫定自動生成を
積む（後半）方針を通した。

### 前半（手動デッキの検証・JSON入出力）

成果物: `lib/src/technique_deck/technique_deck_deck.dart`（`TechniqueDeckEntry`
/ `TechniqueDeckDefinition` / `TechniqueDeckBuilder` / `TechniqueDeckValidator`
/ `TechniqueDeckBuildResult` / `TechniqueDeckValidationRule`）、
`test/technique_deck_deck_test.dart`（24テスト）。加えて Phase 1モデルへ
`KickOutCardCategory { normal, finisherEscape }` と `TechniqueDefenseCard.
kickOutCategory` を追加（仕様書9.1章）。

- `TechniqueDeckEntry`（デッキ内の1枚の物理カード、`instanceId`/`cardId`/
  `cardType`）と `TechniqueDeckDefinition`（`id`/`wrestlerId`/`name`/
  `entries`）のJSON入出力
- `TechniqueDeckBuilder`（手動デッキ組み立ての補助。カードIDと枚数を渡すと
  インスタンスIDを自動採番する。強い自動生成AIではない）
- `TechniqueDeckValidator`（`TechniqueDeckValidationRule` 17種のエラー・
  警告ルール。デッキ枚数30枚固定・カードID解決・宣言cardTypeとカタログ実態の
  整合性・同名上限（4.2章の表）・フィニッシャー合計3枚＆同名禁止・固有技/
  フィニッシャーの`allowedWrestlerIds`必須＆デッキレスラーとの一致・
  技エネルギー0枚・特殊キックアウト0枚警告・攻撃/返技エネルギーの属性
  カバレッジ警告・技カード枚数過少警告・エネルギー比率極端警告・
  使用可能レベルの技が皆無警告）
- `TechniqueDeckBuildResult`（`isValid`/`errors`/`warnings`）

### 後半（デッキプレビューUI・診断表示・JSON入出力UI・暫定自動生成）

成果物:

- `lib/src/technique_deck/technique_deck_builder_screen.dart` — 管理画面
  「Technique Deck Builder（テクニックデッキ）」。既存
  `DebugScreen`（`lib/src/screens.dart`）からDeck Simulatorボタンの直後に
  導線を追加した。「開発中：Technique Deck Rules Phase 2 / このデッキは
  まだ試合では使用されません」バナーを常時表示する。
- `lib/src/technique_deck/technique_deck_generator.dart` —
  `TechniqueDeckAutoGenerator` / `TechniqueDeckGenerationConfig` /
  `TechniqueDeckGenerationResult`。検証を通過する30枚（暫定枚数）を機械的に
  組み立てる。**強いデッキ構築AIではない。**
- `lib/src/technique_deck/technique_deck_storage.dart` — `TechniqueDeckSaveRecord`
  / `TechniqueDeckRepository` / `LocalTechniqueDeckRepository`。
  `SharedPreferences` キー `technique_deck_definitions_v1`
  （既存の `one_night_match_wrestler_editor_v04` 等とは独立した名前空間）。
- `lib/src/technique_deck/technique_deck_defaults.dart` — 画面を実際に
  動かすための**暫定サンプルカタログ**（`buildProvisionalTechniqueDeckCatalog()`）。
  既存レスラー `wrestler_akari` / `wrestler_jack`
  （`lib/src/wrestler_editor/defaults.dart`）のIDを
  `allowedWrestlerIds` の例として借用しているが、**ゲームバランス調整済みの
  正式カードデータではない**。正式データ投入は別タスク（未着手、下記参照）。
- `lib/src/technique_deck/technique_deck_file_io.dart`
  （+ `_web.dart` / `_stub.dart`） — `report_export.dart`
  （`lib/src/level_match/`）と同じ条件付きexportパターンで、Web環境のみ
  ファイル選択→読込に対応（それ以外はテキスト貼り付けにフォールバック）。
- テスト: `test/technique_deck_generator_test.dart`（13テスト）、
  `test/technique_deck_storage_test.dart`（11テスト）、
  `test/technique_deck_builder_screen_test.dart`（10ウィジェットテスト）。

実装対象（今回完了分、詳細は作業報告を参照）:

- デッキプレビューUI（カード種別ごとの折りたたみ表示、増減ボタン、即時再検証）
- 検証結果・構成不足理由の表示（エラーは赤・保存不可、警告は黄・保存可、
  各issueへ修正提案の文章を付与）
- 属性バランス表示（6属性 × エネルギー枚数/必要コスト/該当技数、参考値）
- 使用可能・使用不能カードの一覧（使用不能理由つき）
- JSON入出力（コピー・ファイル出力・貼り付け読込・ファイル読込・現在デッキへ
  上書き・別名複製）
- 暫定自動生成（`TechniqueDeckAutoGenerator`。フィニッシャー/固有技/通常技/
  エネルギー/防御カードの順に候補を割り当て、不足時は通常技→エネルギーで
  端数調整。生成後は必ず`TechniqueDeckValidator`を通し、エラーが残る場合は
  `success: false`とする）
- デッキ保存（`schemaVersion`必須、`generatorVersion`は自動生成時のみ記録）
- UI安全策（未保存変更表示、レスラー変更/自動生成前/JSON読込前の確認、
  同名上限・フィニッシャー3枚到達時の追加ボタン無効化、使用不能カードの
  追加不可、30枚超過時の赤表示）

今回完了していない（次回以降）:

- 技エネルギーカード・技カード・防御カードそのものの正式な「生成」
  （実データ投入。今回は動作確認用の暫定サンプルカタログのみ）
- カード編集UI（カタログ自体の追加・編集は対象外。今回はデッキ編集のみ）
- Technique Deck Rules専用の実戦エンジンへの接続（Phase 4以降）

現行デッキビルダー（`LevelMatchDeckBuilder`）・Deck Simulator・レスラー
エディタは変更していない。新モード専用の画面・クラスとして新規作成した。

### JSON例（`TechniqueDeckDefinition.toJson()`）

```json
{
  "id": "wrestler_akari_20260804",
  "wrestlerId": "wrestler_akari",
  "name": "火神アカリ 暫定デッキ",
  "entries": [
    { "instanceId": "td_normal_strike_1_#1", "cardId": "td_normal_strike_1", "cardType": "technique" },
    { "instanceId": "td_energy_strike_#1", "cardId": "td_energy_strike", "cardType": "energy" }
  ]
}
```

保存領域（`TechniqueDeckSaveRecord.toJson()`）はこれに `deckId` / `createdAt`
/ `updatedAt` / `schemaVersion` / `generatorVersion`（自動生成時のみ） /
`notes` を加えたもの。

**依存関係**: Phase 1（カードデータモデル）。

---

## Phase 3：スタンド・ダウン・休息（最初のプレイアブル）

**ステータス: 完了（縮小スコープ版）。**

Deck Simulator・Technique Deck Builderの拡充よりプレイアブル化を優先する
方針判断のもと、当初計画の全項目ではなく「試合を1つ起動して、状態・ターン・
手札・山札が実際に動く」ことに絞った縮小スコープで実装した。

実装対象（今回完了分）:

- レスラー状態（`stand` / `down`。`fatigued`はenum上は既存だが、ダメージが
  まだ無いため到達しない状態として未使用）
- ターン進行（開始→ドロー→エネルギーセット→終了。技の使用＝メインアクション
  はまだ無いため、エネルギーセット後は即座にプレイヤーの行動待ちとなる）
- ターン開始時のスタンド復帰（仕様書11.4章）
- 休息アクション（ダウン中のみ。HPを回復力分回復し、ターンを終了する）
- レスラー別回復力（`TechniqueDeckWrestlerProfile.recoveryPower`は未接続。
  暫定値 `defaultRecoveryPower`（15、正式値ではない）を全レスラー共通で使用）
- HP／HEAT表示（HEATは変動なし。ダメージがまだ無いためHPも変動しない。
  休息によるHP回復のみ動作する）
- 手札5枚ドロー、山札・捨て札の表示、山札切れ時の捨て札再シャッフル
  （仕様書13章。捨て札も空の場合は何も起きない＝open questions 4番は
  未決定のまま、最小実装として無害な無操作にした）

今回完了していない（Phase 4以降）:

- 縦／横表示（UI）としての明示的な演出（今回はカラーバッジ表示のみ）
- ダウンさせる技（`causesDown`）・ダウン中限定技（`targetState`）
  （技の使用自体がPhase 4）
- HP0時の疲労状態（ダメージが無いため到達しない）
- レスラーごとの`recoveryPower`のカタログ接続（暫定共通値のまま）

成果物: `lib/src/technique_deck/technique_match_state.dart`
（`TechniqueMatchPhase` / `TechniqueMatchPlayerState` / `TechniqueMatchState` /
`TechniqueMatchEngine`）、`lib/src/technique_deck/technique_match_screen.dart`
（「Technique Match」画面。`DebugScreen`からTechnique Deck Builderの直後に
導線を追加）。テスト: `test/technique_match_state_test.dart`（17テスト）、
`test/technique_match_screen_test.dart`（6ウィジェットテスト）。

Player A / Player Bの2人零面（CPU無し）。保存済みTechnique Deckがあれば
それを使用し、無ければ`TechniqueDeckAutoGenerator`で仮デッキを自動生成して
試合開始する（保存を強制せず、プレイアブル化の摩擦を減らす判断）。

HP0時の細かな行動制限（[open questions 3番](technique_deck_open_questions.md)）は
未決定事項が解決するまで、最小実装（例: 制限なし）またはフラグで切替可能な実装に
留める（ダメージ自体が無いため、現時点では到達しない）。

**依存関係**: Phase 1（状態パラメータ定義）。Phase 2とは独立して並行着手可能。

---

## Phase 4：単発技の使用

**ステータス: 完了。**

実装対象（すべて完了）:

- 手札から技カードを1枚使用する基本フロー（`TechniqueMatchEngine.useMove`）
- エネルギーセットの実質化（`TechniqueMatchEngine.setEnergy`。手札の
  エネルギーカードを永続的な属性別プールへ移す。仕様書3.3章の
  「使用済みエネルギーの回復」も自分のターン開始時に実装）
- 攻撃エネルギー消費（即時。使用可能量は`availableEnergyFor()` = セット済み
  総数 − 使用済み）
- 状態・レベル・レスラー条件判定（`TechniqueMatchEngine.canUseMove`。
  `targetState`・`minimumLevel`・固有技/フィニッシャーの`allowedWrestlerIds`）
- 技カードの捨て札化（使用後は必ず捨て札。Phase 4には防御が無いため常に成立）
- ダメージ適用（即時。HPは0未満にしない）
- HEAT処理（即時、`heatDelta`をそのまま加算）
- ダウン付与（`causesDown`。相手が既に疲労状態なら上書きしない）
- HP0到達時の疲労状態への移行（`WrestlerPosture.fatigued`）
- ログ出力（技使用・ダメージ・HEAT上昇・ダウン/疲労を1行ずつ記録）
- UI（技選択ダイアログ〜使用結果反映、`TechniqueMatchScreen`）

**ダメージ適用方式の判断（open questions 1番）**: 即時適用を「暫定ではなく
現時点の有力候補」として採用（ユーザー指示）。単発技のみのPhase 4では
一括適用との結果差が無いため、抽象的な保留ダメージ機構を先行実装せず、
最短で確定可能な即時適用を選んだ。理由: 技Aの成立で相手がダウンし、
直後にダウン限定技Bが使用可能になるという連携（`targetState`による判定）を
成立させるには即時反映が必須。Phase 5（連続攻撃）でも、この方式を維持する
方が自然という判断を踏まえて実装している（`technique_match_state.dart`の
モジュール冒頭コメント参照）。

フォール・ギブアップ・フィニッシャー効果（`hasPinEffect` /
`hasSubmissionEffect` / `hasFinisherEffect`）は技の属性としてカードに
残るのみで、決着処理へは接続していない（Phase 6・7）。

今回のPhase 4スコープでは扱わなかったもの:

- 返技・連続攻撃（Phase 5。Phase 4には防御が一切無く、技は必ず成立する）
- フォール／ギブアップ／フィニッシャーの決着（Phase 6・7）
- レベル変更アクション（プレイヤーの`level`は1で固定。open questions 12番は
  未解決のまま）
- レスラー別`recoveryPower`のカタログ接続（Phase 3から持ち越し、
  open questions 23番）

成果物: `TechniqueMatchEngine.setEnergy` / `canUseMove` / `useMove`、
`TechniqueMoveResult`。`TechniqueMatchPlayerState`へ`level` /
`energyPool` / `spentEnergy`を追加。`TechniqueMatchScreen`の手札チップを
タップ可能にし、技/エネルギーカードごとの選択ダイアログを追加。
テスト: `test/technique_match_state_test.dart`に13件追加（計30件）、
`test/technique_match_screen_test.dart`に2件追加（計8件）。

**依存関係**: Phase 1（カード）、Phase 3（状態）。

---

## Phase 5：返技エネルギーと連続攻撃

**ステータス: 完了。**

実装対象（すべて完了）:

- 対応カードなしのエネルギー防御（`counterAttack`。手札の返技カードは不要、
  技カードの`reversalEnergyCost`のみを参照する）
- 技の完全無効化（返技成功時はダメージ無効・HEAT加算なし・ダウンなし）
- 防御された技の捨て札化（攻撃宣言時点で捨て札化済み。成立可否を問わない
  仕様書6章の原則を踏襲）
- 追加技の使用（連続攻撃。返技成功で攻守交代し、新しい攻撃側が
  通常技・固有技のどちらでも宣言できる）
- 使用上限なし（ルール仕様どおり。実装上は`maxRallyChain`で安全弁）
- 継続／終了選択（プレイヤーが任意のタイミングで`endRally`を選べる。
  CPUはPhase 8）
- 連続ダメージ集計は不要になった: Phase 4に続き**技ごとの即時適用**を採用
  （ユーザー指示、下記「ダメージ適用方式の判断」参照）
- 攻防履歴の記録（ログに`[Chain N]`形式で宣言・返技・成立を記録）
- 演出キューは未実装（Phase 9のUI仕上げで検討）

**無限ループ防止の安全弁**: `TechniqueMatchEngine.maxRallyChain`（20）。
`declareAttack`は`rallyChain >= maxRallyChain`の場合、宣言を拒否して
ラリーを強制終了し、ログに`Chain Limit`を残す。300試合×25ターンの
簡易シミュレーションでは最大到達Chainは6（安全弁は一度も発動せず、
通常プレイでは十分な余裕がある値と確認できた。詳細は作業報告のシミュレーション
結果を参照）。

### 読み合いの設計（ユーザー指示による重要な設計判断）

返技は「返技エネルギーが足りていれば自動的に発生する」のではなく、
**防御側が明示的に選択する**（`counterAttack`を呼ばない限り消費されない）。
UIでは返技判定ダイアログで「返技する」（エネルギーが足りる場合のみ活性化）
と「返技しない」を常に両方提示する。エネルギーが足りていてもあえて温存する
（＝返技しない）という選択が可能であることが、このフェーズの核となる
読み合い要素。

### ダメージ適用方式の判断（open questions 1番、正式決定）

Phase 4に続き、Phase 5でも技ごとの即時適用を採用した。技Aの成立で相手が
ダウンし、直後にダウン限定技Bが使用可能になる連携（`targetState`判定）を
成立させるには即時反映が必要という、Phase 4時点の判断がそのままPhase 5にも
当てはまることを確認した上での採用。

### 「ラリー」と「ターン」の分離

ラリー中に攻守（`rallyAttackerIndex`）が入れ替わっても、公式な「ターン」の
所有者（`activePlayerIndex`。ターン開始処理・ドロー・ターン終了操作の主体）
は変化しない。ラリーが終了すると（技が成立／Chain Limit／使用可能技なし／
プレイヤーが終了を選択）、制御は常に`activePlayerIndex`のプレイヤーへ戻る。
エネルギーセットはラリー中は行えない仕様とした（UI側で制限。エンジンの
`setEnergy`自体は`state.active`基準のままのため、ラリー中の呼び出しは
意図しない挙動になりうるという既知の制約が残る。open questions参照）。

成果物: `TechniqueMatchEngine.declareAttack` / `counterAttack` /
`resolveHit` / `endRally` / `canDeclareAttack` / `checkCounterEligibility` /
`hasUsableMove`。`TechniqueMatchState`へ`rallyAttackerIndex` /
`rallyChain` / `pendingAttack`を追加（`TechniquePendingAttack`）。
`TechniqueMatchScreen`に返技判定ダイアログ・Chain表示・攻撃側/防御側
ラベル・「ラリーを終了する」ボタンを追加。
テスト: `test/technique_match_state_test.dart`に10件追加（計40件）、
`test/technique_match_screen_test.dart`に1件追加（計9件）。

**依存関係**: Phase 4（単発技使用が土台）。

---

## Phase 6：フォール・ギブアップ

**ステータス: 完了（CPU判断を除く）。**

ユーザーからの優先順位指定（1.フォール 2.キックアウト 3.ギブアップ
4.ロープブレイク 5.フィニッシャー、フィニッシャーは後回し可）に沿って
実装した。フィニッシャーはPhase 7で扱う。

実装対象（すべて完了）:

- フォール技成立（`resolveHit`が`hasPinEffect`を検出し`pendingEscape`へ移行）
- キックアウトカード（`escapeWithDefenseCard`。通常キックアウトのみ、
  特殊キックアウトは対象外＝仕様書9.1章どおり）
- 返技エネルギーによるキックアウト（`escapeWithReversalEnergy`。Phase 5の
  返技と同じ`reversalEnergyCost`フィールドを再利用）
- HPキックアウト（`escapeWithHp`。`kickOutThreshold`以上の現在HPが必要、
  `kickOutHpRate`＝現在HPに対する割合を消費。HP0到達時は疲労状態へ）
- ギブアップ技成立（`resolveHit`が`hasSubmissionEffect`を検出）
- ロープブレイク（`escapeWithDefenseCard`、ギブアップ版）
- 返技エネルギーによる耐久（`escapeWithReversalEnergy`と共通実装）
- HP耐久（`escapeWithHp`。`giveUpThreshold`以上の現在HPが必要、
  `giveUpHpCost`＝**固定値**を消費。open questions 7番、正式決定）
- 決着処理（`concede`。回避しない/できない場合に`winnerIndex`・`winReason`を
  セットし、エンジン初の勝敗確定処理となった）
- CPU判断は**未実装**（Phase 8。現状はプレイヤーが両者とも人間の想定）
- ログ・演出（ログ文言のみ実装。専用の演出は今回スコープ外）

今回のPhase 6スコープでは扱わなかったもの:

- フィニッシャー技（`hasFinisherEffect == true`のカード）は`resolveHit`の
  フォール／ギブアップ判定から明示的に除外した（Phase 7でフィニッシャー
  専用の決着処理を実装するまでは通常の技として扱われる。フォール／
  ギブアップ効果を同時に持っていても発火しない）
- 特殊キックアウトカード（`KickOutCardCategory.finisherEscape`）は
  Phase 6の対象外（Phase 7でフィニッシャー成立後の脱出手段として実装）
- フォール／ギブアップ両方が成立する技（実運用では想定しないが、モデル上は
  設定可能）は仕様書どおりフォールを優先する

### Phase 5の潜在的な抜けを合わせて修正

Phase 5時点で`goDown` / `rest` / `endTurn` / `setEnergy`にラリー中・
決着判定待ちの間の実行を防ぐエンジン側ガードが無く、UIがボタンを隠して
いることのみで防いでいた。Phase 6の`pendingEscape` / `winnerIndex`導入に
合わせてエンジン側にもガードを追加した（該当状態では状態を変化させず
no-opする）。

### open questions 7番の決定（ギブアップ時のHP消費方式）

「固定値／最大HP割合／現在HP割合」のうち**固定値**を採用した
（`giveUpHpCost`）。フォールの`kickOutHpRate`（現在HPに対する割合）とは
明確に異なる方式とすることで、キックアウトとギブアップの回避コストの
性質を区別した（フィールド名の`Cost`＝固定額 / `Rate`＝割合、という
命名慣習にも合わせた）。

成果物: `TechniqueMatchEngine.canEscapeWithDefenseCard` /
`escapeWithDefenseCard` / `canEscapeWithReversalEnergy` /
`escapeWithReversalEnergy` / `canEscapeWithHp` / `escapeWithHp` /
`concede`。`TechniqueMatchState`へ`pendingEscape` / `winnerIndex` /
`winReason`を追加（`TechniqueEscapeKind` / `TechniquePendingEscape`）。
`TechniqueMatchScreen`に回避判定ダイアログ・勝利バナーを追加。
テスト: `test/technique_match_state_test.dart`に21件追加（計61件）、
`test/technique_match_screen_test.dart`に2件追加（計11件）。

**依存関係**: Phase 4・5（技の成立・連続攻撃の結果としてフォール／ギブアップが
発生する）。

### Phase 6完了後のプレイテストによる軽微修正（Phase 7着手前）

ユーザー指示により、Phase 7へ進む前に自動シミュレーションでのプレイテストを
実施した（人間による実プレイの代替として、ヒューリスティックなボット同士を
対戦させる方式）。

修正済み:

- `TechniqueDeckGenerationConfig.ropeBreakCount`の既定値を0→1に変更
  （`normalCount`を7→6に削減し合計30枚を維持）。従来は自動生成デッキに
  ロープブレイクカードが一枚も入らず、ギブアップをカードで回避する手段が
  存在しなかった（`normalKickOutCount`との非対称、open questions 21番）。
- 技詳細ダイアログに、フォール／ギブアップ効果を持つ技の場合は成立時に
  何が起きるかを明示するテキストを追加（両方持つ場合はフォール優先である
  ことも表示）。ユーザー指摘「カード詳細にも優先順位を表示した方がよい」に
  対応。

### Phase 6完了後・第2ラウンドの軽微修正（ユーザー指示、ゲームサイクル見直し）

上記シミュレーション結果（0試合決着、山札400回以上再構築）を受け、
ユーザーから3点の修正指示があり、すべて実装した（詳細は
[open questions L番](technique_deck_open_questions.md)参照）。

1. **山札再構築上限による時間切れ**: `maxDeckReshuffles`（既定2回）を
   導入。上限後にさらに山札が尽きたら`TechniqueMatchState.isDraw`で
   試合を終了させる（仕様書14章「時間切れ」の初実装）。
2. **キックアウト／ロープブレイクカードの除外**: 使用後は捨て札ではなく
   `TechniqueMatchPlayerState.removedPile`（ゲームから完全除外）へ送る。
3. **ギブアップ条件の緩和**: `downBonusPower`フィールドを新設し、サンプル
   カタログのギブアップ技を`targetState: down`限定から`any`＋ダウン中
   ボーナス威力に変更。

**再検証結果（20試合シミュレーション）**: 無限膠着は解消（全試合が
約40ターンで終了）。ギブアップも初めて発生（56回、修正前は0回）。
一方、**決着（勝敗確定）は依然として0試合**で、全試合が時間切れ引き分けに
終わった。回避181回中176回がカード／返技エネルギーで賄われ、諦めは
一度も発生しなかった。

### Phase 6完了後・第3ラウンドの見直し（ユーザー指示、決定的な改善）

上記の結果を受け、ユーザーから「返技エネルギーによる決着回避の廃止」と
「2人分の正式モデルデッキ構築」の指示があり、実装した（詳細は
[open questions M番](technique_deck_open_questions.md)参照）。

1. **返技エネルギーの用途を分離**: `reversalEnergyCost`はラリー中の返技
   （`counterAttack`。ダメージ無効化・攻守交代）専用とし、フォール／
   ギブアップ／フィニッシャーからの決着回避には使えない仕様へ変更。
   `TechniqueMatchEngine.canEscapeWithReversalEnergy` /
   `escapeWithReversalEnergy`を削除した。決着回避の手段はカード
   （キックアウト／ロープブレイク）とHP消費の2種のみになった。
2. **モデルデッキの新規構築**: 火神アカリ（フォール型：打撃・スピード、
   スタンド技でダウンを奪いフォールへつなぐ）・白銀レイナ（ギブアップ型：
   関節・テクニカル、ダウン技から関節技でギブアップへつなぐ）の正式な
   30枚デッキを`technique_deck_model_decks.dart`に手動構築で追加した
   （`buildAkariPhase6ModelDeck` / `buildReinaPhase6ModelDeck`）。
   ユーザー指定の内訳（技エネルギー13・通常技9・固有技5・通常
   キックアウト1・ロープブレイク1・調整枠1）に準拠し、固有技5種×2人・
   調整枠2種・共有の「テイクダウン」技を`technique_deck_defaults.dart`へ
   新規追加した（`td_p6_*`系ID。既存の`td_sig_akari_1/2`等は変更せず
   残置）。

**再検証結果（モデルデッキ、アカリ対アカリ／レイナ対レイナ／アカリ対
レイナの3パターン、1000試合）**: **決着率100%（時間切れ0%）**を達成
（第2ラウンドの0%から劇的に改善）。アカリ対アカリは全試合フォール勝利
（333/333）、レイナ対レイナは全試合ギブアップ勝利（333/333）、アカリ対
レイナは両方の勝ち筋が機能（フォール212件・ギブアップ121件）。平均ターン
数19〜28、Chain平均1.0（最大3）。

残った副次的な発見（Phase 8以降で検討、open questions 28・29番）:
「ダウン付与→決着技連携成功率」がほぼ0%だった（ただし検証用ボットが
相手の状態を考慮せず高威力技を機械的に即座に使う単純方式のためと考えられ、
連携自体が機能しないという意味ではない。Phase 8で戦略的なCPU実装後に
改めて検証する必要がある）。「技カードを使えないターン」の割合が
42〜47%と高め（要調査）。

### Phase 6完了後・第4ラウンドの見直し（ユーザー指示、原因分析＋4人モデルデッキ完成）

ユーザーから「決着率よりも技カードを使えないターン42〜47%の方がゲーム
体験に影響する。Phase 7の前に原因分析と4レスラー全員分のモデルデッキ
完成を優先すべき」との指示があり、対応した（詳細は
[open questions N番](technique_deck_open_questions.md)参照）。

1. **「技カードを使えないターン」の原因分析**（アカリ対アカリ／レイナ対
   レイナ／アカリ対レイナ、102試合）: 手番ごとに「なぜ技カードを使えな
   かったか」を分類して集計した結果、**主因は`targetState`
   （スタンド／ダウン限定）のミスマッチ（42.2%）であり、エネルギー不足が
   主因ではない**（エネルギー不足のみが原因だったのは18.2%、スタックした
   ターンの平均使用可能エネルギーは6.98で0だった割合はわずか0.7%）ことが
   判明した。モデルデッキの技構成が「スタンド限定の起き攻め技」と「ダウン
   限定の決着技」に偏っていることが背景と考えられる。対応（`targetState:
   any`比率を増やす等）は本ラウンドでは未実施（原因特定を優先）。
2. **4レスラー全員分のモデルデッキ完成**: 豪田ミサキ（パワー・投げ型、
   低HP高火力、フォール型）・黒蝶ジャック（ラフファイト・関節型、
   ギブアップ型）のモデルデッキを追加し、火神アカリ・白銀レイナと合わせて
   4人全員分が揃った（フォール型2人＋ギブアップ型2人）。
   `buildMisakiPhase6ModelDeck` / `buildJackPhase6ModelDeck`（新規）。

**再検証結果（4人全組み合わせ、10通り×10試合＝100試合）**:
**決着率100%・時間切れ率0%**（全組み合わせで例外なし）。

**依存関係**: Phase 6。

---

## Phase 7：フィニッシャー

**ステータス: 完了（カットイン演出・決着演出を除く。UIは最小限のダイアログ
実装）**

ユーザー指示（詳細な設計スペック）に基づき、フィニッシャーを通常の
`declareAttack`／`pendingEscape`フローとは完全に分離した独立の状態機械
として実装した。

成果物:

- `lib/src/technique_deck/technique_match_state.dart`:
  - `TechniqueFinisherStage { responsePending, escapePending }` /
    `TechniquePendingFinisher`（`pendingEscape`へは統合せず別系統として保持。
    ユーザー指示）
  - `_checkEligibility`（`canUseMove`/`canDeclareAttack`/`hasUsableMove`
    共通）で`hasFinisherEffect`を持つ技を明示的に除外し、通常の宣言・返技
    フローに一切乗らないようにした
  - `_checkFinisherRequirements` — カード側`finisherRequirements`
    （`minimumHeat` / `maximumOpponentHp` / `maximumOwnHp` /
    `requiredOpponentState`）を解釈する汎用チェッカー。エンジンに
    レスラー別の条件をハードコードしない
  - `canDeclareFinisher` / `declareFinisher` — 宣言時に攻撃エネルギーを
    消費し手札から除くが、捨て札にはしない（キャンセル時に山札へ戻すため）。
    ラリーは終了し、返技（`reversalEnergyCost`）を経由せず直接
    `responsePending`へ移行する
  - `canCancelFinisher` / `cancelFinisher` — 防御側のエスケープ／リバーサル
    カードのみで発動前キャンセル可能。成功時はダメージ・HEAT・ダウンが
    一切発生せず、フィニッシャーカードは攻撃側の山札へ戻ってシャッフル
    される（捨て札にはしない）。エスケープはラリー終了、リバーサルは
    `rallyAttackerIndex`を交代させる主導権移動
  - `resolveFinisher` — キャンセルされなければ`_resolveAttack`を再利用して
    即座にダメージ・HEAT・ダウンを反映し、フィニッシャーカードを捨て札へ
    送って`escapePending`へ移行する
  - `canEscapeFinisher` / `escapeFinisher` — `KickOutCardCategory.
    finisherEscape`の特殊キックアウトカードのみで脱出可能（通常キックアウト・
    ロープブレイク・HP消費・返技エネルギーはすべて不可）。成功したカードは
    `removedPile`へ（Phase 6の通常キックアウトと同じ、ゲームから完全除外）
  - `concedeFinisher` — 脱出できなければ残りHPに関係なく攻撃側の即勝利
    （`winReason: 'フィニッシャー勝利'`）
- `lib/src/technique_deck/technique_match_screen.dart`: 宣言・発動キャンセル
  判定ダイアログ・成立後脱出判定ダイアログ・手札詳細シートのフィニッシャー
  専用分岐を追加（カットイン演出等の専用UIはPhase 9で検討）
- `lib/src/technique_deck/technique_deck_defaults.dart`: 4人×3枚
  （`td_p7_*_fin_*`、計12枚）のフィニッシャーカードを追加。ユーザー指定の
  テンプレート「1枚は`targetState: any`・1枚はレスラーの得意状態・1枚は
  条件付きの高性能技」に沿い、`finisherRequirements`もレスラーごとに変えた
  （アカリ=HEAT重視、ミサキ=相手低HP重視、レイナ=相手ダウン重視、
  ジャック=自分低HP重視）
- `lib/src/technique_deck/technique_deck_model_decks.dart`:
  `buildAkariPhase7ModelDeck` / `buildMisakiPhase7ModelDeck` /
  `buildReinaPhase7ModelDeck` / `buildJackPhase7ModelDeck`（各30枚。
  Phase 6モデルデッキから通常技を9→6枚に減らし、フィニッシャー3枚・
  エスケープ1枚・リバーサル1枚・特殊キックアウト1枚を追加）
- テスト: `test/technique_match_state_test.dart`（Phase 7エンジンテスト12件）・
  `test/technique_match_screen_test.dart`（フィニッシャーUIテスト2件）・
  `test/technique_deck_model_decks_test.dart`（Phase 7モデルデッキ検証12件）

**検証結果（4人モデルデッキ全10組み合わせ×100試合＝1000試合の
シミュレーション）**: [open questions O番](technique_deck_open_questions.md)
を参照。

**依存関係**: Phase 6（フォール／ギブアップの仕組みの上にフィニッシャーの
特殊ケースとして構築する）。

---

## Phase 7.5：モデルデッキ最適化・フィニッシャー条件分散・検証Bot改善

**ステータス: 完了・終了（ユーザー判断）。これ以上の検証Botのスコア調整は
行わない。目標レンジは未達成のまま残るが、原因（「カードの価値」は評価
できても「今使う価値＝温存判断」を評価できない検証Botの構造的限界）は
特定済みであり、対応はPhase 8の正式CPU実装（[CPU設計書]
(technique_deck_cpu_design.md)参照）に委ねる**

Phase 7の1000試合検証で目標レンジからの逸脱（宣言率76.5%・決着率47.2%・
通常決着率52.8%・使えないターン率59.4%）が判明した際、ユーザーから
「ルール側の数値調整（HEAT閾値・威力・宣言確率）を今行うのは早い。検証
Botが“必殺技を温存する”という発想を持たないことが真因ではないか」との
指摘を受け、Phase 8（CPU）へ進む前に**ルールの数値ではなく「モデルデッキ」
と「検証Bot」を改善して再検証する**専用ラウンドを挟んだ。

成果物:

- `lib/src/technique_deck/technique_deck_defaults.dart`: アカリ・ミサキ・
  ジャックの「得意状態限定」フィニッシャー枠から追加条件を撤去し
  （`finisherRequirements: {}`）、3枚すべてが同じ条件（アカリの場合
  `minimumHeat: 60`）に偏っていた問題を解消
- `lib/src/technique_deck/technique_deck_model_decks.dart`:
  `build{Akari,Misaki,Reina,Jack}Phase75ModelDeck`（各30枚。通常技6→8枚・
  固有技3→2枚・フィニッシャー3→2枚）
- `test/technique_deck_model_decks_test.dart`にPhase 7.5モデルデッキの
  検証テスト12件を追加
- 検証専用の使い捨てシミュレーションBotを、ユーザー指定の加点式スコアリング
  （相手HP・自分HP・相手ダウン状態・相手の防御札所持状況・自分のHEAT
  蓄積状況を加減点し、スコアが正の場合のみ宣言）へ変更（コミット前に削除、
  ルール本体・CPU実装には含まれない）

**再検証結果（4人×Phase 7.5モデルデッキ全10組み合わせ×100試合＝1000試合）**:
[open questions P番](technique_deck_open_questions.md)を参照。要約すると、
火神アカリの個体差（ミラー戦のみ宣言率1.0%）は解消し、技を使えないターン率も
59.4%→54.3%へ改善したが、**フィニッシャー宣言率はユーザーの想定に反して
76.5%→88.9%へ悪化**した。原因はフィニッシャー条件分散とモデルデッキの
フィニッシャー選定（`minimumHeat`条件を持たないカードを多く採用したこと）が
検証Botのスコアリングと噛み合わなかったためと分析している。数値そのもの
（スコアの重み・HEAT閾値・威力）は本ラウンドでは調整していない。

**依存関係**: Phase 7。

---

## Phase 7A：レスラーカード・技カード・モデルデッキ実装（正式データ）

**ステータス: 完了。**

ユーザー指示により、Phase 8（CPU実装）の前に「ゲームバランス調整ではなく、
4人分の正式な基準データをゲームへ実装する」専用ラウンドを挟んだ。
`TechniqueMatchEngine`・ダメージ計算・ラリー・フォール・ギブアップ・
フィニッシャー処理・CPU・シミュレーションには一切手を加えない、**データ
追加のみ**のフェーズ。

成果物:

- **立ち絵**: ユーザー添付のレスラー4人分リファレンス画像（チェッカー
  ボード背景、一部キャラクターは衣装の色がチェッカーボードと近く単純な
  閾値処理では誤消去される問題があった）から、グリッド認識＋メディアン
  フィルタによる背景除去スクリプトで4人分を切り出し、
  `assets/images/wrestlers/{akari,misaki,reina,jack}.png`として収録
  （新規イラスト生成はしていない）。
  `lib/src/technique_deck/technique_wrestler_portraits.dart`の
  `techniqueWrestlerPortraits`マップを4人分に更新（Ver.2まではアカリ・
  ミサキの2人分のみだった）。
- **①レスラーカード**: `TechniqueDeckWrestlerProfile`
  （`technique_deck_models.dart`）へ`name`・`hp`・`initialHeat`・
  `attributeBonus`（打撃/投げ/関節/飛び/ラフの補正値、既存の
  `_costMapFromJson`/`_costMapToJson`を流用）・`passiveAbility`・
  `description`・`imagePath`・`themeColor`を追加（既存の`wrestlerId`・
  `recoveryPower`・`allowedSignatureCardIds`・`allowedFinisherCardIds`は
  維持）。`hp`・`themeColor`は既存の`WrestlerDefinition`
  （classic/energyモード、`wrestler_editor/defaults.dart`）の値を踏襲。
  4人分のデータを`technique_deck_wrestler_catalog.dart`の
  `buildTechniqueDeckWrestlerCatalog()`として新規追加。実戦エンジンへは
  未接続（データ保持のみ。試合開始時HP/HEATは引き続き既存の
  `WrestlerDefinition.maxHp`／HEAT初期値0を使用）。
- **②技カードのimagePath**: `TechniqueDeckTechniqueCard`へ`imagePath`
  （nullable）を追加。技専用イラストは無いため全カードnull（構造のみ
  用意、画面側はアイコンへフォールバック）。
- **③48枚の技カード**: `technique_deck_defaults.dart`へ
  `td_p7a_{akari,misaki,reina,jack}_{normal,sig,fin}_*`として、ユーザー
  指定の技名（各12枚＝通常技8・固有技2・フィニッシャー2）を追加。
  フィニッシャーの発動条件はPhase 7.5で判明した「全員HEATのみで揃えると
  宣言率が偏る」問題を踏まえ、レスラーごとに異なる条件軸（アカリ:HEAT、
  ミサキ:相手HP、レイナ:HEAT、ジャック:自分HP）を採用し、2枚目は
  `targetState`による状態限定のみとした。
- **④4人分のPhase 7Aモデルデッキ**: `technique_deck_model_decks.dart`へ
  `build{Akari,Misaki,Reina,Jack}Phase7AModelDeck`
  （各30枚: 技エネルギー13・通常技8・固有技4・フィニッシャー2・通常
  キックアウト1・ロープブレイク1・特殊キックアウト1。**エスケープ・
  リバーサルを含まない**、ユーザー指定の内訳）を追加。固有技4枚は
  バリデータの同名上限（固有技は同名1枚まで）があるため、新規2種
  （各1枚）に加え既存Phase 6固有技から2種を1枚ずつ採用して満たした。
  4デッキとも検証エラー・警告ともに0件。`wrestlerId`→デッキ構築関数の
  一覧として`techniquePhase7AModelDeckBuilders`
  （`findTechniquePhase7AModelDeck`）も追加。
- **⑤デッキ構築画面**: `TechniqueDeckBuilderScreen`へ「モデルデッキ読込」
  ボタンを追加。選択中レスラーにPhase 7Aモデルデッキが存在すれば有効化され、
  ワンタップで現在の編集内容をそのモデルデッキで上書きする。
- **⑥Technique Matchのデッキ解決優先度変更**:
  `TechniqueMatchScreen._resolveDeck()`を「保存済みデッキ→モデルデッキ→
  AutoGenerator」の優先順に変更（従来は保存済みデッキ→AutoGeneratorの
  2段階）。`TechniqueMatchEngine`自体は無改修。

**依存関係**: Phase 2（デッキ検証・自動生成）、Phase 7（フィニッシャー）。

---

## Phase 8：CPU・シミュレーション

**ステータス: 未着手（設計書は完成済み）**

Phase 7.5完了後のユーザー指示により、CPUの実装に入る前に設計を確定させた
（[`technique_deck_cpu_design.md`](technique_deck_cpu_design.md)）。以下の
サブフェーズ構成で段階的に実装する（ユーザー指定の順序）。CPUの思考ログ
（Decision Trace）を各段階から組み込む点が本設計の核。

| サブフェーズ | 内容 | ステータス |
|---|---|---|
| Phase 8.0 | CPU基盤: `TechniqueCpuLevel` enum・CPUコントローラのAPI骨格・
  `TechniqueCpuDecisionTrace`データモデル（JSON変換込み） | 未着手 |
| Phase 8.1 | CPU Level 1（初心者、Phase 7.5検証Botの正式な後継） | 未着手 |
| Phase 8.2 | CPU Level 2（中級：フォール率・HP・防御札の残数を自分の
  観測情報のみで評価） | 未着手 |
| Phase 8.3 | CPU Level 3（上級：手札予測・デッキ残数・エネルギー効率・
  フィニッシャー温存） | 未着手 |
| Phase 8.4 | 1000試合シミュレーション（CPU対CPU、Decision Traceで分析、
  目標レンジと再比較） | 未着手 |
| Phase 8.5 | 必要ならモデルデッキ・カード数値を調整（CPUの意思決定込みで
  検証して初めて着手する） | 未着手 |

実装対象の詳細（各サブフェーズに割り振る）:

- 新ルール専用CPU（現行 `_scoreMoveFor` / `CpuDifficulty` とは独立した新規
  設計。既存モードへの変更・依存は非目標のまま）
- 攻撃エネルギーと返技エネルギーの温存判断（Level 3）
- 連続攻撃の継続／終了判断（Level 2〜3）
- フィニッシャー対策（発動条件を読んで警戒する、エスケープ／リバーサルを
  適切に温存する。Level 3）
- ダウン追撃の判断（Level 2〜3）
- 休息の判断（Level 1〜3）
- CPU対CPUシミュレーション・Decision Traceの記録（Phase 8.4）
- デッキ評価・Deck Simulator対応（`DeckSimConfig` / `DeckBalanceReport` を
  新モードへ拡張するか、新モード専用のシミュレータを用意するかは実装時に
  判断。優先度は低く、Phase 8.5以降）
- 観戦性評価（既存 `EntertainmentScore` の考え方を踏襲するか再設計するか。
  優先度は低い）

**依存関係**: Phase 4〜7.5（ルール全体の実装完了後でなければAIの意思決定を
正しく評価できない）。

---

## Phase 9：チュートリアル・UI完成

実装対象:

- カード役割説明
- 技の連鎖表示（連続攻撃の見せ方）
- 使用可能理由／不可能理由の明示
- スタンド／ダウン表示の作り込み
- フィニッシャー防御選択（エスケープ／リバーサル／キックアウト）のUI
- フォール・ギブアップ選択UI
- スポットライトチュートリアル
- ログ出力の仕上げ
- リザルト分析画面

**依存関係**: Phase 3〜8（機能が出揃った後の仕上げ）。

---

## Phase 10：将来拡張（本計画の対象外）

今回は実装しない。参考のため項目のみ列挙する。

- ロープ
- 場外
- コーナー
- トップロープ
- エプロン
- 反則
- 場外カウント
- タッグ
- 複数ラウンド

---

## 依存関係の概観

```
Phase 0 (仕様保存)
   │
   ▼
Phase 1 (データモデル)
   │
   ├──▶ Phase 2 (デッキ生成・検証)
   │
   └──▶ Phase 3 (スタンド/ダウン/休息)
              │
              ▼
        Phase 4 (単発技の使用)
              │
              ▼
        Phase 5 (返技エネルギー・連続攻撃) ※無限ループ安全弁必須
              │
              ▼
        Phase 6 (フォール・ギブアップ)
              │
              ▼
        Phase 7 (フィニッシャー)
              │
              ▼
        Phase 8 (CPU・シミュレーション)
              │
              ▼
        Phase 9 (チュートリアル・UI完成)

Phase 10 (将来拡張) — 独立、今回スコープ外
```

Phase 2とPhase 3は互いに依存せず並行着手できるが、Phase 4以降は前Phaseの
成果に直列に依存する。各Phase完了時点で、独立したテストが通る状態を維持する
（大きな未完成コミットを作らない）。
