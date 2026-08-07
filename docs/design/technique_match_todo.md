# Technique Match 開発TODO（正本）

- ステータス: 新設（Technique Match / Technique Excel 正本整理タスク）
- 位置づけ: **Technique Match開発で「次に何をすべきか」を判断する唯一の入口。**
  新しいClaude Code / Codex / ChatGPTセッションは、まず本ファイルを読めば
  現状・正本・次のアクションが分かる状態を目指す。
- 本ファイル自体の作成・更新根拠: 実コード（`lib/src/technique_deck/`
  `lib/src/playtest_analytics/`）・Git履歴（`git log`）・既存ドキュメント
  （下記SOURCE OF TRUTH）・ユーザー提供のExcel
  （`docs/data/one_night_match_techniques.xlsx`）を実際に確認した上で記載している。
  推測で書いた項目はない。

---

## NEW SESSION START

新しいClaude Code / Codex / ChatGPTセッションでは、作業を始める前に必ず
以下の順で確認する。

1. 本ファイル（`docs/design/technique_match_todo.md`） — 現状・正本一覧・次アクション
2. [`docs/rules/technique_deck_rules.md`](../rules/technique_deck_rules.md) — 現行ルール仕様
3. [`docs/design/technique_deck_open_questions.md`](technique_deck_open_questions.md) — 未決定事項
4. `docs/data/one_night_match_techniques.xlsx` — 技・技系統・返し技の設計データ
   （シート構成は本ファイル「SOURCE OF TRUTH」章を参照）

確認後は、**下記「NEXT ACTION」から作業を再開する**。NEXT ACTIONが既に
完了している場合は、「PRIORITY TODO」の次の番号（P1、P2…）に進む前に、
本ファイルの CURRENT STATUS / NEXT ACTION を更新すること。

---

## NEXT ACTION

### 標準技系統マスタ Ver.1と技データ構造の設計レビュー

- **目的**: Excel `技系統マスタ`シート（現行27系統・5系統グループ:
  STRIKE/THROW/SUBMISSION/AERIAL/FOUL）と`技一覧`シートの`推奨決着属性`系
  列（PIN/SUBMISSION/KO/DOWN/NONE、複合可）を、現行48技だけでなく将来の
  技追加にも耐える「標準技系統マスタ Ver.1」として正式化してよいか、設計
  レビューを行う。本タスクでは仕様確定・Dart実装は行わない（PRIORITY TODO
  P1〜P2で扱う）。
- **入力資料**:
  - `docs/data/one_night_match_techniques.xlsx`
    （`技系統マスタ`・`技一覧`・`設計方針`・`各列の説明`・`返し技制約設計`シート）
  - [`docs/rules/technique_deck_rules.md`](../rules/technique_deck_rules.md) 7章（技カード）
  - [`docs/design/technique_deck_open_questions.md`](technique_deck_open_questions.md)
    （特に項目11・20・22、HEAT/レベル/`targetState`拡張に関する既存の未決定事項）
- **成果物**: レビューコメント・合意事項を本ファイルの
  「PRIORITY TODO > P1」または`open_questions.md`へ追記（新規ドキュメントの
  乱立は避け、既存の正本ファイルへ追記する）。
- **完了条件**: 以下がユーザーとの間で合意されること。
  1. 27系統・5系統グループの過不足（本タスクでは変更していない）
  2. 「属性」（既存5種、互換用）と「系統グループ」「技系統」の関係の扱い方
  3. FINISHERを「技の格」として扱い、決着方法（PIN/SUBMISSION/KO/DOWN/NONE）
     と分離する設計方針（Excel `設計方針`シート）をそのままP1〜P4のベースに
     採用してよいか

このレビューが完了するまで、P1（技系統マスタVer.1確定）・P2（48技マッピング）
には着手しない。

---

## A. CURRENT STATUS

実コード（`lib/src/technique_deck/` 全19ファイル・`lib/src/playtest_analytics/`
全4ファイル）とGit履歴（直近コミット: `f1ddccf` Playtest Analytics Phase A
Firebase Hosting Preview デプロイ設定追加）を確認した上での整理。

### 実装済み

- **Technique Match現行ルール**: `docs/rules/technique_deck_rules.md`
  （全20章）として正式化済み（Technique Match Rule Cleanupラウンドで
  過去のPhase履歴と分離）。
- **旧Phase 4互換API `useMove` は削除済み**（現行フローは
  `declareAttack` → `counterAttack` / `resolveHit`）。
- **Combo Speed実装済み**（`TechniqueMatchState.rallyRemainingSpeed`、
  Phase 8.5A）。休息・1ターン30秒タイマー・1ターン1技はLEGACY（廃止済み）。
- **1ターン複数技**: フォール／ギブアップ効果を伴わないヒットはラリーを
  終了させず、残りCombo Speedが続く限り連続攻撃できる（Phase 8.5A）。
- **返技（返し技）**: 防御側の任意選択、`reversalEnergyCost`のみで判定
  （現行は技の`attribute`ベース。技系統ベースの返し技制約はP3〜P7で未実装）。
- **PIN / SUBMISSION / FINISHER**: 実装済み（`hasPinEffect` /
  `hasSubmissionEffect` / `hasFinisherEffect`）。**KO判定は未実装**
  （Excel `設計方針`シートで新規提案されている決着属性で、現行実装には
  存在しない）。
- **CPU Normal**: 実装済み（`TechniqueMatchCpu`、`TechniqueCpuLevel.normal`
  が唯一の実装レベル）。Level 2（中級）・Level 3（上級、温存判断）は
  設計書（[`technique_deck_cpu_design.md`](technique_deck_cpu_design.md)）
  のみで未実装。
- **CPU対人間**: 実装済み。`TechniqueMatchSetupScreen`から標準の対戦導線
  として選べる（既定選択はCPU対戦）。
- **正式モデルデッキ**: 4人分（火神アカリ・豪田ミサキ・白銀レイナ・
  黒蝶ジャック）のPhase 7Aモデルデッキが正式データ
  （`technique_deck_model_decks.dart`）。旧世代（Phase 6/7/7.5）の生成関数は
  削除済み（履歴は`docs/history/technique_deck_rule_history.md`参照）。
- **技カード48枚（現行48技）**: `technique_deck_defaults.dart`の
  `td_p7a_*`系48件（4人×12枚＝通常技8・固有技2・フィニッシャー2）。
  Excel `技一覧`シートの48行と**cardId・技名・属性・power・speed・heat・
  attackEnergyCost・targetState・現行効果（PIN/SUBMISSION/DOWN/FINISHER）が
  完全一致していることを確認済み**（STEP 8監査結果、下記参照）。
- **Playtest Analytics Phase A**: 実装済み。試合終了時の自動診断
  （`TechniqueMatchAnalyzer`）・`SharedPreferences`によるローカル自動保存
  （`PlaytestMatchRepository`）・確認用画面（`PlaytestAnalyticsScreen`）。
- **Firebase Hosting Preview**: 設定済み（`firebase.json` / `.firebaserc`、
  プロジェクト`one-night-match-preview`、Hostingのみ）。
- **テスト**: `test/`配下に技デッキ関連ファイル17件を含む多数のテストが存在
  （リポジトリ全体で`test(`呼び出し414件、technique関連ファイルのみでも
  十数ファイル）。

### 未実装（明示的に未着手・今回のタスクの対象外）

- **Firestore自動保存**: 未実装。Playtest Analytics Phase Aはローカル保存
  のみで、Firestore/Authentication/Security Rulesは意図的に未導入
  （`firebase.json`にHosting設定のみ、README.mdにも明記）。
- **技系統（技系統コード・系統グループ）のFlutterデータモデルへの実装**:
  完全に未着手。`TechniqueDeckTechniqueCard`に該当フィールドは存在しない
  （STEP 8監査結果、下記参照）。
- **KO判定・決着属性の分離（FINISHER＝技の格、決着方法は別軸）**: 未実装。
  現行実装は`hasFinisherEffect == true`のカードが成立すると
  即勝利になる構造（フィニッシャー成功＝勝利）。
- **返し技マスタ（technique系統ベースのtargetFamilies等）**: 未実装。
  現行の返技判定は技の`attribute`（5属性）ベースのみ。
- **CPU Level 2 / Level 3**: 未実装（設計書のみ存在）。

---

## B. SOURCE OF TRUTH

| 情報 | 正本ファイル |
|---|---|
| 現行ルール | [`docs/rules/technique_deck_rules.md`](../rules/technique_deck_rules.md) |
| 未決定事項 | [`docs/design/technique_deck_open_questions.md`](technique_deck_open_questions.md) |
| 実装計画・Phase履歴（現行） | [`docs/design/technique_deck_implementation_plan.md`](technique_deck_implementation_plan.md) |
| CPU設計 | [`docs/design/technique_deck_cpu_design.md`](technique_deck_cpu_design.md) |
| ルール変更履歴・廃止ルール | [`docs/history/technique_deck_rule_history.md`](../history/technique_deck_rule_history.md) |
| 技・技系統・返し技の設計データ（人間レビュー用） | `docs/data/one_night_match_techniques.xlsx` |
| 開発TODO・次に何をすべきか | 本ファイル（`docs/design/technique_match_todo.md`） |
| ゲームロジック（実装の正本、Dart定数） | `lib/src/technique_deck/technique_deck_defaults.dart`（48技カード） / `technique_deck_model_decks.dart`（4人分モデルデッキ） / `technique_deck_wrestler_catalog.dart`（レスラー） |
| Playtest Analytics（ローカル解析） | `lib/src/playtest_analytics/`（`TechniqueMatchAnalyzer` / `PlaytestMatchRepository` / `PlaytestAnalyticsScreen`） |

### データの正本ルール（今回定義）

現状、技カードデータの実装上の正本は **Dart定数**
（`technique_deck_defaults.dart`）である。JSON/CSVによるデータ駆動化は
行われていない。今回のタスクでは、この現状をいきなりJSON駆動へ移行しない
（禁止事項どおり、ゲームロジックの大規模改修は行わない）。

将来構造（TODOとして定義。今回は実施しない）:

```
Excel（docs/data/one_night_match_techniques.xlsx）
  = 人間が技・系統・返し技を設計/レビューするための正本
    ↓（将来: 変換スクリプト。今回は未着手）
実装用データ（JSON/CSV。将来的な配置場所は未決定）
  = Flutterで読み込みやすい形式
    ↓
Dart（technique_deck_defaults.dart 等）
  = ゲームロジックが直接参照するデータ
```

- 現時点（今回時点）: Excel（設計）→ 手動でDart定数へ転記、という運用。
  STEP 8監査で確認した限り、既存48技の基本フィールド（技名・属性・power・
  speed・heat・cost・targetState・現行効果）はExcelとDartで一致しており、
  転記自体の劣化は見つかっていない。
- 中間データ形式（JSON/CSV）を正式に導入するかどうか、導入する場合の
  自動生成方式は STEP 9（Excel→実装データ同期方式の提案）を参照。
  **今回は提案のみで、実装・移行は行わない。**

---

## C. PRIORITY TODO

### P0. 標準技データ構造の確定

検討中の軸（Excel `各列の説明`・`設計方針`シートに基づく）:

- 属性（既存5種、互換用）
- 系統グループ（STRIKE/THROW/SUBMISSION/AERIAL/FOUL、Excel `技系統マスタ`
  シートに定義済み）
- 大系統／詳細技系統（Excel `技系統`・`技系統コード`列。現行27系統）
- 発動形式（現状Excel上に専用列なし。P1で検討）
- 決着属性（PIN/SUBMISSION/KO/DOWN/NONE、複合可。Excel `推奨決着属性`系列）
- 技の格（通常技／固有技／フィニッシャー。FINISHERは決着方法ではなく
  「技の格」として扱う方針、Excel `設計方針`シート）

決着方法は別途、PIN / SUBMISSION / KO / DOWN / NONE として扱う方向
（Excel `設計方針`シートの提案どおり）。

### P1. 標準技系統マスタ Ver.1

現行48技だけでなく、将来の技追加も考慮した40〜50系統程度の標準マスタを
設計する。Excel `技系統マスタ`シートに現行27系統・5系統グループが定義
済みであり、これをベースに拡充するか、そのまま採用するかをNEXT ACTIONの
レビューで判断する。過度な細分化は避ける。

### P2. 現行48技を新しい技系統へマッピング

Excel上の48技（`技一覧`シート）について、属性・系統グループ・大系統・
詳細技系統・発動形式・決着属性・技の格を設定する。**Excelの`技一覧`シートには
既に`技系統`・`技系統コード`・`系統グループ`・`推奨決着属性`列が入力済み**
（STEP 2調査で確認）。P2は主にこのマッピング内容のレビュー・確定作業になる
見込み。

### P3. 返し技マスタ Ver.1

Excel `返し技一覧`・`返し技対応表`シートに、返し技14件分の
targetGroups・targetFamilies・excludeFamilies・成功時効果案・必要コスト・
Speed・難度が既に設計されている（STEP 2調査で確認）。P3はこの設計内容の
実装可否レビュー・不足項目（cannotCounter・FINISHER対応可否の明示等）の
洗い出しになる見込み。

判定優先順位案（Excel `返し技制約設計`シートに準拠）:

1. cannotCounter（技側が持つ絶対返し不可、最優先級）
2. excludeFamilies（最優先で除外判定）
3. targetFamilies（個別指定があればgroupより優先）
4. targetGroups（個別指定が無い場合の広い許可）
5. targetAttributes（旧属性ルールとの互換、移行期間のみ）

### P4. FINISHERと決着処理の正式化

FINISHER成功＝即勝利ではなく、

```
技成功
  ↓
決着属性（PIN / SUBMISSION / KO / DOWN / NONE）
  ↓
PIN / SUBMISSION / KO判定
  ↓
勝敗
```

という構造を検討・確定する。Excel `設計方針`シートに実装注意として
「現行`hasFinisherEffect`の即勝利処理を、フィニッシャー成功→決着属性別
判定へ変更する想定」と明記されている。

### P5. 技カードUI再設計

カード面には試合中に必要な情報だけを表示する（技名・格・COST・POWER・
SPEED・HEAT・属性・対象状態・決着アイコン・技系統・主要効果）。詳細画面には
詳細技系統・発動形式・返し技相性・使用可能／不可返し技・条件・タグ・
デッキ制限・備考等を表示する。

### P6. Flutterデータモデル実装

仕様確定後に、`TechniqueDeckTechniqueCard`等へ必要フィールドを追加する。
**この段階までは設計とExcelを優先し、仕様未確定のままDartモデルを先行
変更しない**（今回のタスクでも変更していない）。

### P7. 返し技判定実装

新しい技系統を使用して、返し技との対応可否を判定する。

### P8. CPU対応

CPUが技系統・返されやすさ・Speed・決着属性・FINISHER・Combo Speedを
考慮できるようにする。

### P9. シミュレーション・バランス調整

Playtest Analyticsを利用して、技を使えないターン率・返技率・
FINISHER宣言率・PIN決着率・SUBMISSION決着率・KO決着率・DRAW率・
平均試合時間・レスラー別勝率などを検証する。

### P10. Firestore自動保存

現時点では後回し。Playtest Analytics Phase Aのローカル自動解析を優先して
使用する。Firestore/Auth/Security Rulesは、ゲームルール・技システムが
安定してから着手する。

---

## D. STEP 8: Excel vs Flutter実装 差分監査結果

**監査のみ。今回はFlutterへの反映を一切行っていない。**

Excel `技一覧`シート48行（`ID`列＝Dartの`td_p7a_*`系48件と1:1対応）を、
`technique_deck_defaults.dart`の該当48カード定義とスクリプトで機械比較した。

### 一致した項目（48件全件で差分なし）

| 項目 | 結果 |
|---|---|
| cardId（Excel `ID` vs Dart `id`） | 48/48 一致（1:1対応、過不足なし） |
| 技名（Excel `技名` vs Dart `name`） | 48/48 完全一致 |
| 属性（Excel `属性` vs Dart `attribute`） | 48/48 一致 |
| power（Excel `威力` vs Dart `power`） | 48/48 一致 |
| speed（Excel `Speed` vs Dart `speed`） | 48/48 一致 |
| heat（Excel `HEAT` vs Dart `heatDelta`） | 48/48 一致 |
| attackEnergyCost（Excel `攻撃コスト` vs Dart `attackEnergyCost`） | 48/48 一致 |
| targetState（Excel `対象状態` vs Dart `targetState`） | 48/48 一致 |
| 現行の決着効果（Excel `現行効果` vs Dart `hasPinEffect`/`hasSubmissionEffect`/`causesDown`/`hasFinisherEffect`から算出した実効値） | 48/48 一致 |

wrestlerId（Excel `レスラー`列の日本語名 vs Dart
`allowedWrestlerIds`のIDスラッグ）は文字列表現が異なる（例:
「火神アカリ」vs `wrestler_akari`）が対応関係に矛盾はない。down（Excel
`推奨DOWN` vs Dart `causesDown`）はP2「推奨列は新設計案」を参照。

### Excel側にしか存在しない項目（＝未実装。Flutterへは反映していない）

| 項目 | 内容 |
|---|---|
| `技系統` / `技系統コード` / `系統グループ` | `TechniqueDeckTechniqueCard`にこの概念自体が存在しない（P1〜P2・P6の対象） |
| `推奨決着属性` / `推奨PIN` / `推奨SUBMISSION` / `推奨KO` / `推奨DOWN` | 新しい決着属性システムの提案。特に**KOはDart側に概念自体が存在しない**（現行は`hasPinEffect`/`hasSubmissionEffect`/`hasFinisherEffect`の3種のみ）。48件中、現行実装（`現行効果`列）と推奨列が異なる行が多数ある（P4の対象。1件ずつの異同は`docs/data/one_night_match_techniques.xlsx`の`技一覧`シートで確認可能） |
| `提案理由` | 設計レビュー用の文章。Flutterへの実装対象ではない |
| `返し技一覧` / `返し技対応表`シート全体 | 現行の返技判定は技の`attribute`（5属性）ベースのみで、技系統ベースの`targetFamilies`/`excludeFamilies`等は一切未実装（P3・P7の対象） |

**結論**: 現行48技の基本パラメータ（威力・Speed・HEAT・コスト・対象状態・
現行決着効果）はExcelとFlutter実装の間で**完全に整合しており、データ劣化・
転記ミスは検出されなかった**。差分はすべて「Excelで新規提案された未実装
項目」であり、想定どおり「新設計項目」として扱う（P0〜P4で仕様確定後、
P6でDartへ反映する）。

---

## E. STEP 9: Excel→実装データ同期方式の提案（提案のみ、今回は移行しない）

比較した方式:

| 方式 | 人間の編集しやすさ | Git差分の見やすさ | Claude Code/Codexの扱いやすさ | Flutterでの読み込み | CI整合性チェック | シミュレーション利用 |
|---|---|---|---|---|---|---|
| A. Excelを正本にしてJSON/CSVを自動生成 | ◎（Excel編集に慣れたレビュアー向け） | △（xlsxはバイナリのため差分は生成後のJSON/CSV側でのみ見える） | ○（生成後のJSON/CSVは読み書きしやすいが、Excel自体の自動編集は不得意） | ◎（JSON/CSV経由なら容易） | ◎（生成スクリプト＋差分チェックで整合性を機械的に保証しやすい） | ◎（JSON/CSVをそのままシミュレーションスクリプトへ渡せる） |
| B. JSON/CSVを正本にしてExcelをレビュー用に生成 | △（非エンジニアがJSON/CSVを直接編集するのは負担） | ◎（JSON/CSVは差分が読みやすい） | ◎（Claude Code/Codexが最も得意とする形式） | ◎ | ◎ | ◎ |
| C. Dartを正本としてExcelを生成 | ×（Dartを直接編集できる人が設計もレビューもする前提になる） | ○（Dart差分は読めるが、係数変更のたびにコード差分が入りレビューしにくい） | ○（Dart自体は扱えるが、非エンジニア向けレビューの往復には不向き） | ◎（変換不要） | △（DartからExcelを生成するスクリプトが別途必要） | △（Dartを直接シミュレーションに使い回すには追加の抽出コードが要る） |

### 推奨: 方式A（Excelを正本にしてJSON/CSVを自動生成）

**理由**:

- ONE NIGHT MATCHの技・技系統・返し技設計は、今回のExcelが示すとおり
  「人間（ユーザー）が表形式でレビュー・調整する」運用に既に最適化されて
  いる（列構成・提案理由列・難度列など、非エンジニア向けの設計配慮が
  Excel側に既に存在する）。
- Flutter実装・Claude Code/Codexでの機械処理には、Excelそのものではなく
  そこから生成したJSON/CSVを使う（方式Aは方式Bの「機械可読性」の利点を
  変換ステップで取り込める）。
- CI整合性チェック（STEP 8で今回手動実施したような「Excel⇔実装データの
  差分検出」）を、生成スクリプト＋差分チェックとして自動化しやすい。
- 方式B（JSON/CSVを正本にする）は機械可読性で最も優れるが、技デザインの
  レビュー・調整という今回のExcelの主目的（人間が主体のレビュー作業）には
  向かない。方式C（Dartを正本にする）は今回の禁止事項
  （「Excelの内容を推測で補完しない」「現行48技を勝手に変更しない」）とも
  相性が悪く、既存のDart駆動の運用をそのまま固定化してしまう。

**今回のタスクでは方式Aを推奨として記録するのみで、変換スクリプトの実装・
大規模なデータ移行は実施しない。** 実装に着手する場合はP6（Flutterデータ
モデル実装）以降、別タスクとして着手すること。

---

## 変更履歴

- 新設（Technique Match / Technique Excel 正本整理タスク、2026-08-07）:
  本ファイルを新設し、`docs/data/one_night_match_techniques.xlsx`を配置。
  Excel vs Flutter実装の監査（STEP 8）・同期方式の提案（STEP 9）を実施。
  ゲームロジック・バランス数値・FINISHER挙動は変更していない。
