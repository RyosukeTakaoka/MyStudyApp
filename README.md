# MyStudyApp

Claude と一緒に作った「毎日の予定・タスク」を表示して、タップでチェックする、自分専用の iPhone アプリです。

- 予定は **Supabase(クラウドのデータベース)** に置いてあり、アプリはそれを読み書きするだけです。
  予定を変えても、アプリの更新や審査はいりません
- 別のチャットの Claude が、SQL でデータベースに翌日の予定を直接書きこめます
- 電波がなくても表示とチェックができ、つながったら自動で同期します

## はじめに読むもの

| ファイル | 内容 |
|---|---|
| [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | **自分の iPhone で動かすまでの手順**(ステップ1〜7) |
| [docs/FOR_CLAUDE.md](docs/FOR_CLAUDE.md) | 別の Claude が予定を書きこむときの説明書 |

## 使っている技術

| 役割 | 技術 |
|---|---|
| アプリ | Swift + SwiftUI(iOS 17 以上) |
| データベース・ログイン | Supabase(Postgres + Row Level Security)、Sign in with Apple |
| 通信ライブラリ | [supabase-swift](https://github.com/supabase/supabase-swift)(Swift Package Manager) |
| オフライン用の保存 | SwiftData |
| 配布 | TestFlight の内部テスト |

## フォルダの中身

```
MyStudyApp.xcodeproj/   Xcode のプロジェクト(これをダブルクリックして開く)
MyStudyApp/             アプリのコード
  App/                    入口・設定の読みこみ・画面の切りかえ
  Auth/                   ログイン(Sign in with Apple)
  Day/                    メイン画面(今→次、目標、予定、ふりかえり)と、その状態
  Supabase/               Supabase との通信
  Sync/                   端末内の保存(SwiftData)と同期
  Timer/                  勉強タイマーとライブアクティビティ
  Calendar/               カレンダー画面
  ScreenTime/             集中モードの操作と設定画面
  Plans/                  「週・月」タブ(週次・期間の計画)
  Features/               通知・ウィジェットへの受け渡し・設定
Shared/                 アプリとウィジェットの両方で使うコード(データの型・日付計算など)
MyStudyWidget/          ウィジェットとライブアクティビティの表示
Focus/                  集中モード(スクリーンタイム)の時間の決まりと制限のかけ外し
FocusMonitor/           集中モードの時間にアプリを閉じていても制限をかけ外しする拡張機能
Config/                 ビルド設定。Secrets.xcconfig(秘密の値)は Git に入らない
supabase/migrations/    テーブル作成と RLS の SQL
docs/                   手順書と Claude 向け説明書
```

`MyStudyApp/` フォルダは Xcode と自動で同期されます。
このフォルダに Swift ファイルを足すと、Xcode のプロジェクトにも自動で入ります。

## データの流れ

```
Claude(別のチャット) ──SQL──▶ Supabase ◀──同期──▶ iPhone の中の保存場所 ◀──▶ 画面
```

## バージョン 1.1 で追加した機能

- ホーム画面ウィジェット(小・中・大)とロック画面ウィジェット。中・大はその場でチェックできる
- 勉強タイマーと自動タイマー(実績時間を記録)、ライブアクティビティ
- 予定の開始時刻の通知
- 月のカレンダー(日ごとの達成率と、科目別の勉強時間)
- iPhone の純正カレンダー連携(予定ブロックを「MyStudy」カレンダーに書き出し、ほかの予定をアプリに表示。Google カレンダーも iOS のアカウント経由で表示)
- 予定の行を長押しすると、すぐタイマー開始
- 「週・月」タブ: 期間の計画(そもそも終わる?・月の流れ)と週ごとの計画。やることの箱は1つずつ押して緑にできる
- 集中モード: 勉強中はスクリーンタイムで Anki など選んだアプリ以外を制限(予定の時間に自動、タイマー中、手動)
