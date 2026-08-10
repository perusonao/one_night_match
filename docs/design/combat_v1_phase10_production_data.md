# Combat Ver.1 Phase 10 — Production Data 設計・確定値記録

- ステータス: Phase 10C（火神アカリ・白銀レイナ）完了時点。4人Production Catalog完成。
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

上表「状態」列の左側（例: `STAND→DOWN`の`STAND`）は`requiredOpponentState`を表す。
`CombatV1Technique.requiredOpponentState`は`null`の場合「STAND/DOWNどちらでも使用可能」を
意味するため（`combat_v1_technique.dart`）、STAND始動の11技（#1〜7・9〜12）には明示的に
`requiredOpponentState: CombatV1WrestlerPosture.stand`を設定する必要がある
（Phase 10A Codexレビュー指摘、初回実装ではこの11技が`requiredOpponentState`未設定のまま
公開されており、DOWN状態の相手へも使用できてしまう不整合があったため修正した）。
required=DOWNの#8（ギロチンドロップ）のみ元から正しく実装されていた。

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

## 7. Production Deck instanceId設計（Phase 10A GitHub Codexレビュー指摘対応で確定）

`cardId`（Technique/Counterの安定definition id、1章参照）と`instanceId`（デッキ内の
物理カード1枚を識別するID、`CombatV1DeckEntry.instanceId`）は別概念である。

- **cardId**: Technique/Counterの安定definition identity。同じcardIdを複数player・
  複数枚のデッキ内カードが参照すること自体は正常（例: ミサキ同士のミラーマッチで両者が
  `misaki_backdrop`を使う）。
- **instanceId**: 物理カード1枚のidentity。`combat_v1_state_invariants.dart`の
  `duplicateCardInstanceId`invariant（両playerの全カードゾーン＋pendingを通じて
  一意）が要求するとおり、**match内でplayerを跨いで一意**でなければならない。

Phase 10A初版の`buildMisakiDeck()`は、instanceIdを`<wrestlerId>_<cardId>_#<連番>`
（wrestlerId固定）で生成していたため、同一レスラー同士のミラーマッチ（例:
豪田ミサキ vs 豪田ミサキ）で両playerのデッキが完全に同一のinstanceId集合を持ってしまい、
`declareTechnique`以降（`pendingAttackOwnershipViolation`が防御側ゾーンに同名instanceId
を検出）でCommandが失敗する不具合があった（GitHub Codex自動レビュー、PR #10、P1）。

この不具合を受け、Production Deck builder（`buildMisakiDeck`）は`ownerId`
（このデッキがどちらのplayer向けかを表す識別子）を**必須named parameter**として要求する
設計へ変更した。デフォルト値は用意しない——呼び出し側が指定を省略して同一デッキを
両playerへそのまま渡し、再びinstanceId衝突を起こす事故を構造的に防ぐため。

```dart
buildMisakiDeck(ownerId: 'player-a')  // → misakiWrestler.idではなくownerIdをinstanceId生成に使う
buildMisakiDeck(ownerId: 'player-b')
```

- `ownerId`はinstanceId生成専用であり、`CombatV1DeckDefinition.wrestlerId`（常に
  `misakiWrestler.id`＝`"misaki"`）・cardId・Technique/Counter/Wrestlerのstable
  IDのいずれにも影響しない。
- `ownerId`が空文字（trim後）の場合は`ArgumentError`を送出する（player間instanceId
  衝突の原因になるため）。
- この設計はミサキ専用hackにせず、Phase 10B以降の黒蝶ジャック・火神アカリ・白銀レイナの
  Production Deck builderでも同じ`ownerId`パラメータ方式を踏襲する想定
  （ただし3人分のProduction Data自体はPhase 10Aでは実装しない）。

---

## 9. 黒蝶ジャック — Production Wrestler（Phase 10B）

| フィールド | 値 |
|---|---|
| id | `jack` |
| name | 黒蝶ジャック |

### 9.1 ENERGY Pool（`combat_rules_v1.md`18章の検証値をそのまま採用）

| 属性 | 値 |
|---|---|
| 打（strike） | 3 |
| 関（joint） | 1 |
| 投（throwing） | 1 |
| 飛（aerial） | 0 |
| ラフ（rough） | 4 |
| ＊（wild） | 1 |
| **合計** | **10** |

---

## 10. 黒蝶ジャック — Production Technique（12種、Phase 10B）

`combat_rules_v1.md`20章は5技（チョーク攻撃・顔面かきむしり・黒蝶クラッシュ・
黒蝶ドライバー・ブラック・ジャック）のCOST／DMG／HEAT／デッキ枚数のみを確定値として
持ち、状態遷移（requiredOpponentState/resultingOpponentState）・Technique
Family・finisherType・残り7技（NORMAL6＋SIGNATURE1）の名称・数値は一次資料に
記載がなかった。Phase 10Bセッションで、Claudeが叩き台（技名・数値・family割当・
Counter・Deck内訳を含む完全な提案）を提示し、ユーザーが内容を確認のうえ
「進めてください」と正式承認した。`docs/data/one_night_match_techniques.xlsx`にも
ジャックの技候補があったが、Misaki（Phase 10A 6章）と同じ理由——技名・数値・
判定モデル（凶attribute・KO/SUBMISSION決着・Speed等の廃止フィールド）が
SSOT20章と一致しない別系統の旧候補——で不採用とした。

| # | 技名 | ID | category | attribute | family | Cost | DMG | HEAT | 状態 | 備考 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | チョーク攻撃 | `jack_choke_attack` | NORMAL | rough | CHOKE | ラフ1 | 10 | 20 | STAND→STAND | 20章確定値。23.4章のCHOKE例そのもの |
| 2 | 顔面かきむしり | `jack_face_claw` | NORMAL | rough | CLAW | ラフ1 | 10 | 20 | STAND→STAND | 20章確定値 |
| 3 | 闇討ちキック | `jack_sneak_kick` | NORMAL | strike | KICK | 打1 | 10 | 10 | STAND→STAND | Phase 10B新規確定（基本技） |
| 4 | 黒蝶エルボー | `jack_elbow` | NORMAL | strike | ELBOW | 打1 | 10 | 10 | STAND→STAND | Phase 10B新規確定（基本技） |
| 5 | 闇討ちラリアット | `jack_sneak_lariat` | NORMAL | strike | LARIAT | 打2 | 20 | 20 | STAND→DOWN | Phase 10B新規確定 |
| 6 | 黒蝶スープレックス | `jack_suplex` | NORMAL | throwing | SUPLEX | 投1 | 10 | 10 | STAND→STAND | Phase 10B新規確定（投1枠を使用） |
| 7 | アームロック | `jack_armlock` | NORMAL | joint | ARMBAR | 関1 | 10 | 10 | STAND→STAND | Phase 10B新規確定（関1枠を使用） |
| 8 | とどめの踏みつけ | `jack_finishing_stomp` | NORMAL | strike | STOMP | 打1 | 10 | 20 | DOWN→DOWN | 20章「踏みつけは通常技」・23.3章STOMP=STRIKE groupに対応 |
| 9 | 黒蝶クラッシュ | `jack_kurocho_crash` | SIGNATURE | rough | TACKLE | ラフ2 | 20 | 40 | STAND→DOWN | 20章確定値 |
| 10 | 黒蝶ニードロップ | `jack_knee_drop` | SIGNATURE | strike | KNEE | 打2 | 20 | 30 | STAND→DOWN | Phase 10B新規確定 |
| 11 | 黒蝶ドライバー | `jack_kurocho_driver` | FINISHER | rough | DRIVER | ラフ3 | 30 | 50 | STAND→DOWN | 20章確定値。finisherType=directPin |
| 12 | ブラック・ジャック | `jack_black_jack` | FINISHER | strike | LARIAT | 打3 | 30 | 50 | STAND→DOWN | 20章確定値。finisherType=normal |

### 10.1 finisherType確定経緯

`combat_rules_v1.md`20章は黒蝶ドライバーを「妨害型FINISHER」、ブラック・ジャックを
「決着型FINISHER」とのみ記載し、`CombatV1FinisherType`（normal/directPin/submission）
のどれに対応するかは未確定だった。Phase 10Bセッションでユーザーへ確認のうえ、
以下で正式確定した。

- **黒蝶ドライバー**: `finisherType = directPin`（妨害型＝成功後すぐPINへ自動移行し
  主導権を握る）。
- **ブラック・ジャック**: `finisherType = normal`（決着型＝成功後、攻撃側が任意で
  PINを選択する強力な通常技）。

### 10.2 State Mapping（全12技、Phase 10Bで新規確定）

STAND始動11技（#1〜7・9〜12）は`requiredOpponentState:
CombatV1WrestlerPosture.stand`を明示的に設定する（nullは「STAND/DOWNどちらでも
使用可能」を意味するため、Phase 10A Codexレビュー指摘と同じ不整合を作らないため）。
DOWN始動は#8（とどめの踏みつけ）のみ。

---

## 11. 黒蝶ジャック — Production Counter（3種、Phase 10B）

`combat_rules_v1.md`21章・`combat_v1_open_questions.md`のいずれにもジャック用
COUNTERの正式割当は記載がなかった。Phase 10Aミサキ4章と同じ「広範囲/中範囲/専門」
テンプレートで、Phase 10Bセッションでユーザーが確認のうえ以下を正式採用した。
attribute（支払い属性）は、ジャックが保有量の多いENERGY属性（打3／ラフ4）の範囲内
から選定した。COUNTERは返すTECHNIQUEのENERGY Cost合計をCounter側の単一属性で
支払う（`combat_rules_v1.md`7章）ため、関1／投1でもCost1のTECHNIQUEに対しては
支払い可能だが、Cost2以上には対応できず、対象family/groupのCost分布次第では
実用性が低い。そのためより保有量の多い打／ラフを選定した（関・飛の保有量が0で
Counter属性に選ぶと常に支払い不能になるミサキ4章のケースとは異なる）。

| # | 役割 | 名称 | ID | attribute | counterableFamilies | counterableGroups |
|---|---|---|---|---|---|---|
| 1 | 広範囲型 | 闇討ちガード | `counter_jack_sneak_guard` | strike（打） | — | [STRIKE] |
| 2 | 中範囲型 | 黒蝶リバーサル | `counter_jack_reversal` | rough（ラフ） | [SUPLEX, BACKDROP, POWERBOMB, DRIVER] | — |
| 3 | 専門型 | チョークブレイク | `counter_jack_choke_break` | strike（打） | [CHOKE, CLAW] | — |

---

## 12. 黒蝶ジャック — Production Deck（30枚、Phase 10B）

ROUGH技の枚数は`combat_rules_v1.md`20章の確定基準（チョーク攻撃×1・顔面かきむしり×1・
黒蝶クラッシュ×2・黒蝶ドライバー×1＝計5枚）をそのまま採用した。残りはPhase 10Bで
新規確定した配分。

| category | 内訳 | 枚数 |
|---|---|---|
| NORMAL | チョーク攻撃×1、顔面かきむしり×1、闇討ちキック×3、黒蝶エルボー×3、闇討ちラリアット×3、黒蝶スープレックス×2、アームロック×2、とどめの踏みつけ×3 | 18 |
| SIGNATURE | 黒蝶クラッシュ×2、黒蝶ニードロップ×2 | 4 |
| FINISHER | 黒蝶ドライバー×1、ブラック・ジャック×1 | 2 |
| COUNTER | 闇討ちガード×2、黒蝶リバーサル×2、チョークブレイク×2 | 6 |
| **合計** | | **30** |

同名上限（`CombatV1RulesConfig`既定値）: NORMAL 3／SIGNATURE 2／FINISHER
1／COUNTER 2のいずれにも収まる。`combat_v1_open_questions.md`の未解決項目#2
（ジャックのデッキ配分＝SIGNATURE/FINISHER/COUNTER内訳が一次資料に記載なし）は
本節で解決した。

`buildJackDeck({required String ownerId})`は`buildMisakiDeck`と同じowner
namespace方式を踏襲する（7章参照。instanceIdは`<ownerId>_<cardId>_#<連番>`、
ownerIdが空/空白文字のみの場合は`ArgumentError`）。Jack vs Jackミラーマッチ
（`buildJackDeck(ownerId: 'player-a')`/`buildJackDeck(ownerId: 'player-b')`）で
2デッキ計60枚のinstanceIdがすべて一意であることをProduction
test（`test/combat_v1/combat_v1_production_jack_test.dart`）で検証した。
Misaki(player-a) vs Jack(player-b)という異なるレスラー同士の組み合わせでも
同様に60枚すべて一意であることをあわせて検証した。

---

## 14. Production WrestlerとProduction Deckの対応関係（Phase 10B GitHub Codexレビュー指摘対応で確定）

`CombatV1Engine.start(wrestlerA: jackWrestler, deckA: buildMisakiDeck(...), ...)`
のような、あるwrestler向けのDeckを別のwrestlerへ渡す取り違えが、
`validateDeck`・`CombatV1Engine.start`いずれからも拒否されずに成立してしまう
不具合がGitHub Codex自動レビューで指摘された（PR #11、P2）。

- **原因**: `CombatV1DeckDefinition.wrestlerId`（Phase 1から存在する汎用
  Domainフィールド）と、`CombatV1Engine.start`に実際に渡された
  `CombatV1Wrestler.id`を比較する仕組みが一度も実装されていなかった。
- **修正**: `validateDeck`（`combat_v1_deck_validation.dart`）へ任意（既定
  `null`）の`wrestlerId`引数を追加し、非nullかつ`deck.wrestlerId`と不一致
  なら`CombatV1DeckValidationErrorCode.wrestlerMismatch`で拒否するよう
  変更した。`CombatV1Engine.start`は、内部で行っている`deckA`/`deckB`の
  `validateDeck`呼び出しへ、それぞれ`wrestlerA.id`/`wrestlerB.id`を渡す
  よう変更した。これにより`Engine.start`を直接呼ぶ経路でも取り違えを
  確実に拒否する。
- **設計方針**: Misaki/Jack等の固有IDはCore Engine側に一切ハードコード
  しない（`CombatV1Wrestler.id`と`CombatV1DeckDefinition.wrestlerId`という
  既存の汎用String同士を比較するのみ）。Phase 10C以降に火神アカリ・白銀
  レイナのProduction Deckを追加する場合も、同じ仕組みがそのまま機能する。
- **後方互換性**: `wrestlerId`引数は既定`null`（チェックをスキップ）のため、
  wrestlerとの対応関係を意図的に持たない既存の呼び出し元・fixtureベースの
  テストは無変更のまま動作する。
- **ownerIdとの関係（混同しないこと）**: `ownerId`（7章）はphysical card
  instance namespace専用の識別子であり、Production Wrestler ID
  （`CombatV1Wrestler.id`）とは別概念のまま維持する。`ownerId ==
  wrestler.id`を要求する設計にはしていない——`buildMisakiDeck`/
  `buildJackDeck`が返す`CombatV1DeckDefinition.wrestlerId`は、`ownerId`に
  何を渡しても常にそのレスラー自身のID（`"misaki"`/`"jack"`）のまま変化
  しない（`combat_v1_production_wrestler_deck_integrity_test.dart`で
  直接検証済み）。

検証は`test/combat_v1/combat_v1_production_wrestler_deck_integrity_test.dart`
（Misaki/Jack正常系・mismatch双方向・owner namespace独立性・mirror
match・cross-wrestler・既存validation回帰の各観点）と、
`test/combat_v1/combat_v1_deck_validation_test.dart`（`wrestlerId`引数の
単体テスト）で行った。

---

## 16. 火神アカリ — Production Wrestler（Phase 10C）

| フィールド | 値 |
|---|---|
| id | `akari` |
| name | 火神アカリ |

### 16.1 ENERGY Pool（Phase 10C Production Data Final Specification 1章で確定）

`combat_rules_v1.md`18章の検証値を、Phase 10C-0.5セッション（A1）でユーザーが確認のうえ
そのままProduction値として正式採用した。

| 属性 | 値 |
|---|---|
| 打（strike） | 5 |
| 関（joint） | 1 |
| 投（throwing） | 2 |
| 飛（aerial） | 2 |
| ラフ（rough） | 0 |
| ＊（wild） | 1 |
| **合計** | **11** |

---

## 17. 火神アカリ — Production Technique（12種、Phase 10C）

`combat_rules_v1.md`22章は「一次資料に記載がなく未確定」としていた全12技を、Phase
10C-0（調査）→Phase 10C-0.5（仕様案作成・A1〜A10・A7最終回答）→本Phase（実装）の3段階で
確定した。旧Excel（`docs/data/one_night_match_techniques.xlsx`「技一覧」シートの
`td_p7a_akari_*`候補）は、Misaki（Phase 10A 6章）と同じ理由（Speed/KO等の旧仕様
フィールドを持つ別系統）で数値そのものは不採用としたが、技名・family分類の一部は
参考にした（下表参照）。

| # | 技名 | ID | category | attribute | family | Cost | DMG | HEAT | 状態 | 備考 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | エルボースマッシュ | `akari_elbow_smash` | NORMAL | strike | elbow | 打1 | 10 | 10 | STAND→STAND | SSOT21章確定名 |
| 2 | ミドルキック | `akari_middle_kick` | NORMAL | strike | kick | 打1 | 10 | 10 | STAND→STAND | SSOT21章確定名 |
| 3 | ドロップキック | `akari_dropkick` | NORMAL | aerial | dropKick | 飛1 | 10 | 20 | STAND→DOWN | |
| 4 | ランニングニー | `akari_running_knee` | NORMAL | strike | knee | 打2 | 20 | 20 | STAND→DOWN | |
| 5 | アームホイップ | `akari_arm_whip` | NORMAL | throwing | armDrag | 投1 | 10 | 10 | STAND→STAND | |
| 6 | フライングクロスボディ | `akari_flying_crossbody` | NORMAL | aerial | bodyPress | 飛2 | 20 | 20 | DOWN→DOWN | required: DOWN |
| 7 | スイングDDT | `akari_swing_ddt` | NORMAL | throwing | ddt | 投2 | 20 | 20 | STAND→DOWN | |
| 8 | アームキャッチ | `akari_arm_catch` | NORMAL | joint | armbar | 関1 | 10 | 10 | STAND→STAND | submissionHold=true（17.3章参照） |
| 9 | フェニックス・アームドラッグ | `akari_phoenix_armdrag` | SIGNATURE | throwing | armDrag | 投2 | 20 | 30 | STAND→DOWN | |
| 10 | ソウルハイキック | `akari_soul_highkick` | SIGNATURE | strike | kick | 打3 | 30 | 40 | STAND→DOWN | |
| 11 | フェニックススプラッシュ | `akari_phoenix_splash` | FINISHER | aerial | splash | 飛3 | 30 | 40 | DOWN→DOWN | finisherType=directPin、required: DOWN |
| 12 | レッドフレアキック | `akari_red_flare_kick` | FINISHER | strike | kick | 打3 | 30 | 50 | STAND→DOWN | finisherType=normal |

### 17.1 候補技構成からの変更点（Phase 10C-0.5 A2で確定）

Phase 10C-0で発見したExcel候補12技（`akari_forearm`相当の「フォアアーム」を含む）のうち、
「フォアアーム」を削除し、候補に存在しなかった新規技「アームキャッチ」を追加した。理由:
Akariの関節（joint）ENERGYは1しかなく、候補12技のどれも関節attributeを使用していない
ため、そのまま実装すると関1が一切使われない死に属性になる。Jackが唯一の関節技
「アームロック」（Phase 10B）でjoint1を使い切ったのと同じパターンで、Akari用にも
唯一の関節技を新設した。

### 17.2 requiredOpponentState==down の設計理由（Phase 10C-0.5で確定）

フライングクロスボディ・フェニックススプラッシュの2技はrequiredOpponentState==down
とした。理由は「実際のプロレスでは主にグラウンドの相手へ使うため」という実技上の理由
**ではなく**、「Akariのダウンを奪う→飛び技へ繋ぐ、というコンボ構造を作るため」という
ゲームデザイン上の理由である（Phase 10C-0.5セッションでユーザーが明示的に修正・確定
した記述）。フェニックススプラッシュはCombat Ver.1 Production初のDOWN始動FINISHERで
あり、既存Misaki/Jackの4 FINISHERはいずれもSTAND始動だった点との差別化。

### 17.3 submissionHold設計（Phase 10C-0.5 A2・A3で確定）

`akari_arm_catch`（アームキャッチ）にのみ`submissionHold=true`を付与した。Misaki/Jackは
これまでsubmissionHold=trueの技を1つも持たず、本技がCombat Ver.1 Productionにおける
SUBMISSION機構の初採用となる。Akariの決着方針は「PIN＋SUBMISSION」（PIN主・SUBMISSION
副）であり、関1という極小プールを踏まえ、SUBMISSION専用FINISHERは設けず、低頻度・
低コストのNORMAL技1種のみでSUBMISSION勝ち筋を表現する設計とした（「主な決着に
SUBMISSIONと書いてあるから機械的にSUBMISSION FINISHERにする」という判断は行っていない）。

### 17.4 finisherType確定経緯（Phase 10C-0.5 A3で確定）

- **フェニックススプラッシュ**: `finisherType = directPin`。飛属性のCost3は保有プール
  （飛2）を超えるため、宣言時に＊(wild)1で不足分を補う（`resolveEnergyPayment`の既存
  ロジックがそのまま処理する）。
- **レッドフレアキック**: `finisherType = normal`（成功後、攻撃側が任意でPINを選択できる）。

---

## 18. 火神アカリ — Production Counter（3種、Phase 10C）

Phase 10Aミサキ・Phase 10Bジャックと同じ「広範囲/中範囲/専門」テンプレートで、Phase
10C-0.5セッション（A5）でユーザーが確認のうえ以下を正式採用した。attribute（支払い属性）
は、Akariが実際に保有するENERGY属性（打5／投2／飛2）の範囲内から選定した（関1・ラフ0は
除外した——関1は「Cost1攻撃しか返せない極端に狭いCounter」になってしまうため、Misaki
4章と同じ理由で不採用とした）。

| # | 役割 | 名称 | ID | attribute | counterableFamilies | counterableGroups |
|---|---|---|---|---|---|---|
| 1 | 広範囲型 | 紅蓮ガード | `counter_akari_crimson_guard` | strike（打） | — | [STRIKE] |
| 2 | 中範囲型 | フェニックス投げ返し | `counter_akari_phoenix_throw_reversal` | throwing（投） | [BACKDROP, SUPLEX] | — |
| 3 | 専門型 | スカイインターセプト | `counter_akari_sky_intercept` | aerial（飛） | [SPLASH] | — |

②は既存`counter_suplex_reversal`（Misaki）と支払い属性・target familyが機械的に同一
だが、Phase 10C-0.5 A5でユーザーが「レスラー固有のカードとして扱う（新規flavor名・
新規definitionとする）」方針を明示的に選択したため、共有definitionへの統合は行わず
新規IDで実装した。

---

## 19. 火神アカリ — Production Deck（30枚、Phase 10C）

`combat_rules_v1.md`21章の配分方針（基本NORMAL＝エルボースマッシュ×3・ミドルキック×3、
その他NORMALは原則×2、SIGNATURE各×2、FINISHER各×1、COUNTER各×2）をそのまま正式採用した。

| category | 内訳 | 枚数 |
|---|---|---|
| NORMAL | エルボースマッシュ×3、ミドルキック×3、ドロップキック×2、ランニングニー×2、アームホイップ×2、フライングクロスボディ×2、スイングDDT×2、アームキャッチ×2 | 18 |
| SIGNATURE | フェニックス・アームドラッグ×2、ソウルハイキック×2 | 4 |
| FINISHER | フェニックススプラッシュ×1、レッドフレアキック×1 | 2 |
| COUNTER | 紅蓮ガード×2、フェニックス投げ返し×2、スカイインターセプト×2 | 6 |
| **合計** | | **30** |

`buildAkariDeck({required String ownerId})`は`buildMisakiDeck`/`buildJackDeck`と同じ
owner namespace方式を踏襲する（7章参照）。

---

## 20. 白銀レイナ — Production Wrestler（Phase 10C）

| フィールド | 値 |
|---|---|
| id | `reina` |
| name | 白銀レイナ |

### 20.1 ENERGY Pool（Phase 10C Production Data Final Specification 5章で確定）

`combat_rules_v1.md`18章の検証値をそのまま採用した（A6）。

| 属性 | 値 |
|---|---|
| 打（strike） | 2 |
| 関（joint） | 4 |
| 投（throwing） | 3 |
| 飛（aerial） | 0 |
| ラフ（rough） | 0 |
| ＊（wild） | 1 |
| **合計** | **10** |

---

## 21. 白銀レイナ — Production Technique（12種、Phase 10C）

### 21.1 候補技構成からの変更点（Phase 10C-0.5 A7で確定、複数ラウンドの検討を経た最終回答）

Phase 10C-0で発見したExcel候補12技は、family重複が多く（figureFourが3回、headlockが
2回）、NORMALの選択肢が単調になる懸念があった。ユーザーから「関節技に明確に偏った
レスラーで構わない（Misaki=投げ／Jack=ラフ／Akari=打撃＋飛び／Reina=関節＋投げ、という
4人差別化を優先）」という方針が示され、以下を最終確定した。

- 「ヘッドロック」（サイドヘッドロックとfamily完全重複の劣化コピー）を削除し、
  「アブドミナルストレッチ」（joint、family=`stretch`）を新規採用した。`stretch`
  familyはCombat Ver.1 Production全体で初採用（Misaki/Jackとも未使用）。
- 「アイスロック」（FINISHER）のfamilyを、当初案のfigureFour（足四の字/フィギュア
  フォーとの三重重複）から`legLock`へ変更した。

比較検討では「ニーストライク（strike）を採用する案」「ヘッドロックを残す案」
「アブドミナルストレッチ（joint/stretch）を採用する案」の3案を提示し、Reinaを
「関節に明確に偏らせる」方針を最も直接的に満たす3番目の案が最終的に採用された。

### 21.2 Technique一覧

| # | 技名 | ID | category | attribute | family | Cost | DMG | HEAT | 状態 | 備考 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | サイドヘッドロック | `reina_side_headlock` | NORMAL | joint | headlock | 関1 | 10 | 10 | STAND→STAND | SSOT21章確定名 |
| 2 | 足四の字 | `reina_leg_figure_four` | NORMAL | joint | figureFour | 関1 | 10 | 10 | STAND→STAND | SSOT21章確定名 |
| 3 | ドラゴンスクリュー | `reina_dragon_screw` | NORMAL | throwing | legTakedown | 投1 | 10 | 20 | STAND→DOWN | SSOT21章記載技 |
| 4 | ドロップトーホールド | `reina_drop_toehold` | NORMAL | throwing | legTakedown | 投1 | 10 | 20 | STAND→DOWN | |
| 5 | エルボー | `reina_elbow` | NORMAL | strike | elbow | 打1 | 10 | 10 | STAND→STAND | |
| 6 | アブドミナルストレッチ | `reina_abdominal_stretch` | NORMAL | joint | **stretch** | 関1 | 10 | 10 | STAND→STAND | Phase 10C-0.5 A7で新規確定。resultOpponentState=null |
| 7 | アームブリーカー | `reina_arm_breaker` | NORMAL | joint | armbar | 関1 | 10 | 10 | STAND→STAND | |
| 8 | 腕ひしぎ | `reina_ude_hishigi` | NORMAL | joint | armbar | 関2 | 20 | 20 | DOWN→DOWN | submissionHold=true |
| 9 | 白銀クロスフェイス | `reina_silver_crossface` | SIGNATURE | joint | crossface | 関2 | 20 | 30 | STAND→DOWN | submissionHold=true |
| 10 | フィギュアフォー | `reina_figure_four_lock` | SIGNATURE | joint | figureFour | 関3 | 30 | 40 | STAND→DOWN | submissionHold=false |
| 11 | アイスロック | `reina_ice_lock` | FINISHER | joint | legLock | 関3 | 30 | 40 | STAND→DOWN | finisherType=submission、family変更経緯は21.1章参照 |
| 12 | エターナルクロス | `reina_eternal_cross` | FINISHER | joint | crossface | 関4 | 40 | 50 | STAND→DOWN | finisherType=normal |

### 21.3 submissionHold設計（Phase 10C-0.5 A9で確定）

`submissionHold=true`は`reina_ude_hishigi`（腕ひしぎ）・`reina_silver_crossface`
（白銀クロスフェイス）の2種のみ。最頻出NORMAL（足四の字・サイドヘッドロック、各×3枚）
には付与しない方針を明示的に確定した（SUBMISSION自動判定の過度な頻発を避けるため）。
Reinaの決着方針「SUBMISSION＋PIN」（SUBMISSION主・PIN副）を反映し、Akari（副）より
明確に厚い構成としたが、FINISHERのfinisherType=submissionと合わせても、いずれも
「相手HP50以下」という閾値条件を経由するため、試合序盤からの連続SUBMISSION終了は
起きにくい。

### 21.4 finisherType確定経緯（Phase 10C-0.5 A8で確定）

- **アイスロック**: `finisherType = submission`。Reinaの決着方針「SUBMISSION＋PIN」の
  うちSUBMISSIONを主決着として表現する。
- **エターナルクロス**: `finisherType = normal`。関4（保有プール全量）を使い切る
  最大火力技。成功後、攻撃側が任意でPINを選択できる。

---

## 22. 白銀レイナ — Production Counter（3種、Phase 10C）

Phase 10Aミサキ・Phase 10Bジャックと同じテンプレートで、Phase 10C-0.5セッション
（A10）でユーザーが確認のうえ以下を正式採用した。attributeは、Reinaが実際に保有する
ENERGY属性（投3／関4／打2）の範囲内から選定した（飛0・ラフ0は除外した）。広範囲型に
投3（中間値）、中範囲型に関4（最大値、本格関節技への深い対応力）、専門型に打2
（最小値、Cost2級のLARIATに限定）を割り当てることで、各Counterが実際に支払い可能な
範囲に対象を絞り込んだ。

| # | 役割 | 名称 | ID | attribute | counterableFamilies | counterableGroups |
|---|---|---|---|---|---|---|
| 1 | 広範囲型 | 足取りガード | `counter_reina_leg_catch_guard` | throwing（投） | — | [THROW] |
| 2 | 中範囲型 | 白銀ロックリバーサル | `counter_reina_silver_lock_reversal` | joint（関） | [CROSSFACE, FIGURE_FOUR] | — |
| 3 | 専門型 | 銀閃カウンター | `counter_reina_silver_flash_counter` | strike（打） | [LARIAT] | — |

`stretch` family（アブドミナルストレッチ）を専門targetするCounterは現状存在しない。
これはPhase 10C-0.5 A7最終回答でユーザーが明示的に許容した仕様であり、Counter
coverageを補うための新規Counter追加は行っていない（将来のSimulatorによる勝率・
使用率検証後に必要なら調整する方針）。

---

## 23. 白銀レイナ — Production Deck（30枚、Phase 10C）

`combat_rules_v1.md`21章の配分方針（基本NORMAL＝サイドヘッドロック×3・足四の字×3、
その他NORMALは原則×2、SIGNATURE各×2、FINISHER各×1、COUNTER各×2）をそのまま正式採用した。

| category | 内訳 | 枚数 |
|---|---|---|
| NORMAL | サイドヘッドロック×3、足四の字×3、ドラゴンスクリュー×2、ドロップトーホールド×2、エルボー×2、アブドミナルストレッチ×2、アームブリーカー×2、腕ひしぎ×2 | 18 |
| SIGNATURE | 白銀クロスフェイス×2、フィギュアフォー×2 | 4 |
| FINISHER | アイスロック×1、エターナルクロス×1 | 2 |
| COUNTER | 足取りガード×2、白銀ロックリバーサル×2、銀閃カウンター×2 | 6 |
| **合計** | | **30** |

`buildReinaDeck({required String ownerId})`は`buildMisakiDeck`/`buildJackDeck`/
`buildAkariDeck`と同じowner namespace方式を踏襲する（7章参照）。

---

## 24. 4人Production Catalog完成（Phase 10C）

`combat_v1_production_catalog.dart`の`productionCardCatalog`は、Misaki・Jack・
Akari・Reinaの4人分のTechnique（12種×4＝48）・Counter（3種×4＝12）を統合する。
14章で確定した`validateDeck`の`wrestlerId`引数によるWrestler/Deck整合性チェック
（`wrestlerMismatch`）は、Core Engine側の変更なしにAkari/Reinaへもそのまま機能する
（`CombatV1Wrestler.id`と`CombatV1DeckDefinition.wrestlerId`という既存の汎用String
同士の比較のみのため）。

検証は`test/combat_v1/combat_v1_production_akari_test.dart`・
`combat_v1_production_reina_test.dart`（各レスラー単体のProduction Data、Phase
10A/10Bと同型）、`combat_v1_production_wrestler_deck_integrity_test.dart`
（4人roster全組み合わせのmismatch・cross-wrestler Engine.start、既存Misaki/Jack
groupは無変更のまま拡張）、`combat_v1_production_akari_vs_reina_command_test.dart`
（異なるレスラー同士のdeclareTechnique→declineCounter/playCounter経路）で行った。

---

## 25. 変更履歴

- **Phase 10-Precondition〜10A**: 本書を新規作成。上記1〜6章の内容を、Phase
  10Aセッション内でユーザーへ確認のうえ正式確定した。
- **Phase 10A（GitHub Codexレビュー指摘対応）**: 7章を新規追加。Production
  Deck builderのinstanceId生成方式を、`wrestlerId`固定から必須`ownerId`
  パラメータ方式へ変更した経緯を記録した。
- **Phase 10B（GitHub Codexレビュー指摘P2対応）**: 14章を新規追加。
  Production WrestlerとProduction Deckの取り違えを`validateDeck`/
  `CombatV1Engine.start`で拒否する仕組みを追加した経緯を記録した。
- **Phase 10B**: 9〜12章を新規追加。黒蝶ジャックのProduction
  Wrestler／Technique（12種）／Counter（3種）／Deck（30枚）を、Phase
  10Aと同じowner namespace方式・広範囲/中範囲/専門Counterテンプレートで
  正式確定した。`combat_v1_open_questions.md`未解決項目#2（ジャックのデッキ
  配分）を解決した。
- **Phase 10C-0（調査）**: 火神アカリ・白銀レイナの既存情報（SSOT・旧Engine・
  Excel候補・現行taxonomy）を調査し、未確定事項を整理した（コード変更なし）。
- **Phase 10C-0.5（仕様案作成）**: 「Phase 10C Production Data Final
  Specification」を作成し、A1〜A10（ENERGY・Technique 24種・Counter
  6種・FINISHER・submissionHold・state mapping・4人バランス比較）についてユーザー
  承認を得た。A7（Reina NORMAL第6枠）のみ複数案比較を経て最終確定した
  （アブドミナルストレッチ、family=stretch）。実装はまだ行わなかった。
- **Phase 10C（実装）**: 16〜24章を新規追加。火神アカリ・白銀レイナのProduction
  Wrestler／Technique（12種×2）／Counter（3種×2）／Deck（30枚×2）を、Final
  Specificationの値を厳密に反映して実装した。`combat_v1_production_catalog.dart`が
  Misaki・Jack・Akari・Reinaの4人構成になった。既存Misaki/Jackの
  Production Data・テストは変更していない。Core
  Engine／Domain model／既存enum taxonomyの変更は不要だった（`stretch`
  familyは既存enumの値をアカリ・レイナで初めて使用したのみ）。
  `combat_v1_open_questions.md`未解決項目#3（アカリ・レイナの技データ）を解決した。
