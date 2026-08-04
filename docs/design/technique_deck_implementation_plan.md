# Technique Deck Rules — 段階実装計画

- ステータス: **Phase 0（本書自体が成果物） 完了時点**
- 対象仕様: [`technique_deck_rules.md`](../rules/technique_deck_rules.md)
- 未決定事項: [`technique_deck_open_questions.md`](technique_deck_open_questions.md)

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

実装対象:

- 新ルールモード識別子（`ResourceMode.techniqueDeck` 案、または既存
  `MatchResourceMode` に3値目を追加するか、別enumとして独立させるかを設計判断する）
- 技カード種別（`normal` / `signature` / `finisher`。既存 `MoveCategory` を
  拡張するか新設するかは仕様書3章の案A/案Bから選定する）
- 攻撃エネルギーコスト（`attackEnergyCost`）
- 返技エネルギーコスト（`reversalEnergyCost`）
- 使用可能レスラー（`allowedWrestlers`）
- 対象状態（`targetState`）
- ダウン効果（`causesDown`）
- フォール・ギブアップ・フィニッシャー用パラメータ
  （`kickOutThreshold` / `kickOutHpRate` / `giveUpThreshold` / `giveUpHpCost` /
  `finisherRequirements` / `cannotEscape`）
- JSON入出力
- 後方互換（既存 `WrestlerDefinition` / `MoveDefinition` のJSON往復に新フィールドが
  混入しても既存モードの読み込みが壊れないこと）
- エディタ項目（wrestler_editor側での表示・編集。ただし新モード向けUIは
  Phase 9まで最小限でよい）

この段階では実戦ロジック（`LevelMatchEngine` 相当のTechnique Deck版）へ接続しなくてよい。
データモデルの単体テストのみで完結させる。

**依存関係**: Phase 0（仕様確定）。

---

## Phase 2：新デッキ生成・デッキ検証

実装対象:

- 技エネルギーカードの生成
- 通常技・固有技・フィニッシャーカードの生成
- 特殊防御カードの生成
- フィニッシャー最大3枚・同名フィニッシャー禁止のバリデーション
- レスラー使用制限（`allowedWrestlers`）のバリデーション
- デッキバリデーション全般
- 自動生成デッキ
- デッキプレビュー
- JSON出力

現行デッキビルダー（`LevelMatchDeckBuilder`）は変更せず、新モード専用ビルダー
（例: `TechniqueDeckBuilder`）を新規作成する。

**依存関係**: Phase 1（カードデータモデル）。

---

## Phase 3：スタンド・ダウン・休息

実装対象:

- レスラー状態（`stand` / `down` / `fatigued`）
- 縦／横表示（UI）
- ダウンさせる技（`causesDown`）
- ダウン中限定技（`targetState`）
- ターン開始時のスタンド復帰
- 休息アクション
- レスラー別回復力（`recoveryPower`）
- HP0時の疲労状態

HP0時の細かな行動制限（[open questions 3番](technique_deck_open_questions.md)）は
未決定事項が解決するまで、最小実装（例: 制限なし）またはフラグで切替可能な実装に
留める。

**依存関係**: Phase 1（状態パラメータ定義）。Phase 2とは独立して並行着手可能。

---

## Phase 4：単発技の使用

実装対象:

- 手札から技カードを1枚使用する基本フロー
- 攻撃エネルギー消費
- 状態・レベル・レスラー条件判定
- 技カードの捨て札化
- ダメージ適用
- HEAT処理
- ダウン付与
- ログ出力
- UI（最小限、技選択〜結果表示）

この段階ではまだ連続攻撃（Phase 5）を実装しない。1ターンに1技のみ成立する
単純化されたフローで、コアループを先に検証する。

**依存関係**: Phase 1（カード）、Phase 3（状態）。

---

## Phase 5：返技エネルギーと連続攻撃

実装対象:

- 対応カードなしのエネルギー防御
- 技の完全無効化
- 防御された技の捨て札化
- 追加技の使用（連続攻撃）
- 使用上限なし（ルール仕様）
- 継続／終了選択（プレイヤー・CPU双方）
- 連続ダメージ集計（即時適用か一括適用かは
  [open questions 1番](technique_deck_open_questions.md) 解決後に実装）
- 攻防履歴の記録
- CPU判断（連続攻撃を続けるか、リソースを温存するか）
- 演出キュー

**無限ループ防止用の安全弁を必ず設ける。** ルール上は使用上限なしでも、
エンジン内部には以下のような防御策を実装すること。

- 1ターンあたりの最大反復回数のハードキャップ（デバッグ・異常系検知用。
  通常プレイでは手札・エネルギーの有限性により到達しない想定だが、
  バグによる無限ループを防ぐ最終防衛ラインとして必須）
- 手札・エネルギーが尽きた時点での強制終了
- 使用可能技が存在しない場合の即時終了（既存 `energy` モードの
  `noUsableMove` ログ機構を参考にできる）

**依存関係**: Phase 4（単発技使用が土台）。

---

## Phase 6：フォール・ギブアップ

実装対象:

- フォール技成立
- キックアウトカード
- 返技エネルギーによるキックアウト
- HPキックアウト（`kickOutThreshold` / `kickOutHpRate`）
- ギブアップ技成立
- ロープブレイク
- 返技エネルギーによる耐久
- HP耐久（`giveUpThreshold` / `giveUpHpCost`）
- 決着処理
- CPU判断（キックアウト／ロープブレイク／HP消費のどれを選ぶか）
- ログ・演出

**依存関係**: Phase 4・5（技の成立・連続攻撃の結果としてフォール／ギブアップが
発生する）。

---

## Phase 7：フィニッシャー

実装対象:

- 発動条件判定（`finisherRequirements`）
- デッキ内最大3枚・同名禁止（Phase 2のバリデーションと連動）
- エスケープカード
- リバーサルカード
- 発動キャンセル処理
- 山札へ戻す（キャンセル成立時）
- シャッフル
- 特殊キックアウトカード
- 高い返技コスト（フィニッシャー用の`reversalEnergyCost`）
- HPに関係しない勝利
- カットイン演出
- 決着演出

**依存関係**: Phase 6（フォール／ギブアップの仕組みの上にフィニッシャーの
特殊ケースとして構築する）。

---

## Phase 8：CPU・シミュレーション

実装対象:

- 新ルール専用CPU（現行 `_scoreMoveFor` / `CpuDifficulty` 相当の再設計）
- 攻撃エネルギーと返技エネルギーの温存判断
- 連続攻撃の継続／終了判断
- フィニッシャー対策（発動条件を読んで警戒する、エスケープ／リバーサルを
  適切に温存する）
- ダウン追撃の判断
- 休息の判断
- デッキ評価
- CPU対CPUシミュレーション
- Deck Simulator対応（`DeckSimConfig` / `DeckBalanceReport` を新モードへ拡張、
  または新モード専用のシミュレータを用意するかは実装時に判断）
- 観戦性評価（既存 `EntertainmentScore` の考え方を踏襲するか再設計するか）

**依存関係**: Phase 4〜7（ルール全体の実装完了後でなければAIの意思決定を
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
