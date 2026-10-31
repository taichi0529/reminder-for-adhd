# クリーンアーキテクチャ

`Reminder/` のソースは層に分かれている。新しいコードを書くとき、既存のコードを動かすときは、この決まりに従う。

## 層と依存の向き

依存は外側から内側への一方向だけ。内側の層は、外側の層の型を知らない。

```
App ──→ Presentation ──→ Application ──→ Domain
  └───→ Infrastructure ──┘
```

| 層 | ディレクトリ | 置くもの | import してよいもの |
|---|---|---|---|
| Domain | `Reminder/Domain` | 予定 (`CalendarEvent`)・カレンダー (`CalendarInfo`)・通知の判定 (`AlertPlanner` / `AlertState`)・カレンダーの選択 (`CalendarSelection`)・会議 URL の抽出・音声出力の状態 (`AudioStatus`)。純粋な型と計算だけ | `Foundation` だけ |
| Application | `Reminder/Application` | ユースケース (`ReminderService`) と、外とつなぐポート (`Ports/` の protocol) | `Foundation` だけ |
| Infrastructure | `Reminder/Infrastructure` | ポートの実装。EventKit・UserDefaults・CoreAudio・ServiceManagement など OS や外部サービスに触るもの | 何でもよい。Presentation の型は使わない |
| Presentation | `Reminder/Presentation` | `AppModel` (タイマー・App Nap・OS からの通知・画面の状態)・SwiftUI / AppKit の画面・表示用の文字列 (`EventFormatting`) | `AppKit`・`SwiftUI` など。Infrastructure の具体的な型は使わない |
| App | `Reminder/App` | エントリポイントと組み立て (`AppDelegate`)。Infrastructure の実装を作り、Presentation に渡す | 何でもよい。ここ以外で Infrastructure の具体的な型を作らない |

## どこに置くか

| 書きたいもの | 置き場所 |
|---|---|
| 予定やカレンダーについての、時刻を渡せば決まる計算 (並べ方・数え方・選び方) | Domain。`[CalendarEvent]` などへの extension か、`enum` の static 関数 |
| 「いつ・何を通知するか」「ボタンを押したら状態がどう変わるか」「設定をどう変えるか」 | Application の `ReminderService`。大きくなったら別のユースケースのクラスに分ける |
| OS・外部サービスから読む / 書く (カレンダー・設定の保存・音声・ネットワーク) | Application の `Ports/` に protocol を足し、Infrastructure で実装する |
| いつ判定し直すか (タイマー・スリープ明け・日付の変更) | Presentation の `AppModel` |
| 画面に出す文字列の組み立て | Presentation の `EventFormatting` |
| 実装の差し替え (EventKit の代わりに別の取得元など) | App の `AppDelegate` で組み立てを変える |

- 判定のロジックを `AppModel` や SwiftUI の View に書かない。`ReminderService` か Domain に置き、`AppModel` はその結果を画面の状態に写すだけにする
- 現在時刻は `Date()` をユースケースの中で呼ばず、引数 (`now:`) で受け取る。テストで時刻を決められるようにするため

## ポート

- `Reminder/Application/Ports/` に置く。`@MainActor` の `protocol ...: AnyObject` にする
- 引数と戻り値は Domain の型か標準の型だけにする。EventKit の `EKEvent` などを出さない
- 変化を知らせるときは `onChange` のようなクロージャか、実装側を `@Observable` にする (`AudioOutput` の `status`)

## 値オブジェクトは作らない

- ID は `String`、時間の長さは `Int` (分) や `TimeInterval`、色は `RGBColor` のまま扱う。`CalendarID` や `Minutes` のような包むだけの型を作らない
- `struct` にするのは、意味のまとまりがあるもの (`CalendarEvent`・`Alert`・`ReminderSnapshot` など) だけにする
- 設定は `SettingsStore` の個々のプロパティ (`Set<Int>`・`Set<String>`) として扱い、設定をまとめた型も作らない

## テスト

- テストのターゲット (`ReminderTests`) は、アプリを起動せずに Domain・Application・`Presentation/EventFormatting.swift` のソースを直接取り込む (`project.yml`)。ここに入るものは `Foundation` だけに依存させる
- ユースケースのテストでは、ポートの偽の実装 (`FakeCalendarSource`・`InMemorySettingsStore` など) をテストのファイルの中に書いて差す
- Domain や Application に処理を足したら、同じ変更の中でテストを足す。テストの名前は日本語で、何を確かめるかを書く (`@Test func 最後のタイミングは外せない()`)

## 確かめ方

変更のたびに、依存の向きが崩れていないかを確かめる。どれも何も出なければよい。

```sh
# Domain と Application は Foundation しか import しない
grep -rh '^import ' Reminder/Domain Reminder/Application | grep -v '^import Foundation$'

# Domain は外側の型を参照しない
grep -rnwE 'CalendarSource|SettingsStore|AudioOutput|ReminderService|AppModel' Reminder/Domain

# Application と Presentation は Infrastructure の具体的な型を参照しない
grep -rnE 'EventKitCalendarSource|AudioOutputMonitor|UserDefaultsSettingsStore|LoginItem' Reminder/Application Reminder/Presentation
```

そのうえで `make test` を通す。CI (`.github/workflows/test.yml`) も同じ `make test` を回す。
