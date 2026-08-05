# Technique Deck Rules — CPU設計書（Phase 8）

- ステータス: **草案（Phase 8着手前の設計文書。コードはまだ存在しない）**
- 対象仕様: [`technique_deck_rules.md`](../rules/technique_deck_rules.md)
- 実装計画: [`technique_deck_implementation_plan.md`](technique_deck_implementation_plan.md)
  Phase 8章
- 未決定事項: [`technique_deck_open_questions.md`](technique_deck_open_questions.md)

## 0. 本書の位置づけ

Phase 7.5完了時点のユーザー判断（要旨）:

> これ以上検証Botを調整するより、Phase8で本番CPUを設計・実装した方が開発
> 効率も品質も高い。CPUを作る前にCPU設計書を作る。CPUの思考ログ
> （Decision Trace）を最初から組み込むことを強くおすすめする。

Phase 7.5の検証Bot（`test/_phase7_sim.dart`・`test/_phase75_sim.dart`、いずれも
使い捨てでコミット前に削除済み）は「カードの価値」しか評価せず、「今この
瞬間に使う価値」（温存判断）を評価できなかった。これがPhase 7.5で宣言率が
76.5%→88.9%へ悪化した根本原因（open questions セクションP参照）。

**本書の役割**: Phase 8で実装する正式CPUの設計を、コードを書く前に確定する。
検証Bot（使い捨てスクリプト）とは異なり、正式CPUは以下を満たす必要がある。

- `lib/src/technique_deck/`配下の永続コードとして実装する（使い捨てではない）
- 相手の手札を覗かない（検証Botは簡略化のため相手の手札を参照していたが、
  正式CPUはプレイヤーと同じ情報のみで判断する。フェアネスの観点で必須）
- 判断根拠を`TechniqueCpuDecisionTrace`としてJSON出力できる（デバッグ・
  バランス調整用。ユーザー必須指示）
- `classic`/`energy`モードの`CpuDifficulty`（`level_match_engine.dart`）とは
  完全に独立した新規enum・新規ファイルとする（既存モードへの依存・変更は
  非目標のまま）

## 1. アーキテクチャ

### 1.1 新規ファイル（Phase 8で実装、現時点では未実装）

- `lib/src/technique_deck/technique_match_cpu.dart` — CPU本体
  （`TechniqueCpuLevel` enum・`TechniqueCpuController`・意思決定関数群）
- `lib/src/technique_deck/technique_cpu_decision_trace.dart` — Decision Trace
  のデータモデル（JSON変換込み）

### 1.2 設計方針

- `TechniqueMatchEngine`（`technique_match_state.dart`）は**一切変更しない**。
  CPUはエンジンの外側から、既存の`canDeclareAttack` / `canDeclareFinisher` /
  `checkCounterEligibility` / `canEscapeWithDefenseCard` / `canEscapeWithHp` /
  `canCancelFinisher` / `canEscapeFinisher`等の「判定のみ行う」公開APIを
  読み取り専用で使い、最終的にどのエンジンメソッド（`declareAttack` /
  `counterAttack` / `resolveHit` / …）を呼ぶかを選ぶだけの薄い層とする。
  これはPhase 6〜7で確立した「エンジンは純粋関数群、UIやBotはその外側から
  呼ぶだけ」という設計を踏襲する。
- `TechniqueMatchEngine.hasFinisherEffect`除外や`pendingFinisher`分離などの
  既存ルールはCPUにとってもブラックボックスであり、CPU側で状態遷移の
  整合性を意識する必要はない（エンジンのガードがすべて担保する）。
- CPUの意思決定関数は`TechniqueMatchEngine`の各メソッドと同じ「純粋関数」
  スタイルとする: `(TechniqueMatchState, TechniqueDeckCardCatalog, TechniqueCpuLevel, Random)
  → (action, TechniqueCpuDecisionTrace)`。副作用を持たず、テストしやすくする。

### 1.3 CPUが担当する意思決定ポイント（既存エンジンAPIとの対応）

| # | 場面 | 判定に使う既存API | 実行する既存API |
|---|---|---|---|
| 1 | エネルギーをセットするか・何をセットするか | `setEnergy`の事前条件（手札のエネルギーカード） | `setEnergy` |
| 2 | 技を宣言する／休息する／ターン終了する | `canDeclareAttack` / `canDeclareFinisher` / `hasUsableMove` | `declareAttack` / `declareFinisher` / `rest` / `endTurn` |
| 3 | 返技を受けるか（防御側） | `checkCounterEligibility` | `counterAttack` / `resolveHit` |
| 4 | ラリーを継続するか・終了するか（攻撃側） | `canDeclareAttack`（次の一手があるか） | 次の技宣言 or `endRally` |
| 5 | フォール／ギブアップから回避するか（防御側） | `canEscapeWithDefenseCard` / `canEscapeWithHp` | `escapeWithDefenseCard` / `escapeWithHp` / `concede` |
| 6 | フィニッシャーをキャンセルするか（防御側） | `canCancelFinisher` | `cancelFinisher` / （何もしない→`resolveFinisher`はUI/シミュレータ側が呼ぶ） |
| 7 | フィニッシャーから脱出するか（防御側） | `canEscapeFinisher` | `escapeFinisher` / `concedeFinisher` |

## 2. CPUレベル設計

`enum TechniqueCpuLevel { level1, level2, level3 }`。ユーザー提示の3段階構成
をそのまま採用する。各レベルは「情報量」と「時間軸の考慮」で差をつける
（Phase 7.5の反省: 情報を増やすだけでなく、「今か・後か」を判断できることが
本質的に重要）。

### 2.1 Level 1（初心者）: カードの価値だけを見る

Phase 7.5検証Bot相当の判断を、正式なCPU実装として作り直す（ユーザー指摘
「検証BotがCPU並みに複雑になると作り直しになる」を踏まえ、検証Botの
後継として位置づける。以後の検証は使い捨てスクリプトではなくLevel 1 CPUを
使う）。

- 技選択: 使用可能な技の中から`power`が最大のものを選ぶ
- フィニッシャー: `canDeclareFinisher`が真であれば高確率（例: 80%）で宣言する
  （温存という概念を持たない）
- 返技: 返技エネルギーが足りていれば固定確率（例: 50%）で返す
- フォール／ギブアップ回避: 使えるキックアウト／ロープブレイクカードがあれば
  必ず使う。無ければHP消費、それも無ければ諦める
- フィニッシャーのキャンセル・脱出: 使えるカードがあれば必ず使う
- **Decision Traceには「カードの評価点（power値）」のみを記録し、温存判断の
  factorは持たない**（Level 1はそもそも温存しないため）

### 2.2 Level 2（中級）: 状況を見て、自分の情報だけで判断する

ユーザー提示の3項目（フォール率／HP／防御札）をLevel 1のスコアリングに
追加する。**Phase 7.5の失敗（相手の手札を覗く簡略化）を正式CPUでは行わない**
——「相手が防御札を持っていそうか」は、相手の**捨て札・除外札から推測**する
（後述2.4「情報源の制約」参照）。

技宣言・フィニッシャー宣言のスコアリング例（暫定値、実装時に検証して調整）:

- 基礎点: 技の`power`
- +相手の推定HPが低いほど加点（フォール／ギブアップ／フィニッシャーが
  決まりやすいタイミングを狙う）
- +自分のHPが低いときは守り寄りの選択（回避・エネルギー温存）に加点
- +自分の手札に防御札（エスケープ／リバーサル／キックアウト／
  ロープブレイク）が少ないときは、リスクを取る技より安全な技を優先
- フィニッシャー: 「相手の捨て札・除外札に特殊キックアウトが**確認できて
  いない**」場合にのみ加点する（覗き見ではなく観測情報に基づく）

### 2.3 Level 3（上級）: 時間軸を持つ（温存判断）

ユーザー提示の4項目（手札予測／デッキ残数／エネルギー効率／フィニッシャー
温存）を追加する。Level 3の核心は「今すぐ使えるが、後の方が有利かどうか」を
評価できることであり、これがPhase 7.5で最も欠けていた能力。

- **手札予測**: 相手の捨て札・除外札・（ラリー中に見えた）宣言済みカードから、
  相手の残りデッキ構成（防御札の残数・種類）を推測する
- **デッキ残数**: 自分・相手の山札残り枚数と`reshuffleCount`
  （`maxDeckReshuffles`上限）を見て、終盤（時間切れ引き分けが近い）かどうかを
  判断材料にする
- **エネルギー効率**: 温存中のエネルギーが次ターン以降どの技に使えるかを
  先読みし、無駄なセットを避ける
- **フィニッシャー温存**: `finisherRequirements`が`minimumHeat`条件を持つ
  場合、「あと何ターンでHEATが伸びるか」を自分の技のHEAT獲得量から見積もり、
  今すぐ使うより待った方が優位（後述の「専用防御成功率」を下げられる、
  相手の防御札が枯渇するのを待てる等）と判断できる場合は宣言を見送る
  （Decision Traceに`"温存"`という`rejected`理由を記録する）

### 2.4 情報源の制約（フェアネス）

検証Bot（Phase 7.5）は「相手が特殊キックアウトを持っていない」を手札を
直接見て判定していたが、これはCPUの判断力を測る上で不当な情報アドバンテージ
になる。正式CPUでは、レベルを問わず**相手の手札を直接参照しない**。
Level 2・3で使う「相手の防御札の有無」は、以下のいずれかの観測可能情報から
推測する。

- 相手の捨て札・除外札に何が積まれているか（使用済みカードは公開情報）
- 相手のデッキ枚数構成が既知の場合（モデルデッキ・自分で選んだ相手デッキ等）
  、残りデッキから確率的に推測する
- ラリー中に相手が返技・エスケープ・キックアウトを実際に使った履歴

この制約により、Level 1〜3すべてで一貫して「プレイヤーと同じ情報量」で
判断する設計とする。

## 3. Decision Trace（必須実装）

CPUの各意思決定ポイントで、以下の構造を持つオブジェクトを生成する。
UIやシミュレータはこれを蓄積し、JSONへシリアライズしてログ出力できる
ようにする（デバッグ・バランス調整専用機能。試合の勝敗判定には一切
関与しない）。

```jsonc
{
  "turnNumber": 12,
  "playerIndex": 0,
  "cpuLevel": "level3",
  "decisionType": "declareFinisher", // "declareAttack" | "counterAttack" |
                                      // "endRally" | "escapeChoice" |
                                      // "cancelFinisher" | "finisherEscapeChoice" |
                                      // "setEnergy" | "restOrEndTurn"
  "candidates": [
    {
      "cardId": "td_p7_akari_fin_burningdrive",
      "cardName": "紅蓮バーニングドライブ",
      "eligible": true,
      "score": 15,
      "factors": [
        { "label": "相手HP40以下", "delta": 20 },
        { "label": "HEATがまだ閾値+20未満（温存推奨）", "delta": -20 },
        { "label": "基礎威力", "delta": 15 }
      ]
    }
  ],
  "chosen": {
    "cardId": null,
    "action": "declareAttack",
    "actionCardId": "td_normal_strike_1",
    "reason": "フィニッシャー候補のスコアが0以下のため、通常技で様子を見た"
  },
  "rejected": [
    {
      "cardId": "td_p7_akari_fin_burningdrive",
      "reason": "温存（スコア15点だが基準値20点未満）"
    }
  ]
}
```

- `TechniqueCpuDecisionTrace`はDartクラスとして実装し、`toJson()`を持つ
  （既存の`TechniqueDeckSaveRecord`等と同じJSON往復パターンを踏襲）
- 蓄積先: `TechniqueMatchState`本体には持たせない（エンジンの純粋性を
  保つため）。CPU対戦を駆動する呼び出し側（シミュレータ・将来のCPU対戦
  画面）が`List<TechniqueCpuDecisionTrace>`として別途保持する
- 人間プレイヤーの操作にはDecision Traceは生成されない（CPU専用）

## 4. 試合ログ解析の強化

現状の`TechniqueMatchState.log`は人間可読な`List<String>`のみで、「なぜ
その判断をしなかったか」は残らない。Decision Traceの導入により、CPU対戦の
ログは以下の2層構造になる。

1. **既存の`TechniqueMatchState.log`**（人間可読、変更なし）:
   `Turn12: アカリが「ジャブ連打」を使用した` のような時系列テキスト
2. **新規: `List<TechniqueCpuDecisionTrace>`**（CPU専用、構造化）:
   同じターンで「なぜフィニッシャーを撃たなかったか」を
   `rejected: [{cardId, reason: "温存"}]`として保持する

シミュレータ・将来のログビューア（未実装）は両方を突き合わせて、
「Turn12: 通常技を使用（フィニッシャーは温存: HEAT80、閾値+20未満）」の
ような統合ログを再構成できる。

## 5. Phase 8 実装順序（ユーザー指定のサブフェーズ構成）

実装計画（[`technique_deck_implementation_plan.md`](technique_deck_implementation_plan.md)）
のPhase 8を、以下のサブフェーズへ分割する。

| サブフェーズ | 内容 |
|---|---|
| Phase 8.0 | CPU基盤: `TechniqueCpuLevel` enum・`TechniqueCpuController`の
  API骨格・`TechniqueCpuDecisionTrace`データモデル・JSON変換。実際の
  意思決定ロジックはまだ入れない（スタブ／テスト用の最小実装のみ） |
| Phase 8.1 | CPU Level 1（初心者）実装＋テスト。Phase 7.5検証Botの後継として
  位置づけ、以後のシミュレーションはLevel 1 CPUを使う |
| Phase 8.2 | CPU Level 2（中級）実装＋テスト |
| Phase 8.3 | CPU Level 3（上級）実装＋テスト（温存判断を含む） |
| Phase 8.4 | 1000試合シミュレーション（CPU対CPU、Decision Traceを使った
  分析。ユーザー提示の目標レンジと再度比較する） |
| Phase 8.5 | 必要ならモデルデッキ・カード数値を調整（**ここで初めて数値
  調整に着手する**。CPUの意思決定込みで検証できて初めて「Botの限界」ではなく
  「ルール・カードの限界」かどうかを切り分けられる、というPhase 6〜7.5から
  一貫した方針） |

各サブフェーズの完了ごとに、既存の慣例通り`flutter analyze`（0件）・
`flutter test`（全件パス）を確認し、進捗をopen questions／実装計画へ記録する。

## 6. 非目標（本設計書の対象外）

- `classic` / `energy`モードの`CpuDifficulty`・AIロジックへの変更
- Technique Match画面へのCPU対戦UIの実装（Phase 8.0〜8.3ではロジックのみ。
  UI統合のタイミングは実装時に判断）
- Decision Traceの可視化UI（本書はJSON出力までを対象とし、専用ログ
  ビューアの実装はPhase 9「チュートリアル・UI完成」以降で検討）
