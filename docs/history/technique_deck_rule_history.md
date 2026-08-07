# Technique Deck Rules — 変更履歴・廃止ルール

- 位置づけ: **過去の仕様変更・廃止ルール・Phase履歴の記録**。現在の正式仕様は
  [`../rules/technique_deck_rules.md`](../rules/technique_deck_rules.md) を参照する。
  本書はTechnique Match Rule Cleanup（現行仕様の正式化・旧実装の除去）ラウンドで、
  従来の `technique_deck_rules.md` に混在していた過去のPhase履歴を分離して
  新設した。
- 関連: [`../design/technique_deck_implementation_plan.md`](../design/technique_deck_implementation_plan.md)
  （実装計画の詳細なPhase履歴）、
  [`../design/technique_deck_open_questions.md`](../design/technique_deck_open_questions.md)
  （未決定事項の解決履歴）

---

## 1. Phase構成の概要

Technique Deck Rulesは以下の順で段階実装された（詳細は実装計画書を参照）。

| Phase | 内容 |
|---|---|
| Phase 0 | 仕様保存（本仕様の草案作成） |
| Phase 1 | データモデル基盤 |
| Phase 2 | デッキ生成・検証 |
| Phase 3 | スタンド・ダウン・休息（最初のプレイアブル） |
| Phase 4 | 単発技の使用 |
| Phase 5 | 返技エネルギーと連続攻撃（ラリー） |
| Phase 6 | フォール・ギブアップ |
| Phase 7 | フィニッシャー |
| Phase 7.5 | モデルデッキ最適化・フィニッシャー条件分散・検証Bot改善 |
| Phase 7A | レスラーカード・技カード・モデルデッキ実装（正式データ） |
| Phase 8 | CPU・シミュレーション（8.0〜8.1: CPU基盤・Normal実装） |
| Phase 8.5A | ゲームサイクル再設計（休息廃止・Combo Speed導入） |
| Phase 8.5A-2 | バージョン表示・CPU演出速度・試合時間換算 |
| （Phase番号なし） | UI/UX改善+CPU実装ラウンド、ゲームサイクル整理ラウンド、
  Technique Match Rule Cleanupラウンド（本ラウンド）等 |

## 2. 廃止したルール（LEGACY）

### 2.1 休息（HPを回復するダウンアクション）

**Phase 3〜Phase 7.5まで存在、Phase 8.5Aで廃止。**

かつては「自分をダウン状態にしてHPを回復力（`recoveryPower`）分回復し、
ターンを終了する」休息アクションが存在し、`TechniqueMatchEngine.rest()`／
`goDown()`として実装されていた。

- 廃止理由: 1ターンで「技を使う」か「休息する」のいずれかしか選べない
  仕様が、Combo Speedによる1ターン複数技化の障害になっていたため、
  ゲームサイクルそのものを再設計する際にあわせて廃止した。
- 廃止後の扱い: ダウン状態は技（`causesDown`）によってのみ発生する。
  自分の意思でダウン状態になる手段は存在しない。休息が無くても、使用可能な
  技が1枚も無いフレッシュターンでは、UI操作なしで自動的にターンが終了する
  （独立した「ターン終了」ボタンの復活ではない）。
- 現存する痕跡: `recoveryPower`フィールド（`TechniqueMatchPlayerState`・
  `TechniqueDeckWrestlerProfile`）とJSONログの`restsUsed`は、既存JSONログ・
  分析ツールとの互換性維持のため削除せずLEGACY/deprecatedとして残置。
  現在は常に無効果・常に0。

### 2.2 1ターン30秒のリアルタイム制限（TIME OVER）

**UIレベルの機構として存在、Phase 8.5Aで廃止。**

対戦画面に1ターン30秒のカウントダウンタイマーがあり、時間切れ
（TIME OVER）になると自動処理が走る仕組みだった。`AppLifecycleObserver`
との連携（バックグラウンド遷移時の扱い）も含んでいた。

- 廃止理由: 休息廃止と同じゲームサイクル再設計の一環。旧ルールの
  「試合時間」（引き分け条件としての時間切れ、13〜14章相当）とは別物の
  UI専用機構であり、Combo Speed導入後のゲームサイクルとは噛み合わないと
  判断された。
- 廃止後の扱い: リアルタイム制限は無い。対戦画面・JSON試合ログに表示される
  「試合時間」は、Phase 8.5A-2で追加された`formatMatchTime`（ターン数×30秒の
  演出上の換算表示）であり、実時間タイマーの復活ではない。
- 現存する痕跡: JSONログの`timeOverCount`は常に`0`固定（互換性維持、
  LEGACY/deprecated）。

### 2.3 1ターン1技（技使用後は必ず即ターン終了）

**Phase 5〜Phase 7.5まで存在、Phase 8.5Aで撤回。**

Phase 5で「攻防（ラリー）」を導入した際、「防御側が返技しない＝攻防
（ラリー）終了」という仕様だった。返技されなかった技が成立すると、
その時点で1ターンに使える技は実質1回のみだった。

- 撤回理由: 「1ターンに1技しか使えない」という制約になっており、
  Combo Speed導入（1ターン内の連続攻撃を制御するリソースとして技ごとの
  `speed`を新設）に伴い、フォール・ギブアップ効果を持たない通常のヒットは
  攻防（ラリー）を終了させない仕様へ変更した。
- 変更後の扱い: 攻撃側は同じ攻撃側のまま攻防に残り、残りCombo Speedが
  続く限り追加の技を宣言できる。フォール・ギブアップ効果を持つ技が成立した
  場合の即時決着処理（防御側の回避判定へ移行）自体はこの変更の対象外で、
  従来どおり。

### 2.4 旧返技判定（防御側のエネルギーだけで判定）

**Phase 5〜「ゲームサイクル整理ラウンド」まで存在、その後変更。**

Phase 5導入時の返技は「防御側が該当属性の返技エネルギーを持っていれば
返技できる」という、エネルギーの有無のみを条件とする判定だった（対応
カードの概念は無かった）。

- 変更理由: 「返技には手札の返技候補カードが必要」という仕様へ変更する
  ユーザー指示があった（ゲームサイクル整理ラウンド 優先度2）。攻撃技Xに
  対して返技Yが1対1で対応するというデータはカタログに存在しないため、
  「手札にある（フィニッシャー以外の）技カードは、そのカード自身の
  `reversalEnergyCost`を支払うことで任意の保留中攻撃への返技として使用
  できる」という汎用ルールへ再定義した。
- 現行仕様: [`../rules/technique_deck_rules.md`](../rules/technique_deck_rules.md)
  10章を参照（返技には手札の返技候補カードが必要、というのが現行仕様）。

## 3. 旧世代モデルデッキ（Phase 6・Phase 7・Phase 7.5）

Technique Match Rule Cleanupラウンドで、以下の12個のモデルデッキ生成関数を
`technique_deck_model_decks.dart`から削除した（本番のTechnique Match画面・
デッキ解決ロジックからは一度も参照されておらず、専用のテストからのみ
参照されていたことを確認済み）。

- Phase 6: `buildAkariPhase6ModelDeck` / `buildMisakiPhase6ModelDeck` /
  `buildReinaPhase6ModelDeck` / `buildJackPhase6ModelDeck`
- Phase 7: `buildAkariPhase7ModelDeck` / `buildMisakiPhase7ModelDeck` /
  `buildReinaPhase7ModelDeck` / `buildJackPhase7ModelDeck`
- Phase 7.5: `buildAkariPhase75ModelDeck` / `buildMisakiPhase75ModelDeck` /
  `buildReinaPhase75ModelDeck` / `buildJackPhase75ModelDeck`

これらは、通常技・固有技・フィニッシャーの内訳比率を変えながら
「フィニッシャー宣言率・決着率が目標レンジに収まるか」を検証していく過程で
順に手動構築された、世代の異なるモデルデッキだった（Phase 6: 通常技9・
固有技5・フィニッシャー無し → Phase 7: 通常技6・固有技3・フィニッシャー3 →
Phase 7.5: 通常技8・固有技2・フィニッシャー2）。最終的にPhase 7A
（レスラーカード・技カード・モデルデッキの正式データ投入）で、通常技8・
固有技4・フィニッシャー2という構成の正式版に統合され、以降はPhase 7A
モデルデッキのみが本番で使用されている。

**削除していないもの**: 各世代が使用していたカード定義そのもの
（`td_p6_*` / `td_p7_*` 等、`technique_deck_defaults.dart`内）は削除して
いない。Phase 7Aモデルデッキが一部の`td_p6_*`カード（固有技）を直接参照
しているほか、プレイヤーが手動デッキ編集画面（`TechniqueDeckBuilderScreen`）
で過去にこれらのカードを使ってデッキを保存している可能性があり、削除すると
保存済みデッキの読み込みが壊れるおそれがあるため。

## 4. 削除した旧実装（Rule Cleanupラウンド）

- `TechniqueMatchEngine.useMove`: Phase 4時点の「単発技のみ、返技・
  フォール／ギブアップ／フィニッシャー判定を経由しない」互換API。
  現行の`declareAttack`→`counterAttack`/`resolveHit`→`pendingEscape`/
  `pendingFinisher`というフローと非互換であり、本番コード
  （`technique_match_screen.dart`・`technique_match_cpu.dart`）からの参照が
  ゼロであることを確認した上で削除した。直接テストしていた既存テスト
  （ダメージ・DOWN・HEAT等の検証）は`declareAttack`→`resolveHit`の現行
  フローを使う形へ書き換えて残した。

## 5. 変更していないもの（誤解しやすい点の補足）

- `TechniqueMatchEngine.canUseMove`: `useMove`の事前条件チェック用メソッド。
  `useMove`とは独立した読み取り専用の判定関数であり、Rule Cleanupラウンド
  では削除していない（既存テストも変更していない）。
- `TechniqueMatchEngine.autoAdvanceTurnIfSettled`: 名称に反して「旧・
  1技=1ターン終了時代の仕組み」ではなく、現行のゲームサイクル
  （技の使用が完全に完結するかその手番で行動できなくなるまでターンを
  進めない）を支える中核の冪等関数であり、CPU・UIの両方から現役で使われて
  いる。
- SPEED-vs-COUNTER判定・`calculateEffectiveSpeed`・`enableSpeedGate`／
  `enableSpeedCounterGate`・`TechniqueCpuDecisionReason`: いずれも既定OFFの
  実験的機能（Feature Flag）であり、Rule Cleanupラウンドでは削除・正式化・
  有効化のいずれも行っていない。現行仕様書
  ([`../rules/technique_deck_rules.md`](../rules/technique_deck_rules.md) 20章)
  にも正式ルールとしてではなく実験機能として明記している。
