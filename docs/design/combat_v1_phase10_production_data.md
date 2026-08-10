# Combat Ver.1 Phase 10 — Production Data 設計・確定値記録

- ステータス: Phase 10A（豪田ミサキ）着手時点
- 関連: [`../combat_rules_v1.md`](../combat_rules_v1.md)（SSOT） /
  [`combat_v1_open_questions.md`](combat_v1_open_questions.md)

本書は、Combat Ver.1 SSOT（`combat_rules_v1.md`）が「検証値」「未確定」としている項目のうち、
Phase 10（Production Data実装）のセッションでユーザーへ確認のうえ正式確定した値を記録する。
`combat_rules_v1.md`本文へは、個別レスラーの大量Techniqueデータをベタ書きしない方針
（同書26章）のため、Production値の確定記録は本書へ集約する。

Dartの`lib/src/combat_v1/`配下（`combat_v1_wrestler_catalog.dart`
／`combat_v1_technique_catalog.dart`／`combat_v1_counter_catalog.dart`
／`combat_v1_decks.dart`）がruntime SSOTであり、本書はその設計判断・確定経緯の記録に留める。
`docs/data/one_night_match_techniques.xlsx`は引き続きreview/reference専用であり、
本書・Dartの値と食い違う場合はDart側を正とする。

---

## 1. Stable ID規約（Phase 10Aで確定）

### 1.1 Technique ID

`<wrestler-stable-key>_<technique-stable-key>`（ASCII lowercase snake_case）。

- categoryを含めない（NORMAL/SIGNATURE/FINISHERの別はIDに現れない）
- Phase番号を含めない
- damage/cost/familyを含めない
- 表示名（`name`）を変更してもIDは変更しない

例: `misaki_backdrop`、`misaki_goda_bomb`。

### 1.2 Wrestler ID

レスラー本人を表す短いASCII lowercase key。豪田ミサキ = `misaki`。

### 1.3 Counter ID

Counterは原則共有definitionのため、Technique IDとは異なり**wrestler-stable-keyを含めない**
（同一name・payment attribute・counterableFamilies/Groupsであれば複数レスラーが同一Counter
definitionを参照できるようにするため、SSOT「Phase 10-Precondition B」方針）。
`counter_<counter-stable-key>`の形式とする。

例: `counter_strike_guard`、`counter_suplex_reversal`、`counter_powerbomb_escape`。

---

## 2. 豪田ミサキ — Production Wrestler

| フィールド | 値 |
|---|---|
| id | `misaki` |
| name | 豪田ミサキ |

HP等は`CombatV1RulesConfig`の共通値（全レスラー共通固定、SSOT 2・14章）を使うため、
Wrestlerモデルへ重複保存しない（既存`CombatV1Wrestler`の設計どおり）。

### 2.1 ENERGY Pool（Phase 10Aで検証値からProduction値へ確定）

`combat_rules_v1.md`18章の検証値を、Phase 10Aセッションでユーザーが確認のうえ、
そのままProduction値として正式採用した。

| 属性 | 値 |
|---|---|
| 打（strike） | 3 |
| 関（joint） | 0 |
| 投（throwing） | 4 |
| 飛（aerial） | 0 |
| ラフ（rough） | 1 |
| ＊（wild） | 1 |
| **合計** | **9** |

---

## 3. 豪田ミサキ — Production Technique（12種）

`combat_rules_v1.md`19章のCOST／DMG／HEAT／状態は確定値としてそのまま採用した
（Phase 10Aセッションでの再確認により変更なし）。Technique
Family割当はSSOT本文に明記がなかったため、Phase
10Aセッションでユーザーが確認のうえ、技名から自然に導ける下記mappingを正式採用した
（すべて現行30 family taxonomy、`combat_rules_v1.md`23.3章に実在する値）。

| # | 技名 | ID | category | attribute | family | Cost | DMG | HEAT | 状態 | 備考 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 逆水平チョップ | `misaki_reverse_chop` | NORMAL | strike | CHOP | 打1 | 10 | 10 | STAND→STAND | |
| 2 | ショルダータックル | `misaki_shoulder_tackle` | NORMAL | strike | TACKLE | 打1 | 10 | 20 | STAND→DOWN | |
| 3 | ボディスラム | `misaki_body_slam` | NORMAL | throwing | SLAM | 投1 | 10 | 10 | STAND→STAND | |
| 4 | ブレーンバスター | `misaki_brainbuster` | NORMAL | throwing | SUPLEX | 投2 | 20 | 20 | STAND→DOWN | |
| 5 | バックドロップ | `misaki_backdrop` | NORMAL | throwing | BACKDROP | 投2 | 20 | 20 | STAND→DOWN | |
| 6 | パワースラム | `misaki_power_slam` | NORMAL | throwing | SLAM | 投3 | 30 | 30 | STAND→DOWN | |
| 7 | ラリアット | `misaki_lariat` | NORMAL | strike | LARIAT | 打2 | 20 | 20 | STAND→DOWN | |
| 8 | ギロチンドロップ | `misaki_guillotine_drop` | NORMAL | strike | GUILLOTINE_DROP | 打1 | 10 | 20 | DOWN→DOWN | required: DOWN |
| 9 | 豪快バックドロップ | `misaki_mighty_backdrop` | SIGNATURE | throwing | BACKDROP | 投3 | 30 | 40 | STAND→DOWN | |
| 10 | 剛腕ラリアット | `misaki_strong_arm_lariat` | SIGNATURE | strike | LARIAT | 打2 | 20 | 30 | STAND→DOWN | |
| 11 | 豪田ボム | `misaki_goda_bomb` | FINISHER | throwing | POWERBOMB | 投3 | 30 | 40 | STAND→DOWN | finisherType=directPin |
| 12 | 豪田ドライバー | `misaki_goda_driver` | FINISHER | throwing | DRIVER | 投4 | 40 | 50 | STAND→DOWN | finisherType=normal |

### 3.1 finisherType確定経緯

- **豪田ボム**: `combat_rules_v1.md`19章の表が「特性」列に明示的に「DIRECT PIN」と記載しており、
  Phase 9で確定した`finisherType`優先順位ルール（`category==finisher`では`finisherType`のみが
  決着方式を決定する）へそのまま正規化できるため、`finisherType = directPin`として確定した
  （追加のユーザー確認は不要と判断）。
- **豪田ドライバー**: 同表には「最大火力（検証対象）」としか記載がなく、決着方式は未確定だった。
  Phase 10Aセッションでユーザーへ確認し、`finisherType = normal`として確定した
  （豪田ボム（directPin）と役割を分け、攻撃側が成功後に任意でPINを選択できる形にする）。

attribute（ENERGY属性）は全12技とも`combat_rules_v1.md`19章のCOST列（打／投のみ、ラフ技は
0種）からそのまま導出した。ミサキのENERGY Poolが持つラフ1は、Technique
Costとしては使用しない（3章のCounter attribute側で使用する、後述）。

---

## 4. 豪田ミサキ — Production Counter（3種）

`combat_rules_v1.md`21章・Phase 4オープンクエスチョンのいずれにも、ミサキ用COUNTER
3種の正式割当は記載がなかった。`docs/data/one_night_match_techniques.xlsx`の「返し技一覧」14候補は
どのレスラーへ割り当てるか未決定であり、かつ`excludeFamilies`等の制約設計が現行`CombatV1Counter`
モデル（`counterableFamilies`/`counterableGroups`のORマッチのみ、23.5章）と一致しないため、
名称・対応範囲の参考としてのみ使用した。

Phase 10Aセッションでユーザーが確認のうえ、SSOTの「広範囲/中範囲/専門」テンプレート
（`combat_v1_open_questions.md`起票時の設計方針）に沿って以下の3種を正式採用した。
attribute（支払い属性）は、ミサキが実際に保有するENERGY属性（打3／投4／ラフ1）の範囲内から選定した
（関・飛は保有量0のため、Counter attributeとして選ぶと常に支払い不能になり実質使用不可能な
Counterになってしまうため除外した）。

| # | 役割 | 名称 | ID | attribute | counterableFamilies | counterableGroups |
|---|---|---|---|---|---|---|
| 1 | 広範囲型 | ガード＆エルボー | `counter_strike_guard` | strike（打） | — | [STRIKE] |
| 2 | 中範囲型 | スープレックス切り返し | `counter_suplex_reversal` | throwing（投） | [BACKDROP, SUPLEX] | — |
| 3 | 専門型 | フランケンシュタイナー返し | `counter_powerbomb_escape` | throwing（投） | [POWERBOMB] | — |

Counter自身に固定ENERGY COSTは設定しない（返される攻撃TECHNIQUEのENERGY COST総量を、
上記単一属性で支払う、`combat_rules_v1.md`7章）。

---

## 5. 豪田ミサキ — Production Deck（30枚）

`combat_rules_v1.md`21章の配分方針（基本NORMAL＝逆水平チョップ×3・ボディスラム×3、
その他NORMALは原則×2、SIGNATURE各×2、FINISHER各×1、COUNTER各×2）をそのまま正式採用した。

| category | 内訳 | 枚数 |
|---|---|---|
| NORMAL | 逆水平チョップ×3、ボディスラム×3、ショルダータックル×2、ブレーンバスター×2、バックドロップ×2、パワースラム×2、ラリアット×2、ギロチンドロップ×2 | 18 |
| SIGNATURE | 豪快バックドロップ×2、剛腕ラリアット×2 | 4 |
| FINISHER | 豪田ボム×1、豪田ドライバー×1 | 2 |
| COUNTER | ガード＆エルボー×2、スープレックス切り返し×2、フランケンシュタイナー返し×2 | 6 |
| **合計** | | **30** |

同名上限（`CombatV1RulesConfig`既定値）: NORMAL 3／SIGNATURE 2／FINISHER 1／COUNTER
2のいずれにも収まる。

---

## 6. Excelとの差分（意図的に採用しなかったもの）

`docs/data/one_night_match_techniques.xlsx`の「技一覧」シートにあるミサキ候補データ
（`td_p7a_misaki_*`のID体系、ショルダータックル威力8/Speed1/HEAT5、パワーボム／
ジャイアントスラム／ラストパワーボムなど）は、`combat_rules_v1.md`19章のミサキ12技データと
技名・数値ともに一致しない別系統の旧候補であり、以下の理由でPhase 10Aでは採用しなかった
（SSOT優先、`combat_rules_v1.md`本文を優先する方針）。

- `Speed`列・`KO`列はSSOTで禁止された旧仕様のフィールドである（本タスク方針「5. 旧仕様の移植禁止」）。
- 技名・技数がSSOT 19章の12技（NORMAL8・SIGNATURE2・FINISHER2）と一致しない
  （Excel側はパワーボム／ジャイアントスラム／ラストパワーボムを含み、豪田ボムを含まない）。

「返し技一覧」「返し技対応表」「技系統マスタ」の技系統コード（STRIKE/AERIAL/THROW/SUBMISSION/FOUL、
ELBOW/CHOP/KICK/…等）自体は、現行`CombatV1TechniqueFamily`/`CombatV1TechniqueFamilyGroup`
taxonomyと一致するため、family/group名称の参考にした（値そのものは`combat_rules_v1.md`
23章がSSOTであり、Excelから昇格させたわけではない）。

---

## 7. 変更履歴

- **Phase 10-Precondition〜10A**: 本書を新規作成。上記1〜6章の内容を、Phase
  10Aセッション内でユーザーへ確認のうえ正式確定した。
