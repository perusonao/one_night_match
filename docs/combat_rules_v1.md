# ONE NIGHT MATCH Combat Ver.1 戦闘ルール仕様書（SSOT）

- ステータス: **Phase 0 確定版**（Combat Ver.1 Engine設計フェーズの正式仕様。ゲームロジックの実装はまだ行われていない）
- 位置づけ: **Combat Ver.1（④ Combat Ver.1 Engine）のSingle Source of Truth（SSOT）**。
  Combat Ver.1の仕様と実装（`lib/src/combat_v1/`、Phase 1以降に新規作成予定）に矛盾がある場合、
  原則として本書を優先する。本書自体を変更する場合は変更理由を明記して更新する（29章「変更履歴」参照）。
- 対象読者: Combat Ver.1のEngine実装・CPU実装・シミュレーション実装・バランス調整に関わる全セッション。
- 出典: ユーザー提供資料「ONE_NIGHT_MATCH_戦闘ルール_Ver.1_検証版」（.docx、4レスラー総当たり検証用・
  2026-08-09時点）を一次資料とし、Combat Ver.1 Engine設計セッション（Phase 0）で確定した追加事項を統合したもの。
- 関連ドキュメント:
  - [`docs/design/combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) — Phase 1技術設計
    （ディレクトリ構成・データモデル・State Machine・Engine API・テスト計画）
  - [`docs/design/combat_v1_open_questions.md`](design/combat_v1_open_questions.md) — 未決定事項一覧
- 既存3エンジンとの関係: 本書はいずれの既存エンジンの仕様も変更しない。
  - ① Prototype（`lib/src/game.dart`）
  - ② Level Match（`lib/src/level_match/`、`lib/src/wrestler_editor/`）
  - ③ Technique Match（`lib/src/technique_deck/`、`lib/src/playtest_analytics/`）

  Combat Ver.1は上記3エンジンに**直接実装しない**。独立した第4のエンジン
  （④ Combat Ver.1 Engine、想定配置 `lib/src/combat_v1/`）として新規構築する（1章参照）。

> **本書の読み方**: 本書はCombat Ver.1のルールブックである。未確定・検証中の数値・技名は
> 「検証用」「未確定」「検証候補」「後続Phaseで決定」のいずれかを明記する。**推測による補完は行わない**。
> 一次資料（docx）に記載がない項目は、本セッションで新たに確定した場合のみ追記し、それ以外は
> 「未確定」として28章にまとめる。

---

## 0. この文書の位置づけ

本書は、ONE NIGHT MATCHの新しい戦闘仕様「Ver.1」を固定し、火神アカリ／白銀レイナ／豪田ミサキ／黒蝶ジャックの
4人で総当たり検証を行うための基準仕様である。未確定・仮称の技名や数値は「検証用」として扱い、検証後に調整する
（一次資料 docx 1章より）。

Combat Ver.1 Engine設計セッション（Phase 0）により、以下が追加で確定した。

- Ver.1は既存3エンジンに実装せず、独立した新エンジン（④）として構築する（1章）。
- HP・KOC・PINカードはいずれも試合開始時から存在する基本リソースとして扱う（2章）。
- FINISHERの決着方式（NORMAL／DIRECT PIN／SUBMISSION）は独立したenumで表現し、
  技が持つ「SUBMISSION技かどうか」という属性とは別概念として扱う（13章）。
- 開発は Phase 0〜16 の順で進め、Ver.1の基本ルールが一通り動作した時点で
  旧3エンジンを削除する「Legacy Engine Removal Gate」を設ける（26・27章）。

---

## 1. Engine方針（④ Combat Ver.1 Engine）

- Combat Ver.1は、①Prototype／②Level Match／③Technique Matchのいずれにも直接実装しない。
- 新しく「④ Combat Ver.1 Engine」を独立して構築する。想定配置は `lib/src/combat_v1/`。
- ④は①②③のコードを**直接importして成立させる構造にはしない**（独立性を優先する）。
- 既存資産（設計パターン・アルゴリズム・テスト方法・Simulator設計等）を**参考にすることはできる**が、
  コードそのものへの依存は作らない。
- Combat EngineはUI非依存（Pure Dart寄り）の構造とする。Flutter Widgetをエンジンへ渡す設計は禁止する。
  UI／CPU／Simulator／Testが同じCommand APIを呼び出せる構造を目指す。
- 詳細な技術設計（ディレクトリ構成・データモデル・API）は
  [`docs/design/combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) を参照。

---

## 2. 基本リソース

Combat Ver.1 Engineが扱う主要リソース: **HP／KOC／ENERGY／HEAT／PIN CARD／HAND／DECK／DISCARD／STAND・DOWN**。

| 項目 | 仕様 |
|---|---|
| HP | **初期値150（全レスラー共通、レスラーごとの差は設けない）**。TECHNIQUEのDMGで減少。0未満にはならない（14章）。 |
| KOC | 初期値**10**。PINのカウント（1／2／2.9）／SUBMISSIONからの脱出に使用（8・9・10章）。 |
| ENERGY | レスラーごとに属性別に定義される固定プール。自ターン開始時に全回復。TECHNIQUEとCOUNTERで消費（5章）。 |
| HEAT | 両者共有。TECHNIQUE等で10単位を基本に上昇。**200以上でFINISHER解禁**。消費しない（12章）。 |
| 状態 | STAND／DOWN。技の使用条件、PIN条件などに影響（11章）。 |
| PINカード | 共有4枚。試合開始時は各プレイヤー2枚ずつ保持。移動ルールは9章参照。 |
| HAND／DECK／DISCARD | 30枚デッキ、初期手札5枚、山札切れは捨て札シャッフルで再構築（FATIGUEなし、16章）。 |

---

## 3. デッキ

各レスラー30枚固定。

| 区分 | 枚数 | 備考 |
|---|---|---|
| NORMAL | 18枚 | 8種類。基本技は3枚、その他は原則2枚（検証用の暫定基準）。 |
| SIGNATURE | 4枚 | 2種類×2枚。 |
| FINISHER | 2枚 | 2種類×1枚。 |
| COUNTER | 6枚 | 3種類×2枚。 |
| **合計** | **30枚** | |

- **ENERGYカードは使用しない**。ENERGYはレスラー固有の固定プールであり、デッキに含めない（5章）。
- 初期手札は5枚。
- NORMALの同名カード上限は3枚を基本とする。
- 正式な4レスラーのデッキ内容は後続Phase（Phase 10想定）で完成させる。21章の「30枚デッキ配分（現時点）」は
  検証段階の暫定基準であり、確定値ではない。

---

## 4. ターン進行

自ターンの流れ:

1. 自ターン開始時にENERGYを全回復する。
2. 山札から1枚引く。
3. 手札から任意の1枚を捨てる（手札循環）。
4. DOWN状態なら、起き上がり／RESTなどの処理を行う（11章、Phase 7で実装）。
5. 使用条件を満たすTECHNIQUEを使用する。
6. TECHNIQUEまたはCOUNTERを1枚使用したら、原則として山札から1枚補充する。
7. 攻撃継続、PIN、SUBMISSION、またはターン終了を選択する。
8. 山札がなくなった場合は捨て札をシャッフルして新しい山札とする。FATIGUEペナルティは設けない（16章）。

**Combo Speedは採用しない**。同一ターン内のTECHNIQUE使用回数は、基本的にENERGYによって制限する。
ENERGYが残っており、かつその他の使用条件（相手の状態等）を満たしていれば、
TECHNIQUE → TECHNIQUE → TECHNIQUE と攻撃を継続できる。Combo Speedのような第二の攻撃回数リソースは導入しない。
ROUGHによる「次ターンTECHNIQUE最大1枚」（15章）は、この通常の複数TECHNIQUE使用を制限する効果として機能する。

---

## 5. ENERGY

ENERGYは属性別に定義される。属性は以下の6種:

**打（strike）／関（joint）／投（throwing）／飛（aerial）／ラフ（rough）／＊（wild）**

- レスラーごとにENERGY配分が異なる（例は18章参照）。
- 自ターン開始時に全回復する。
- TECHNIQUEとCOUNTERの両方で使用する（COUNTERの詳細は7章、Phase 4で実装）。
- **EnergyPool（持っているENERGY）とEnergyCost（技が要求するENERGY）は別モデルとして扱う。**

  例:
  ```
  EnergyPool（アカリ）:  打5 / 関1 / 投2 / 飛2 / ラフ0 / ＊1
  Technique Cost（例）:  打2
  ```

### 5.1 ＊（ワイルドENERGY）

＊はワイルドENERGYである。基本的には、打／関／投／飛／ラフの任意の属性ENERGY COST不足分を補える。

**解決手順（確定）**:
1. 各属性の具体的なENERGY（打・関・投・飛・ラフ）をまず使用する。
2. 各属性で不足している分を合算する。
3. 合算した不足分の合計を、保有する＊ENERGYで補えるか判定する（属性ごとに個別のワイルド消費順序は設けず、
   ＊は属性を跨いで融通できる共有資源として扱う）。

例:
```
残ENERGY:        打1 / 投0 / ＊2
TECHNIQUE COST:   打2 / 投1

不足: 打1 + 投1 = 合計2
＊2があるため使用可能。
```

**COUNTERでの＊ENERGYの扱いはPhase 4まで保留する**。Phase 1のENERGY支払いロジックは、
COUNTER用の別ポリシーへ後から差し替えられる構造にする（技術設計は
[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) 参照）。

---

## 6. TECHNIQUE

TECHNIQUEには属性、技系統、ENERGY COST、DMG、HEAT、使用可能状態などを定義する。

- 技ごとに、STAND→STAND／STAND→DOWN／DOWN→DOWN のような状態変化を表現できる。
- 技系統（TechniqueFamily）は将来COUNTERの成立判定に使う概念だが、正式taxonomyは未確定（23章）。
- DIRECT PIN（PIN不要で成功後に自動的にPINへ移行する性質）は、**FINISHER限定ではなく技全般に付与できる**
  汎用フラグとして扱う（8章、13章とあわせて参照）。
- 技自体が「SUBMISSIONホールド技である」という性質（例: 鳳凰固め、白銀ロック）と、
  「FINISHERとしてSUBMISSION決着方式を持つこと」は**別概念**として扱う（13章で詳述）。

---

## 7. COUNTER（概念定義、本実装はPhase 4）

COUNTERカード自体には固定ENERGY COSTを設定しない。

- 返し必要コストは、**返される側のTECHNIQUEのENERGY COSTと同値**とする。
- COUNTER側は、そのCOUNTERに定義された属性ENERGYを必要量支払う。
- このため高COST技は高火力であるだけでなく、COUNTER側にも多くのENERGYを要求し、自然に返されにくくなる。
- さらに、技系統・COUNTER可能な技系統・使用可能ENERGYを確認して成立判定する想定（23章、技系統の正式化待ち）。
- COUNTER時の＊ENERGYの扱いはPhase 4まで保留（5.1章）。

Phase 1ではCOUNTERの判定・実行ロジックは実装しない。デッキ内にCOUNTERカードのカテゴリは保持する（3章）。

---

## 8. PIN

通常PINは、相手がDOWNで、その攻撃ターン中にTECHNIQUEを成功させている場合に行える。
DIRECT PINを持つ技は成功後に自動的にPINへ移行する。**DIRECT PINでもPINカードを使用する**。

### 8.1 PINカード

- PINカードは共有4枚。試合開始時は各プレイヤー2枚ずつ保持する。
- 1カウント／2カウントで終了したPINでは、使用したPINカードを**原則として**相手側へ移動する。
- 2.9カウントでは移動しない。
- **最低1枚保証（正式採用）**: 現在PINカードが1枚しかないプレイヤーは、そのカードを相手へ移動しない。
  つまり各プレイヤーは常に最低1枚のPINカードを保持する。

### 8.2 カウント

| カウント | 消費KOC | 効果 |
|---|---|---|
| 1カウント | KOC3 | 返した側は山札から追加で1枚引く |
| 2カウント | KOC2 | — |
| 2.9カウント | KOC1 | 攻撃側は攻撃を継続できる |

必要なKOCを支払えなければ3カウントとなり、PIN決着。

Phase 1ではPIN・カウント処理・PINカード移動のロジックは実装しない。PlayerStateにPINカード保有数
（試合開始時2枚ずつ）を正しく初期化するところまでを対象とする（Phase 1範囲は
[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) 参照）。

---

## 9. KOC

KOCは初期値10。PINのカウント（8章）およびSUBMISSIONからの脱出（10章）に使用する共通リソース。

Phase 1ではKOCの消費・判定ロジックは実装しない。PlayerStateにKOC=10が試合開始時に正しく初期化される
ところまでを対象とする。

---

## 10. SUBMISSION

SUBMISSIONはPINカードを使用しない。**通常SUBMISSIONとSUBMISSION FINISHERは別ルールとして扱う**
（13章「FINISHER」とあわせて参照。「技がSUBMISSION属性を持つこと」と「FINISHERとしてSUBMISSION決着方式を
持つこと」を混同しないこと）。

### 10.1 通常SUBMISSION

- 例: 鳳凰固め、白銀ロック
- 相手HP50以下で宣言可能。
- ESCAPE: KOC1を消費。**HP0でもKOCがあればESCAPE可能**。
- KOCを支払えなければGIVE UP。

### 10.2 SUBMISSION FINISHER

- 例: 白銀スペシャル
- HP1〜50: KOC1でESCAPE可能。
- **HP0: 即GIVE UP**（HP0による特殊決着の唯一の例外パターン。14章参照）。

Phase 1ではSUBMISSIONのロジックは実装しない。

---

## 11. REST / DOWN

DOWN状態の自ターンでは、起き上がりまたはRESTを選択できる。

- REST: HP+10回復（**最大150を超えない**）。RESTしたターンはTECHNIQUEを使用できないが、COUNTERは使用可能。
- ダブルダウンはVer.1では採用しない。

Phase 1ではSTAND／DOWNの基本状態モデル（状態の保持と、技によるSTAND→DOWN等の遷移）のみを扱う。
起き上がり／REST選択のロジック自体はPhase 7で実装する。

---

## 12. HEAT

- HEATは両プレイヤー共有。試合開始時 `sharedHeat = 0`。
- TECHNIQUE等で10単位を基本に上昇する。
- **200以上でFINISHER解禁**。
- HEATは消費リソースではない（FINISHER使用時にも消費しない）。

Phase 1ではFINISHER解禁・決着処理は実装しないが、`sharedHeat`の増加自体は最小戦闘ループの一部として扱う。

---

## 13. FINISHER

共有HEAT 200以上で使用可能。FINISHERだから自動的にPINになる、という処理にはしない。

FINISHERの決着方式は、**独立したenumとして明示的に保持する**（技のフラグからの導出ではない）:

```dart
enum CombatV1FinisherType {
  normal,     // 強力な通常TECHNIQUE。成功しても自動PINしない。攻撃側がその後PINを選択できる
  directPin,  // 技成功後に自動的にPIN処理へ移行する
  submission, // 技成功後にFINISHER専用SUBMISSION処理（10.2章）へ移行する
}
```

| 種別 | 意味 |
|---|---|
| A. NORMAL FINISHER | 通常の強力なTECHNIQUEとして扱う。成功→DMG→HEAT→状態変化→その後、必要なら攻撃側が通常PINを選択する。 |
| B. DIRECT PIN FINISHER | 成功後、自動的にPINへ移行する（8章のPINカードルールに従う）。 |
| C. SUBMISSION FINISHER | 専用SUBMISSION処理（10.2章）へ移行する。 |

**重要な区別**: 技モデル上の「この技はSUBMISSIONホールドである」という汎用フラグ（6章）と、
「この技はFINISHERとしてSUBMISSION決着方式（`CombatV1FinisherType.submission`）を持つ」ことは別概念である。
通常技・固有技にもSUBMISSION技は存在しうる（例: 通常SUBMISSION技である鳳凰固め・白銀ロックはFINISHERではない）。
汎用フラグの値だけを見てSUBMISSION FINISHERと自動判定する設計にはしない。

Phase 1ではFINISHER決着ロジックは実装しない。`CombatV1FinisherType` enumおよび技モデル上の表現のみ
先行して定義する。

---

## 14. HP0の扱い

- HP0 = 即KOではない。
- HPは0未満にはならない（0でクランプ）。
- HP0でも試合は継続する。
- HP0でも、ルール上可能であれば以下のような行動を行える:
  - COUNTERする
  - PINからKOCでKICK OUTする
  - 通常SUBMISSIONからKOC1でESCAPEする
  - RESTする
- HP0による特殊な決着は、**その効果が明示された技だけに限定する**。
  例: SUBMISSION FINISHER（10.2章）の「HP0なら即GIVE UP」。
- 通常TECHNIQUEでHP0になっても、それだけでは決着しない（即KO処理は実装しない）。

---

## 15. ROUGH（ラフ属性）

ROUGHは相手のコンボを切る妨害属性として扱う。反則カウント／反則負けはVer.1では導入しない。

- ROUGH属性TECHNIQUEを1枚でも使用したターンはPINできない。
- 最後に成功したTECHNIQUEがROUGHの状態で攻撃ターンを終了した場合、相手は次の自ターンに
  TECHNIQUEを**最大1枚**しか使用できない。
  - **重要**: 「相手が技を一切使用できない」ではない。最大1枚である。
  - COUNTER、REST、起き上がりなどはこの「TECHNIQUE 1枚」に含めない。

Phase 1ではROUGHの特殊処理（PIN不可・次ターン制限）は実装しない。

---

## 16. 山札切れ・手札循環

- 山札がなくなった場合は捨て札をシャッフルして新しい山札とする。
- FATIGUEダメージ、HEAT加算、強制TKOなどのペナルティは発生しない。

### 16.1 手札循環

自ターン開始時: ENERGY全回復 → 1枚ドロー → 1枚捨てる → ACTION（TECHNIQUE使用フェーズ）

- TECHNIQUE使用成功後: 1枚ドロー
- COUNTER使用成功後: 1枚ドロー（COUNTERはPhase 4で実装）

Phase 1では、ターン開始ドロー・1枚捨てる・TECHNIQUE使用後1枚ドロー・山札切れ時の再構築までを実装対象とする。

---

## 17. 4レスラーの方向性

検証段階の方向性。数値・技名は未確定を含む。

| レスラー | 主軸 | 特徴 | 主な決着 |
|---|---|---|---|
| 火神アカリ | 打撃＋飛び | コンボ／爆発力 | PIN＋SUBMISSION |
| 白銀レイナ | 関節＋投げ | 足攻め／技巧 | SUBMISSION＋PIN |
| 豪田ミサキ | 投げ＋打撃 | 高COST・高DMG・返されにくい | PIN |
| 黒蝶ジャック | ROUGH＋打撃 | コンボ制限／高HEAT | PIN |

---

## 18. ENERGY配分（検証値）

| レスラー | 打 | 関 | 投 | 飛 | ラフ | ＊ | 合計 |
|---|---|---|---|---|---|---|---|
| アカリ | 5 | 1 | 2 | 2 | 0 | 1 | 11 |
| レイナ | 2 | 4 | 3 | 0 | 0 | 1 | 10 |
| ミサキ | 3 | 0 | 4 | 0 | 1 | 1 | 9 |
| ジャック | 3 | 1 | 1 | 0 | 4 | 1 | 10 |

---

## 19. 豪田ミサキ TECHNIQUE（検証版）

高COST・高DMG型。新しいPOWERゲージなどは追加しない。高COST技ほど、DMGが高く、返し必要ENERGYも高いという
既存ルールだけで「返されにくいパワーファイター」を表現する。

例: COST1→DMG10、COST2→DMG20、COST3→DMG30、COST4→DMG40。

| 技 | 格 | COST | DMG | HEAT | 状態 | 特性 |
|---|---|---|---|---|---|---|
| 逆水平チョップ | NORMAL | 打1 | 10 | 10 | STAND→STAND | |
| ショルダータックル | NORMAL | 打1 | 10 | 20 | STAND→DOWN | |
| ボディスラム | NORMAL | 投1 | 10 | 10 | STAND→STAND | |
| ブレーンバスター | NORMAL | 投2 | 20 | 20 | STAND→DOWN | |
| バックドロップ | NORMAL | 投2 | 20 | 20 | STAND→DOWN | |
| パワースラム | NORMAL | 投3 | 30 | 30 | STAND→DOWN | |
| ラリアット | NORMAL | 打2 | 20 | 20 | STAND→DOWN | |
| ギロチンドロップ | NORMAL | 打1 | 10 | 20 | DOWN→DOWN | |
| 豪快バックドロップ | SIGNATURE | 投3 | 30 | 40 | STAND→DOWN | |
| 剛腕ラリアット | SIGNATURE | 打2 | 20 | 30 | STAND→DOWN | |
| 豪田ボム | FINISHER | 投3 | 30 | 40 | STAND→DOWN | DIRECT PIN |
| 豪田ドライバー | FINISHER | 投4 | 40 | 50 | STAND→DOWN | 最大火力（検証対象） |

「豪田ドライバー：投4／DMG40」が重要な検証対象。

---

## 20. 黒蝶ジャック ROUGH関連（検証版）

ROUGH＋打撃型。ROUGH TECHNIQUEは30枚中5枚程度を検証基準とする。

| 技 | 格 | 属性 | COST | DMG | HEAT | 採用枚数 |
|---|---|---|---|---|---|---|
| チョーク攻撃 | NORMAL | ROUGH | ラフ1 | 10 | 20 | ×1 |
| 顔面かきむしり | NORMAL | ROUGH | ラフ1 | 10 | 20 | ×1 |
| 黒蝶クラッシュ | SIGNATURE | ROUGH | ラフ2 | 20 | 40 | ×2 |
| 黒蝶ドライバー | FINISHER | ROUGH | ラフ3 | 30 | 50 | ×1 |
| ブラック・ジャック | FINISHER | STRIKE | 打3 | 30 | 50 | ×1 |

- ジャックのROUGH TECHNIQUEは30枚中5枚を初期基準とする。
- **踏みつけはROUGHではなく通常技として扱う。**
- 黒蝶ドライバー: 妨害型FINISHER。ブラック・ジャック: 決着型FINISHER、という役割分担。

---

## 21. 30枚デッキ配分（現時点、検証段階の暫定基準）

- アカリ: 基本NORMAL＝エルボースマッシュ×3、ミドルキック×3。その他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- レイナ: 基本NORMAL＝サイドヘッドロック×3、足四の字×3。ドラゴンスクリューを含むその他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- ミサキ: 基本NORMAL＝逆水平チョップ×3、ボディスラム×3。その他NORMALは原則×2。
  SIGNATURE各×2、FINISHER各×1、COUNTER各×2。
- ジャック: NORMAL18枚は個別配分。ROUGHはチョーク×1、顔面かきむしり×1、黒蝶クラッシュ×2、
  黒蝶ドライバー×1＝計5枚を基準（ジャックのSIGNATURE／FINISHER／COUNTERの内訳は一次資料に記載がなく、
  本書でも未確定のまま残す。推測補完はしない）。

Phase 1ではこの正式デッキ内容は使用せず、テスト用フィクスチャで代替する（Phase 10で正式データ化）。

---

## 22. アカリ・レイナの技データ（未確定）

アカリ・レイナの全12技（NORMAL8・SIGNATURE2・FINISHER2相当）の詳細数値（COST／DMG／HEAT／状態／特性）は、
**一次資料（docx）に記載がなく、本セッションでも未確定のまま**とする。17章の方向性、21章のデッキ配分の
一部（基本NORMAL名）のみが判明している。

**推測で技データを補完しない。** 後続Phase（Phase 10想定）でユーザーから仕様が追加された時点で本書へ反映する。

---

## 23. 技系統（TechniqueFamily）

将来COUNTERの成立判定で、攻撃TECHNIQUEの技系統とCOUNTERが返せる技系統を比較する想定。

例（イメージ、確定ではない）: バックドロップ系、スープレックス系、パワーボム系、ラリアット系、キック系、
関節系、飛び技系 など。

**正式taxonomyは未確定**。Phase 1では技モデル上に `familyId`（自由文字列、nullable）程度の暫定構造を
持たせるに留め、後から正式なTechniqueFamilyへ移行できるようにする（詳細は
[`combat_v1_phase1_design.md`](design/combat_v1_phase1_design.md) 参照）。

---

## 24. CPU検証ロジックの原則（将来Phase向け、参考情報）

Phase 11（CPU実装）以降で参照する原則。Phase 1では適用しない。

- 確定勝利（3カウント／GIVE UP）を最優先。
- PIN／SUBMISSION／追撃を、相手HP・KOC・PIN資源・追撃可能性から比較する。
- COUNTERは使用可能なら必ず使うのではなく、重要技へのENERGY温存も評価する。
- FINISHERはHEATが低い序盤では交換候補、HEAT100以降は使用可能性に応じて温存、HEAT200以上では
  高優先度保持とする。
- 1カウントの追加ドローは手札状況・FINISHER探索・COUNTER確保などの価値を評価して選択する。
- ROUGHは相手を弱らせる局面では妨害に使い、決着圏ではPIN不可のデメリットも考慮する。

---

## 25. 検証で記録する指標（将来Phase向け、参考情報）

Phase 12〜13（Simulator／バランス検証）以降で使用する想定の指標。Phase 1では扱わない。

- 勝率（先攻／後攻別）・決着方法・平均／中央値ターン
- PIN回数、1／2／2.9カウント回数、PINカード移動
- SUBMISSION／ESCAPE／GIVE UP回数
- HEAT200到達ターン、FINISHER使用・成功・決着率
- REST回数、山札再構築回数
- 各TECHNIQUEのドロー／使用／成功／被COUNTER／与DMG／勝利貢献
- COUNTERの使用可能回数・実使用回数・COST別成功率
- ミサキのCOST3/4技が実際に返されにくいか
- ジャックのROUGH締め回数と相手TECHNIQUE制限回数

---

## 26. 開発ロードマップ（Phase 0〜16）

依存関係を考慮した推奨実装順。各Phaseの詳細な技術設計は該当Phase着手時に
`docs/design/`配下へドキュメントを追加する。

| Phase | 内容 | 概要 |
|---|---|---|
| Phase 0 | 設計・SSOT確定 | 本書および`combat_v1_phase1_design.md`の確定（今回） |
| Phase 1 | Core Skeleton | Match生成〜ENERGY消費〜DMG適用〜HEAT加算〜手札循環の最小ループ。UI非依存でテスト可能な状態にする |
| Phase 2 | Deck / Hand | 30枚デッキの正式構成検証、手札循環の仕上げ |
| Phase 3 | ENERGY / TECHNIQUE | ENERGY・TECHNIQUE処理の本実装（Phase 1で土台は構築済み） |
| Phase 4 | COUNTER | 動的コスト（攻撃技コスト＝返し必要コスト）、技系統マッチング、＊ワイルドのCOUNTER時ポリシー確定 |
| Phase 5 | PIN / KOC | 1／2／2.9カウント階層、PINカード移動（最低1枚保証込み）、KOC消費処理 |
| Phase 6 | SUBMISSION | 通常SUBMISSION・SUBMISSION FINISHERの実装 |
| Phase 7 | DOWN / REST | 起き上がり／REST選択の実装 |
| Phase 8 | ROUGH | PIN不可・次ターンTECHNIQUE最大1枚制限の実装 |
| Phase 9 | FINISHER | `CombatV1FinisherType`に基づく3種の決着フローの実装 |
| **— Legacy Engine Removal Gate —** | | 27章の条件を満たした時点で旧3エンジンを削除（27章） |
| Phase 10 | 4 Wrestlers / Deck Data | アカリ・レイナの技データ確定、4レスラー全員の正式30枚デッキ実装 |
| Phase 11 | CPU | Combat Ver.1専用CPU実装 |
| Phase 12 | Simulator | Config／Simulator／Report／Diagnostics分離によるシミュレーション基盤（②の設計を参考） |
| Phase 13 | Balance Validation | 6組み合わせ×大量対戦によるバランス検証 |
| Phase 14 | UI | Combat Ver.1専用UI実装 |
| Phase 15 | Presentation / Animation / Audio | 演出・アニメーション・音声 |
| Phase 16 | Final Validation | 最終検証 |

---

## 27. Legacy Engine Removal Gate

**非常に重要**: 既存3エンジン（①Prototype／②Level Match／③Technique Match）は永久には残さない。
Combat Ver.1完成後、正式戦闘Engineを1つに統一する。

### 27.1 Gate通過条件

以下をすべて満たした時点で、旧エンジン削除Phaseへ進む。

1. Combat Ver.1の基本戦闘ルールが実装済みである。
2. COUNTER／PIN／KOC／SUBMISSION／REST／ROUGH／FINISHERが動作する。
3. 各ルールのテストが成功する。
4. UI非依存で、試合開始から決着まで1試合を最後まで実行できる。
5. 旧Engineから再利用したい資産の洗い出しが完了している。
6. 削除前の状態をGitで保存している。

### 27.2 削除対象（Gate通過後）

- ① Prototype、② Level Match、③ Technique Match
- 対象候補: 旧Engine本体、旧Engine専用UI、旧Engine専用CPU、旧Engine専用Simulator、旧Engine専用テスト、
  旧Engine専用保存処理、不要な旧データモデル、タイトル画面の旧モード導線

### 27.3 削除前に必ず評価する資産

Playtest Analytics、Simulatorの設計、Report、Diagnosticsなど、Ver.1へ再利用価値のある資産は
**削除前に必ず評価する**。必要なものをVer.1側へ移植してから削除する。**旧Engine互換レイヤーは作らない。**

---

## 28. 未決定事項

詳細は [`docs/design/combat_v1_open_questions.md`](design/combat_v1_open_questions.md) を参照。

---

## 29. 変更履歴

- **Phase 0（Combat Ver.1 Engine設計セッション）**: 本書を新規作成。一次資料（docx「ONE_NIGHT_MATCH_
  戦闘ルール_Ver.1_検証版」）の内容を全面的に統合したうえで、以下を追加確定した。
  - Combat Ver.1を独立エンジン（④）として構築する方針（1章）
  - HP初期値150を全レスラー共通固定とする（2章、14章）
  - KOC・PINカードをPhase 1の基本リソースとして扱う（9章、8章）
  - PINカード最低1枚保証ルールの正式採用（8.1章）
  - ＊（ワイルドENERGY）の解決手順（具体属性優先→不足分合算→＊で補完）の確定（5.1章）
  - Combo Speedを不採用とし、ENERGYで攻撃継続回数を制御する方針の確定（4章）
  - `CombatV1FinisherType`を独立enumとして定義し、技のSUBMISSIONフラグとは別概念とする方針（13章）
  - 開発ロードマップ（Phase 0〜16）とLegacy Engine Removal Gateの正式条件（26・27章）
