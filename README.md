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

- **GitHub Pages（本番・自動）**: `main` へのmerge/pushをトリガーに
  GitHub Actions workflow
  [`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml)
  （workflow名: **Deploy to GitHub Pages**）が自動実行される。
  `flutter pub get` → `flutter analyze` → `flutter test` →
  `flutter build web --release --base-href /one_night_match/ --no-web-resources-cdn`
  を通し、検証が全て成功した場合のみ `build/web` をGitHub Pages公式actions
  （`configure-pages` / `upload-pages-artifact` / `deploy-pages`）でdeployする。
  `workflow_dispatch` にも対応しており、Actionsタブから手動実行も可能。
  - 本番URL: https://perusonao.github.io/one_night_match/
  - deployが失敗した場合はGitHub Actionsの実行ログを確認する。
  - **前提（初回Actions deployment前に必ず確認する）**:
    1. `Settings → Pages → Build and deployment → Source` を
       `GitHub Actions` へ変更する。
    2. `Settings → Environments → github-pages → Deployment branches /
       Deployment branch policy` を確認する。**現状は `gh-pages` のみが
       許可されている想定**であり、このworkflowは `main` からdeployする
       ため、`main` からのdeploymentを明示的に許可しないとenvironment
       protectionによりdeployが拒否される。GitHub UIがSource切替時に
       policyを自動調整する可能性に依存せず、必ず自分の目で確認すること。
  - **`./deploy_web.sh` の位置づけ（Source切替後）**: このscriptは
    `gh-pages` ブランチへ直接pushするだけの、旧来の
    「Deploy from a branch」方式専用のlegacy scriptである。Pages Source
    を `GitHub Actions` へ切り替えた後は、`gh-pages` ブランチを更新しても
    **production Pagesには反映されない**（Actions Sourceの場合、Pagesは
    `deploy-pages` actionによるdeploymentのみで更新される）。したがって
    Source切替後は通常のproduction deployにこのscriptを使用しない。
    手動でproduction deployしたい場合はGitHub Actionsの
    `workflow_dispatch`（Actionsタブから該当workflowの
    "Run workflow"）を使う。`deploy_web.sh` を再びproduction反映に使う
    には、Pages SourceをBranch方式へ戻す必要があるが、通常運用では
    行わない。
  - **移行手順（初回のみ）**: 上記2点はrepository settingの変更が
    必要なため、Claude Codeでは実施せずここに手順として記録する。
    実施順序:
    1. Auto Deploy workflow（本節冒頭のworkflow）を `main` へmergeする。
    2. 現在のproduction（`gh-pages` ブランチ配信）が引き続き公開されて
       いることを確認する。
    3. `Settings → Pages → Build and deployment → Source` を
       `GitHub Actions` へ変更する。
    4. `Settings → Environments → github-pages` を確認する。
    5. `main` からのdeploymentを許可する（Deployment branch policyに
       `main` を追加、または対象を緩和する）。
    6. `Actions` → `Deploy to GitHub Pages` workflow → `Run workflow`
       で `workflow_dispatch` を実行する。
    7. workflow_dispatchが成功することを確認する。
    8. production URL（https://perusonao.github.io/one_night_match/）が
       正しく更新されていることを確認する。
    9. 以後は `main` へのmergeで自動deployされる。
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
