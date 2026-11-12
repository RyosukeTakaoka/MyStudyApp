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
  Models/                 データの型と、日付・時刻の計算
  Supabase/               Supabase との通信
  Sync/                   端末内の保存(SwiftData)と同期
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

## 次の版で作る予定のもの

- ホーム画面ウィジェット(「今 → 次」を表示)
- 予定の開始時刻のローカル通知
- 勉強時間の実績タイマーと、週ごとの集計
