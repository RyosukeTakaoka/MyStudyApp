# MyStudyApp

不動産鑑定士の勉強のための、自分専用の iPhone アプリです。
Claude(別のチャット)が立てた予定・週の計画・資料をアプリで見て、タップでチェックし、タイマーで勉強時間を記録します。

- 予定や資料は **Supabase(クラウドのデータベース)** に置いてあり、アプリはそれを読み書きするだけです。
  予定や資料を変えても、アプリの更新や審査はいりません
- 別のチャットの Claude が、コネクタ(MCP)でデータベースに予定・計画・資料を直接書きこみ、勉強の実績を読めます
- 電波がなくても表示・チェック・タイマー・編集ができ、つながったら自動で送ります

## はじめに読むもの

| ファイル | 内容 |
|---|---|
| [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | 自分の iPhone で動かすまでの手順と、機能ごとの使い方・困ったときの直し方 |
| [docs/FOR_CLAUDE.md](docs/FOR_CLAUDE.md) | 別のチャットの Claude が読む説明書(どのテーブルに何を書くか、SQL の見本、やってはいけないこと) |

## アプリでできること

### 「今日」タブ

- その日の目標・進み具合(例 4/9 完了)・予定(時刻順)・やること・ふりかえり
- いちばん上に「今 → 次」(今の時刻の予定と、次の予定)
- 予定を **タップでチェック**、**長押しでタイマー開始**。予定ごとに「手順と注意」を開ける
- 左右スワイプか矢印で日付を切りかえ。右上の 📅 で月のカレンダー(日ごとの達成率・科目別の勉強時間)
- 右上の **+** で予定を足す。予定を左へスワイプして **編集・明日へ・削除**(自分で入れた予定は、Claude の入れ直しで消えない)
- 勉強タイマー
  - **いくつでも同時に動かせる**(例: 夕食を食べながら Anki)
  - 一時停止・再開(止めたところから続く)、完了、記録して終了
  - 同じ予定をもう一度始めると、前回までの記録の続きから表示する
  - 自動タイマー: 予定の時間にアプリを開くと始まり、終了時刻で止まる
  - 始めた時刻・止めた時刻を区間ごとに記録する(Claude が読んで計画に生かす)
- 右上の **…** メニュー: 自動タイマー、開始時刻の通知、カレンダー連携、集中モード、ログアウト

### 「週・月」タブ

- 期間の計画(「そもそも終わる?」の数字と「月の流れ」)
- 週ごとのカード(ラベル・行事・やること・バッファ)。やることの箱(例 数学 1〜12)は **1つずつ押して緑** にできる

### 「資料」タブ

- Claude が書いた読み物(ルール・方針・答練の振り返りなど)を、分類ごと・ピン留め順に一覧。検索できる
- 本文は Markdown(見出し・太字・箇条書き・表・チェックなど)。□ は押してチェックできる
- 本文は Web ページのように **部分選択・全選択・コピー** ができる。右上のボタンで全文コピー

### アプリの外

- ホーム画面ウィジェット(小・中・大)とロック画面ウィジェット。中・大はその場でチェックできる
- タイマー中は、ロック画面とダイナミックアイランドに経過時間(ライブアクティビティ、タイマーごとに1つ)
- iPhone の純正カレンダー連携: 予定を「MyStudy」カレンダーに書き出し、学校や Google の予定をアプリに表示
- 集中モード: 勉強中はスクリーンタイムで、選んだアプリ(Anki など)以外を制限。予定の時間に自動・タイマー中・手動(25/50/90分)。
  どれも終わりの時刻が決まっていて、時間が来れば必ず外れる

## データベース(Supabase)

テーブルと、Claude が書きこむための関数は `supabase/migrations/` にあります。
**新しく作るときは、下の順番で SQL Editor に貼って実行します**(どれも1回だけ)。

| 順 | ファイル | 中身 |
|---|---|---|
| 1 | `20261112000000_create_days_and_items.sql` | 1日の情報(`days`)と予定(`items`)、RLS、チェック済みの行を消させない安全装置 |
| 2 | `20261113000000_claude_plan_functions.sql` | 予定の入れ直し・削除の関数(`replace_plan` / `remove_plan_items`) |
| 3 | `20261114000000_weekly_and_term_plans.sql` | 週・月の計画(`term_plans` / `weeks` / `week_goals`)と書きこみ用の関数 |
| 4 | `20261115000000_item_steps_and_open_end.sql` | 予定の手順と注意(`steps` / `cautions`)、終わりの時刻のない予定 |
| 5 | `20261116000000_study_sessions.sql` | タイマーの区間の記録(`study_sessions`) |
| 6 | `20261117000000_notes.sql` | 資料(`notes`)と書きこみ用の関数 |

どのテーブルも RLS(行レベルセキュリティ)で、ログインした本人の行しか読み書きできません。

## データの流れ

```
                     書く: 予定・目標・週と月の計画・資料
Claude(別のチャット) ────────────────────────────▶ Supabase
                     ◀──────────────────────────── 
                     読む: チェック・実績(タイマーの記録)・ふりかえり
                                                      ▲
                                                      │ 同期(アプリを開いたとき・押したとき・電波が戻ったとき)
                                                      ▼
                          iPhone の中の保存場所(SwiftData・ファイル) ◀──▶ 画面・ウィジェット
```

## TestFlight へのアップロード

```bash
cd ~/Desktop/MyStudyApp
./scripts/release.sh
```

最新のコードの取りこみ → ビルド番号を決める(日時から自動) → Archive → App Store Connect へのアップロード、までを行います。
はじめに次の2つの設定ファイルが必要です(どちらも Git には入りません)。

| ファイル | 書くこと |
|---|---|
| `Config/Secrets.xcconfig`(見本: `Secrets.example.xcconfig`) | `SUPABASE_HOST`・`SUPABASE_KEY`(Publishable key)・`DEVELOPMENT_TEAM`(チーム ID) |
| `scripts/asc-api-key.env`(見本: `asc-api-key.example.env`) | App Store Connect の API キー(`ASC_KEY_ID`・`ASC_ISSUER_ID`・`ASC_KEY_PATH`) |

## 使っている技術

| 役割 | 技術 |
|---|---|
| アプリ | Swift + SwiftUI(iOS 17 以上、Xcode 16 以上) |
| データベース・ログイン | Supabase(Postgres + Row Level Security)、Sign in with Apple |
| 通信ライブラリ | [supabase-swift](https://github.com/supabase/supabase-swift)(Swift Package Manager) |
| オフライン用の保存 | SwiftData(予定)、JSON ファイル(週・月の計画、資料、未送信の編集とタイマーの記録) |
| ウィジェット・ライブアクティビティ | WidgetKit、ActivityKit、App Intents(App Group でアプリとデータを共有) |
| 集中モード | FamilyControls、ManagedSettings、DeviceActivity(Family Controls (Distribution) の許可あり) |
| カレンダー・通知 | EventKit、UserNotifications |
| 配布 | TestFlight の内部テスト(`scripts/release.sh`) |

## フォルダの中身

```
MyStudyApp.xcodeproj/   Xcode のプロジェクト(アプリ・ウィジェット・集中モード監視の3つのターゲット)
MyStudyApp/             アプリのコード
  App/                    入口・設定の読みこみ・画面とタブの切りかえ
  Auth/                   ログイン(Sign in with Apple)
  Day/                    「今日」タブ(今→次、予定、タイマーのカード、ふりかえり、予定の編集)
  Plans/                  「週・月」タブ(週次・期間の計画)
  Notes/                  「資料」タブ(Markdown の読み物、選んでコピーできる表示)
  Calendar/               月のカレンダー画面
  Timer/                  勉強タイマー(複数)・タイマーの記録・ライブアクティビティ
  ScreenTime/             集中モードの操作と設定画面
  Features/               通知・ウィジェットへの受け渡し・純正カレンダー連携・設定
  Supabase/               Supabase との通信
  Sync/                   端末内の保存(SwiftData)、同期、未送信の編集
Shared/                 アプリとウィジェットの両方で使うコード(データの型・日付計算など)
MyStudyWidget/          ウィジェットとライブアクティビティの表示
Focus/                  集中モードの時間の決まりと、制限のかけ外し(アプリと監視の拡張機能で共有)
FocusMonitor/           アプリを閉じていても、集中モードの時間に制限をかけ外しする拡張機能
Config/                 ビルド設定・Info.plist・権限(entitlements)。Secrets.xcconfig は Git に入らない
scripts/                TestFlight へのアップロード(release.sh)
supabase/migrations/    テーブル・RLS・関数の SQL
docs/                   手順書と Claude 向け説明書
```

`MyStudyApp/`・`Shared/`・`MyStudyWidget/`・`Focus/`・`FocusMonitor/` のフォルダは Xcode と自動で同期されます。
フォルダに Swift ファイルを足すと、Xcode のプロジェクトにも自動で入ります。
