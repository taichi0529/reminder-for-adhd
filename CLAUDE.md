# CLAUDE.md

Reminder For ADHD — カレンダーの予定の時間に、画面の下 1/4 へ大きくパネルを出す macOS のメニューバーアプリ。Swift 6 / SwiftUI + AppKit、macOS 15 以上。アプリの画面と文言は日本語。

## コマンド

```sh
make generate  # project.yml から Reminder.xcodeproj を生成する (XcodeGen が必要: brew install xcodegen)
make build     # Debug ビルド
make test      # 単体テスト (Swift Testing)
make run       # Debug ビルドを起動する
make install   # Release ビルドを /Applications に入れて起動する
```

- `.xcodeproj` は生成物なので git に入れない。ファイルを足したり動かしたりしたら `make generate` (build / test が自動で行う)
- CI は `.github/workflows/test.yml`。プッシュとプルリクエストで、macOS 26 (Xcode 26) のランナーで `make test` を回す

## アーキテクチャ

ソースはクリーンアーキテクチャの層 (Domain・Application・Infrastructure・Presentation・App) に分かれている。**層ごとの責務・依存の向き・新しいコードの置き場所・値オブジェクトを作らないこと・テストの書き方は [.claude/rules/clean-architecture.md](.claude/rules/clean-architecture.md) に従う。** コードを書く前に読むこと。

## 決まり

- **バッテリー**: 定期的なポーリングはしない。次に表示が変わる時刻・OS からの変更通知・スリープ明けでだけ読み直す (README の「バッテリーへの配慮」)。タイマーを足すときは tolerance を付ける
- **設定のキー**: UserDefaults のキー (`alertLeadMinutes`・`enabledCalendarIDs`) は変えない。変えるとユーザーの設定が消える
- **バージョン**: 機能を足したら `project.yml` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を上げ、`RELEASE_NOTES.md` に書く
- **README**: 英語版 (`README.md`) と日本語版 (`README.ja.md`) の両方を同じ内容で直す
- **コミット**: 日本語で、1行目に何をしたか、空行のあとに `- ` で始まる箇条書き。最後に `Co-Authored-By` を付ける
- **署名**: 既定は ad-hoc。作り直すとカレンダーへのアクセス許可をまた求められることがある
