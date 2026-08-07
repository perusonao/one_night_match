# one_night_match

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Technique Match Development

Technique Matchの開発状況・次に何をすべきかは、以下のドキュメントを
入口として参照する（詳細な仕様はここではなく各ドキュメントに記載する）。

- **開発TODO / 次のアクション**:
  [`docs/design/technique_match_todo.md`](docs/design/technique_match_todo.md)
  — 新しいセッションはまずここを確認する
- **現行ルール**:
  [`docs/rules/technique_deck_rules.md`](docs/rules/technique_deck_rules.md)
- **未決定事項**:
  [`docs/design/technique_deck_open_questions.md`](docs/design/technique_deck_open_questions.md)
- **技データ（設計・レビュー用Excel）**:
  [`docs/data/one_night_match_techniques.xlsx`](docs/data/one_night_match_techniques.xlsx)
- **ルール変更履歴**:
  [`docs/history/technique_deck_rule_history.md`](docs/history/technique_deck_rule_history.md)

## Web deploy

- **GitHub Pages（本番）**: `./deploy_web.sh` — `flutter build web --release`
  してから `gh-pages` ブランチへpushする。
- **Firebase Hosting（Preview、Playtest Analytics検証用）**: このリポジトリ管理下の
  `firebase.json` / `.firebaserc`（プロジェクト: `one-night-match-preview`、
  Hostingのみ。Firestore/Authentication/Security Rulesは未設定＝Phase B以降）
  を使い、**live（本番）チャンネルではなくPreviewチャンネル**へデプロイする。

  ```sh
  flutter build web --release
  firebase hosting:channel:deploy <channel-name> --project one-night-match-preview
  ```

  認証はFirebase CIトークン（`firebase login:ci`。値はリポジトリ・コードへは
  一切保存しない）または`GOOGLE_APPLICATION_CREDENTIALS`のサービスアカウント
  キーを使う。`firebase deploy`（引数なし）や`hosting:channel:deploy live`は
  本番チャンネルを書き換えるため、無断では実行しない。

  【重要】Firestore構造を追加・変更する場合は、`firestore.rules`と
  Rulesのテストを必ず同じ変更セットで追加すること（Firestore未導入の
  現時点では該当なし）。
