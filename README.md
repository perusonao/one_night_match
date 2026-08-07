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
