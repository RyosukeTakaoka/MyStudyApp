# セットアップガイド(あなたがやること)

このアプリを自分の iPhone で動かすまでの手順を、ステップごとにまとめています。
上から順番に進めてください。

| ステップ | やること | 場所 |
|---|---|---|
| 1 | Supabase プロジェクトとテーブルを作る | Supabase |
| 2 | Xcode でプロジェクトを開いて動かす | Mac |
| 3 | ログイン(Sign in with Apple) | Supabase・Xcode・iPhone |
| 4 | 今日の画面(読み込み・チェック・保存) | Supabase・iPhone |
| 5 | 日付の切り替え・「今 → 次」・ふりかえり | iPhone |
| 6 | オフラインキャッシュと同期 | iPhone |
| 7 | TestFlight(内部テスト)で iPhone に入れる | App Store Connect・Xcode |
| 1.1 | ウィジェット・ライブアクティビティ・自動タイマー・カレンダー | Xcode・iPhone |
| 集中モード | スクリーンタイムで Anki 以外を制限 | Xcode・iPhone |
| 困ったら | Xcode でエラーが出たとき | Xcode |
| おまけ | Claude から予定を書きこめるようにする | claude.ai |

必要なもの: Mac(Xcode 16 以上)、Apple Developer アカウント、iPhone(iOS 17 以上)

---

## ステップ1: Supabase プロジェクトとテーブルを作る

1. ブラウザで <https://supabase.com> を開き、「Start your project」からアカウントを作る
   (GitHub アカウントでログインするのが簡単です)
2. 「New project」を押して、次のように入力する
   - **Project name**: `MyStudyApp`
   - **Database Password**: 「Generate a password」で作り、**必ずメモ**する
   - **Region**: `Northeast Asia (Tokyo)`
3. 「Create new project」を押して、1〜2分待つ
4. このリポジトリの `supabase/migrations/20261112000000_create_days_and_items.sql` を開き、中身を全部コピーする
5. Supabase の左メニュー **SQL Editor** を開き、貼り付けて **Run** を押す
   - 「Success. No rows returned」と出れば成功
6. 左メニュー **Table Editor** で、`days` と `items` の2つのテーブルができていることを確認する

> SQL は1回だけ実行します。2回実行すると「already exists」というエラーになりますが、壊れはしません。

---

## ステップ2: Xcode でプロジェクトを開いて動かす

### 2-1. Mac にコードを持ってくる

「ターミナル」アプリを開いて、次の3行を1行ずつ実行します。

```bash
cd ~/Documents
git clone https://github.com/RyosukeTakaoka/MyStudyApp.git
cd MyStudyApp && git checkout claude/exam-schedule-ios-app-wbcq5h
```

### 2-2. 秘密の設定ファイルを作る

1. 続けてターミナルで、見本をコピーして `Secrets.xcconfig` を作る

   ```bash
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```

2. Supabase の画面で、接続先とキーを調べる
   - 画面上部の **Connect** ボタン、または左下の歯車 **Project Settings → API Keys** を開く
   - **Project URL**(`https://xxxxxxxx.supabase.co` の形)
   - **Publishable key**(`sb_publishable_` で始まる文字)
3. `Config/Secrets.xcconfig` を開いて(次の 2-3 で Xcode を開いたあと、左の一覧から選ぶと編集できます)、2つの値を書き換える

   ```
   SUPABASE_HOST = xxxxxxxx.supabase.co
   SUPABASE_KEY = sb_publishable_xxxxxxxxxxxxxxxx
   ```

   - **`SUPABASE_HOST` には `https://` を付けません。** このファイルの形式では `//` から後ろがコメント扱いになり、URL が切れてしまうためです
   - **「Secret key」や「service_role」と書かれたキーは絶対に使いません。** RLS を無視して何でもできる強いカギだからです。アプリに入れるのは Publishable key だけです

> `Secrets.xcconfig` は `.gitignore` に入っているので、GitHub には送られません。

### 2-3. Xcode で開く

1. Finder で `MyStudyApp` フォルダの中の **`MyStudyApp.xcodeproj`** をダブルクリックする
2. 初回は、Xcode が自動で `supabase-swift` というライブラリをダウンロードします。
   左の一覧のいちばん下に「Package Dependencies」が出て、ダウンロードが終わるまで数分待ちます
   - 「Trust & Enable」のような確認が出たら、許可してください
3. 左上の青いアイコン **MyStudyApp**(いちばん上)をクリック → 中央の **TARGETS → MyStudyApp** → 上のタブ **Signing & Capabilities** を開く
4. **Team** で自分の Apple Developer のチームを選ぶ
5. **Bundle Identifier** を確認する。最初は `com.ryosuketakaoka.MyStudyApp` になっています
   - 世界で1つだけの名前である必要があります。エラーが出たら、`Config/Config.xcconfig` の `APP_BUNDLE_ID` を `com.自分の名前.MyStudyApp` のように変えてください(Xcode の画面の欄では変えないでください。ウィジェットと合わなくなります)
   - **ここで決めた文字は、ステップ3で Supabase にも入力します**

### 2-4. シミュレータで動かす

1. Xcode の上部中央で、実行先を **iPhone 16** などのシミュレータにする
2. 左上の **▶(Run)** を押す(ショートカットは `⌘R`)
3. シミュレータが起動して、緑のチェックと「Supabase につながりました」が出れば成功です
   - 「(未ログインなのでデータは読めません。これで正常です)」と出ます。RLS が働いている証拠です

### うまくいかないとき

| 画面・エラー | 原因 | 直し方 |
|---|---|---|
| 「Supabase の設定が必要です」と出る | `Secrets.xcconfig` が無い、または値が見本のまま | 2-2 をやり直す。`https://` を付けていないかも確認 |
| 「つながりませんでした」と出る | `SUPABASE_HOST` のつづりちがい、または Mac がオフライン | Supabase の Project URL と見比べる |
| `Missing package product 'Supabase'` | ライブラリのダウンロードが終わっていない・失敗した | メニュー **File → Packages → Reset Package Caches** |
| `Signing for "MyStudyApp" requires a development team` | Team が未選択 | 2-3 の手順4 |
| 左の一覧で `Secrets.xcconfig` が赤い | まだファイルを作っていない | 2-2 の手順1。作れば黒くなります |

---

## ステップ3: ログイン(Sign in with Apple)

ログイン方法は **Sign in with Apple** にしました。ボタンを1回押すだけでログインでき、
メールのリンクからアプリに戻る設定(マジックリンクで必要)がいらないためです。

### 3-1. Supabase で Apple ログインを有効にする

1. Supabase の左メニュー **Authentication** を開く
2. **Sign In / Providers**(または **Providers**)を開き、一覧から **Apple** を選ぶ
3. **Enable Sign in with Apple** をオンにする
4. **Client IDs** の欄に、ステップ2で確認した **Bundle Identifier** を入力する
   (変えていなければ `com.ryosuketakaoka.MyStudyApp`)
5. ほかの欄(Secret Key など)は**空のまま**で、**Save** を押す
   - Secret Key は Web サイトからログインするときだけ必要なものです。iPhone アプリだけなら不要です

### 3-2. Xcode で確認する

1. ステップ2と同じ **Signing & Capabilities** タブを開く
2. 一覧に **Sign in with Apple** が表示されていることを確認する(このリポジトリで設定済みです)
   - 赤いエラーが出ている場合は、Team が選ばれているか確認してください

### 3-3. 動かしてログインする

ログインの確認は、**自分の iPhone をつないで行うのがおすすめ**です(シミュレータは Apple のログインが不安定なことがあります)。

1. iPhone を USB ケーブルで Mac につなぐ
2. 初めての場合、iPhone で **設定 → プライバシーとセキュリティ → デベロッパモード** をオンにして再起動する
3. Xcode の上部中央で、実行先を自分の iPhone にして **▶** を押す
4. アプリが開いたら **「Apple でサインイン」** を押して、Face ID などで認証する
   - 「メールを非公開」を選んでも問題ありません
5. 「ログインできました」と **user_id**(英数字とハイフンの長い文字)が表示されれば成功です

Supabase の **Authentication → Users** を開くと、自分が1人だけ登録されているのが見えます。
この行の **UID** が、Claude が予定を書き込むときに使う `user_id` です(`docs/FOR_CLAUDE.md` 参照)。

### うまくいかないとき

| 画面・エラー | 原因 | 直し方 |
|---|---|---|
| 「Supabase へのログインに失敗しました」 | Supabase の Client IDs と、Xcode の Bundle Identifier がちがう | 両方を見比べて、1文字もちがわないようにする |
| 同上で `Unacceptable audience in id_token` と出る | 上と同じ原因 | 上と同じ |
| 同上で `Provider (issuer "https://appleid.apple.com") is not enabled` | Supabase で Apple がオフ | 3-1 の手順3 |
| Apple の画面が出ずにエラーになる(シミュレータ) | シミュレータが Apple アカウントにログインしていない | シミュレータの「設定」で Apple アカウントにサインインするか、実機で試す |
| `Provisioning profile ... doesn't include the com.apple.developer.applesignin entitlement` | 署名の情報が古い | Signing & Capabilities で Team を選び直す。直らなければ **Product → Clean Build Folder** のあと再実行 |

---

## ステップ4: 今日の画面(読み込み・チェック・保存)

### 4-1. テスト用の予定を入れる

まだ予定が1件もないので、まず今日の分のサンプルを入れます。
Supabase の **SQL Editor** に下の SQL を貼り付けて **Run** を押してください
(`user_id` と今日の日付は自動で入るので、書き換える所はありません)。

```sql
-- 今日の目標
insert into days (user_id, date, goal)
select u.id, (now() at time zone 'Asia/Tokyo')::date, 'アプリの動作確認をする'
from (select id from auth.users order by created_at limit 1) as u
on conflict (user_id, date) do update set goal = excluded.goal;

-- 今日の予定とやること
insert into items (user_id, date, kind, start_time, end_time, title, subject, sort_order)
select u.id, (now() at time zone 'Asia/Tokyo')::date, v.kind, v.start_time::time, v.end_time::time, v.title, v.subject, v.sort_order
from (select id from auth.users order by created_at limit 1) as u,
     (values
        ('block', '07:00', '07:30', 'Anki 鑑定評価基準',     '鑑定理論', 10),
        ('block', '16:30', '17:30', '民法 物権 過去問 10問', '民法',     20),
        ('block', '19:00', '20:30', '経済 ミクロ 演習',      '経済',     30),
        ('task',  null,    null,    '英語の宿題を提出する',  '学校',     40)
     ) as v(kind, start_time, end_time, title, subject, sort_order);
```

> この SQL はテスト用です。ふだんの予定は、Claude が `docs/FOR_CLAUDE.md` の手順で入れます。

### 4-2. 動かして確認する

1. Xcode で **▶** を押してアプリを実行する
2. 「今日の目標」「0/4 完了」「予定」「やること」が表示されることを確認する
3. 行をタップして ✓ が付き、「1/4 完了」に変わることを確認する
4. Supabase の **Table Editor → items** を開き、タップした行の `done` が `true`、`done_at` に日時が入っていることを確認する
5. 画面を下に引っぱる(プル・トゥ・リフレッシュ)と、最新の状態を読み直します

### うまくいかないとき

| 画面・エラー | 原因 | 直し方 |
|---|---|---|
| 「予定がありません」のまま | サンプルを入れる前にログインしていなかった(`auth.users` が空だった) | ステップ3でログインしてから、4-1 の SQL をもう一度実行する |
| `permission denied for table items` | ステップ1の SQL の後半(GRANT と RLS)が実行されていない | ステップ1の SQL ファイルの「4. 権限と RLS」の部分だけを SQL Editor で実行する |
| `Could not find the table 'public.items' in the schema cache` | テーブルがまだ無い | ステップ1の手順4〜6をやり直す |

---

## ステップ5: 日付の切り替え・「今 → 次」・ふりかえり

このステップは、Supabase や Xcode の設定変更はありません。動かして確認するだけです。

1. Xcode で **▶** を押してアプリを実行する
2. **「今 → 次」**: 画面のいちばん上に、今の時刻に当たる予定と、その次の予定が大きく出ることを確認する
   - 今の時刻に当たる予定がなければ「予定なし」と出ます
   - 時刻が進むと、1分ごとに自動で切りかわります
3. **日付の切り替え**: 上のバーの `<` `>` を押す、または画面を左右にスワイプして、前日・翌日に移れることを確認する
   - まん中の日付をタップすると、今日に戻ります
   - 「今 → 次」は、今日を表示しているときだけ出ます
4. **ふりかえり**: いちばん下の入力欄に文章を書き、**保存** を押す
   - Supabase の **Table Editor → days** を開き、今日の行の `reflection` に入っていることを確認する
   - `goal`(目標)が消えていないことも確認する
   - 保存を押さずに日付を変えたりアプリを閉じたりしても、自動で保存されます

### 明日の予定を入れて試す

`docs/FOR_CLAUDE.md` の「入れ直し用 SQL」を使って明日の予定を入れ、アプリで `>` を押して表示されるか試してみてください。

---

## ステップ6: オフラインキャッシュと同期

このステップも、設定の変更はありません。**実機の iPhone で**動かして確認します。

### しくみ(かんたんに)

```
画面 ⇄ iPhone の中の保存場所(SwiftData) ⇄ Supabase(クラウド)
```

- 画面は、いつも iPhone の中の保存場所を読み書きします。だから電波がなくても表示・チェックができます
- チェックやふりかえりは、まず iPhone の中に「未送信」の印を付けて保存されます
- 電波があるとき(アプリを開いたとき・下に引っぱったとき・電波が戻ったとき)に、未送信の変更をサーバーへ送り、サーバーの最新を取りこみます
- 表示している日の **前日〜7日後** までをまとめて取りこむので、オフラインでも明日以降の予定が見られます

### 確認のしかた

1. Xcode で **▶** を押して、iPhone でアプリを実行する(予定が表示されるまで待つ)
2. iPhone を **機内モード** にする(Wi-Fi もオフにする)
3. アプリを一度完全に終了して、開き直す → **予定が表示される**ことを確認する
   - 上に「オフラインです。…」というお知らせが出ます
4. 行をタップしてチェックを付ける → ✓ が付き、「1 件の変更は端末に保存してあり…」と出ることを確認する
5. 機内モードを **オフ** にする → 数秒でお知らせが消える
6. Supabase の **Table Editor → items** で、チェックした行の `done` が `true` になっていることを確認する

### Claude が書きこんだ予定がすぐ出るかの確認

1. アプリを開いたまま、Supabase の SQL Editor で `docs/FOR_CLAUDE.md` の「予定を1件だけ追加したいとき」の SQL を実行する
2. アプリの画面を下に引っぱる → 追加した予定が出ることを確認する
3. アプリをホーム画面に戻してから開き直しても、自動で最新になります

### 知っておくとよいこと

- **ログアウトすると、iPhone の中の保存データは消えます。** 未送信の変更があるときは、ログアウトの確認画面に件数が出ます
- 予定の内容(タイトルや時刻)は、いつもサーバー側が正しいものとして上書きされます。iPhone 側が優先されるのは「未送信のチェック」と「未送信のふりかえり」だけです

---

## ステップ7: TestFlight(内部テスト)で iPhone に入れる

Xcode から直接入れたアプリは、数日〜1年で使えなくなったり、Mac につなぎ直す必要があったりします。
**TestFlight の「内部テスト」**を使うと、App Store の審査なしで、自分の iPhone にふつうのアプリのように入れられます。

### 7-1. App Store Connect にアプリの「箱」を作る(最初の1回だけ)

1. ブラウザで <https://appstoreconnect.apple.com> を開き、Apple Developer のアカウントでサインインする
2. **アプリ(Apps)** を開き、左上の **＋ → 新規アプリ(New App)** を押す
3. 次のように入力して **作成** を押す
   - **プラットフォーム**: iOS
   - **名前**: `MyStudy 予定` など(App Store 全体でほかの人と重ならない名前が必要です。重なったら少し変えてください。公開はしないので、何でもかまいません)
   - **プライマリ言語**: 日本語
   - **バンドル ID**: ステップ2で決めた Bundle Identifier を選ぶ
     - 一覧に出てこないときは、先に Xcode で一度実機に実行してください(Xcode が自動で登録します)
   - **SKU**: `mystudyapp001` など(自分用の管理番号。何でもよい)
   - **ユーザアクセス**: アクセス制限なし

### 7-2. Xcode からアップロードする

1. Xcode の上部中央の実行先を **Any iOS Device (arm64)** にする(シミュレータのままだと、次のメニューが押せません)
2. メニュー **Product → Archive** を選ぶ(ビルドに数分かかります)
3. 終わると **Organizer** という画面が開き、今作ったアーカイブが選ばれている
4. 右の **Distribute App** を押す
5. **TestFlight Internal Only** を選んで **Distribute** を押す
   - 「TestFlight Internal Only」は、内部テスト専用でアップロードする方法です。まちがって App Store に公開されることがありません
6. 「Upload Successful」のような表示が出るまで待つ

### 7-3. 内部テスターに自分を追加する(最初の1回だけ)

1. App Store Connect で作ったアプリを開き、上のタブ **TestFlight** を開く
2. アップロードしたビルドが「処理中」と表示される。**5〜30分ほど**待つと、処理が終わる(メールでも通知が来ます)
3. 左メニュー **内部テスト(Internal Testing)** の横の **＋** を押し、グループを作る(名前は `自分` など)
   - 「自動配信を有効にする」にチェックを入れておくと、次からはアップロードするだけで届きます
4. 作ったグループを開き、**テスター** の **＋** から自分を追加する
5. **ビルド** の **＋** から、アップロードしたビルドを追加する

### 7-4. iPhone に入れる

1. iPhone の App Store で **TestFlight** アプリをインストールする
2. TestFlight を開き、Apple Developer と同じ Apple アカウントでサインインする
3. アプリが一覧に出るので、**インストール** を押す
4. ホーム画面にアイコンができたら完成です。開いて「Apple でサインイン」してください

### 知っておくとよいこと

- **予定を変えるだけなら、アップロードは不要です。** 予定は Supabase のデータなので、Claude が書きこめばアプリにすぐ出ます。これが、このアプリのいちばん大事な設計です
- **アップロードが必要なのは、次の2つのときだけです**
  1. アプリの機能(コード)を変えたとき
  2. **90日の期限が近づいたとき。** TestFlight のビルドは、アップロードから **90日** で使えなくなります。期限の前に、もう一度 7-2 をやってください(TestFlight アプリに残り日数が出ます)
- **2回目からのアップロードでは、ビルド番号を増やします。** `Config/Config.xcconfig` の `CURRENT_PROJECT_VERSION` を `2`、`3`…と増やします。同じ番号だとアップロードで断られます
- **Supabase の無料プランは、1週間まったく使わないとプロジェクトが一時停止します。** 毎日アプリを開いていれば止まりません。止まった場合は、Supabase の画面で「Restore」を押すと戻ります

### うまくいかないとき

| 画面・エラー | 原因 | 直し方 |
|---|---|---|
| **Product → Archive** が灰色で押せない | 実行先がシミュレータになっている | 7-2 の手順1 |
| `No profiles for '...' were found` | 署名の設定ができていない | Signing & Capabilities で Team を選び、「Automatically manage signing」にチェック |
| `The bundle version must be higher than the previously uploaded version` | ビルド番号が前と同じ | Build の数字を1つ増やす |
| `Missing required icon file` | アイコン画像が無い | `MyStudyApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` が消えていないか確認 |
| TestFlight アプリに何も出ない | テスターに追加されていない、またはビルドが処理中 | 7-3 を確認。Apple アカウントが同じかも確認 |

---

## バージョン 1.1: ウィジェット・ライブアクティビティ・自動タイマー・カレンダー

### 追加された機能

| 機能 | 内容 |
|---|---|
| ホーム画面ウィジェット(小・中・大) | 小: 今 → 次 / 中: 今 → 次 + 残りの予定 / 大: 目標・進み具合・予定の一覧。**中と大は、ウィジェットのままチェックできます** |
| ロック画面ウィジェット(丸・長方形・1行) | 丸: 進み具合のメーター / 長方形: 今の予定と残り時間・次の予定 / 1行: 今の予定 |
| 勉強タイマー | 「今 → 次」の **タイマー開始**、または予定を **長押し → タイマーを開始**。止めると実績時間(actual_minutes)が記録されます |
| 自動タイマー | 予定の時間にアプリを開くと、自動でタイマーが始まり、終了時刻で自動で止まって記録されます(右上の … メニューでオン・オフ) |
| ライブアクティビティ | タイマー中は、ロック画面とダイナミックアイランドに経過時間と進み具合が出ます |
| 開始時刻の通知 | 予定の開始時刻に通知します(… メニューでオン。初回は許可を求められます) |
| カレンダー | 右上の 📅 から。日ごとの達成率と、月の科目別の勉強時間を表示。日付を押すとその日に移動します |

### あなたがやること

1. **Bundle Identifier を変えていた人だけ:** Xcode で変えた値をメモしておく
2. ターミナルで最新のコードを取りこむ

   ```bash
   cd ~/Documents/MyStudyApp
   git checkout -- MyStudyApp.xcodeproj
   git pull
   ```

   - 1行目は、Xcode が自動で書きかえたプロジェクトファイルを元に戻すためです(`Secrets.xcconfig` は消えません)
3. 手順1でメモした人は、`Config/Config.xcconfig` の `APP_BUNDLE_ID = ...` をその値に書きかえる
   (Bundle ID はここで管理するようにしました。ウィジェットと App Group も自動で合わせて変わります)
4. Supabase の **SQL Editor** で、`supabase/migrations/20261113000000_claude_plan_functions.sql` の中身を貼って **Run**
   - チャットの Claude が予定を入れ直したり消したりできるようになります(`docs/FOR_CLAUDE.md` も更新済み)
5. Xcode でプロジェクトを開き、左上の青い **MyStudyApp** → **TARGETS** で、次の2つそれぞれについて **Signing & Capabilities** を開く
   - **MyStudyApp**(アプリ)
   - **MyStudyWidgetExtension**(ウィジェット。今回増えました)

   それぞれで:
   - **Team** を選ぶ
   - **App Groups** の欄に `group.(あなたのBundle ID)` が表示され、チェックが入っていることを確認する。赤い文字やチェックなしなら、チェックを入れる/右の 🔄 を押す
6. **▶** で iPhone に入れる
7. ホーム画面を長押し → 左上の **+** → **MyStudy** を探して、好きな大きさのウィジェットを追加する
   - ロック画面は、ロック画面を長押し → **カスタマイズ** → **ロック画面** → 時計の下の枠から追加
8. TestFlight に上げるときは、今回からバージョンが **1.1** になります。2回目以降は `Config/Config.xcconfig` の `CURRENT_PROJECT_VERSION` を 2、3…と増やしてください(Xcode の General タブではなく、こちらを書きかえます)

### 知っておくとよいこと

- **ウィジェットの内容は、アプリが最後に同期したときのものです。** Claude が予定を書きかえたら、一度アプリを開くとウィジェットにも反映されます
- **ウィジェットでのチェックは、次にアプリを開いたときにサーバーへ送られます**
- 自動タイマーは、iPhone の決まりで「アプリを開いているとき」に始まります。アプリを閉じている間にタイマーを自動で始めることはできません。開始時刻の通知をオンにしておき、通知を押してアプリを開くと、自動で始まります
- ライブアクティビティが出ないときは、iPhone の **設定 → MyStudy → ライブアクティビティ** がオンか確認してください

### うまくいかないとき

| 画面・エラー | 原因 | 直し方 |
|---|---|---|
| `Provisioning profile ... doesn't include the com.apple.security.application-groups entitlement` | App Group がまだ登録されていない | 手順5の App Groups にチェックを入れる。それでもだめなら 🔄 を押す |
| `Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier` | Bundle ID を Xcode の画面で直接変えた | Xcode の画面ではなく `Config/Config.xcconfig` の `APP_BUNDLE_ID` で変える。画面で変えた値は元の `$(APP_BUNDLE_ID)` に戻す |
| ウィジェットに「アプリを開いてログインしてください」と出る | アプリがまだデータを書き出していない、または App Group の設定ちがい | アプリを一度開く。直らなければ手順5で、2つのターゲットの App Group が同じか確認 |
| `git pull` で `Your local changes ... would be overwritten` | Xcode が書きかえたファイルがある | 表示されたファイル名で `git checkout -- ファイル名` を実行してから、もう一度 `git pull` |

---

## 集中モード(スクリーンタイムで Anki 以外を制限)

勉強中は、選んだアプリ(Anki と MyStudy など)以外を開けないようにします。かけ方は3つです。

| かけ方 | いつかかる | いつ外れる |
|---|---|---|
| 予定ブロックの時間(自動) | 予定の開始時刻。**アプリを閉じていても**始まる | 予定の終了時刻、またはその予定にチェックを付けたとき |
| タイマー中 | タイマーを始めたとき(自動タイマーも) | タイマーを止めたとき。止め忘れても予定の終了時刻(最長3時間)で外れる |
| 今すぐ集中モード | 25・50・90分のボタンを押したとき | 時間が来たとき |

どれも「終わりの時刻」が必ず決まっているので、アプリを開けなくなっても、時間が来れば自動で外れます。

### 大事な注意: TestFlight の版では、まだ使えません

スクリーンタイムの機能は、Apple が特別な許可(Family Controls)を出したアプリしか配布できません。

- **Xcode から ▶ で iPhone に入れた版:** すぐに使えます(有料の開発者アカウントなら、入れてから1年間使えます)
- **TestFlight の版:** Apple に申請して許可が下りるまで、この機能は「使えません」と表示されます(ほかの機能はそのまま使えます)。
  申請しても、返事まで数週間かかることがよくあります

当面は、**Xcode から ▶ で入れた版を使う**のがおすすめです。

> TestFlight 用の版では、許可が下りるまで、監視用の拡張機能(MyStudyFocusMonitor)をアプリから自動で取りのぞいています。
> 拡張機能が入っていると、App Store Connect に「Missing Entitlement(com.apple.developer.family-controls)」と言われて、アップロードを断られるためです。

### あなたがやること

1. ターミナルで最新のコードを取りこむ(`git checkout -- MyStudyApp.xcodeproj` → `git pull`)
2. Xcode の **TARGETS** に **MyStudyFocusMonitor** が増えています。これも **Signing & Capabilities** で **Team** を選び、**App Groups** にチェックを入れる
3. **MyStudyApp** と **MyStudyFocusMonitor** の **Signing & Capabilities** に **Family Controls** が表示されていることを確認する
   - 赤いエラーが出たら、Team を選び直す。直らなければ、右上の **+ Capability** から **Family Controls** を追加する
4. **▶** で iPhone に入れる
5. アプリの右上の **…** → **集中モード(スクリーンタイム)…** を開き、上から順に設定する
   1. **スクリーンタイムの使用を許可する** → Face ID などで許可
   2. **使ってよいアプリを選ぶ** → **Anki** と **MyStudy** を必ず選ぶ(必要なら Claude なども)
      - **MyStudy を選び忘れると、集中モード中にこのアプリも開けなくなります。** その場合も、終わりの時刻には自動で外れます
      - 「教育」などのカテゴリをまるごと選んでも反映されません。アプリを1つずつ選んでください
   3. 「タイマー中」「予定ブロックの時間(自動)」を好みでオンにする
6. 試しに **25分 集中する** を押し、ほかのアプリが開けなくなること、**今すぐ終える** で戻ることを確認する

### TestFlight の版でも使いたくなったら

1. Apple の申請フォーム(<https://developer.apple.com/contact/request/family-controls-distribution>)から、**アプリ本体**と**監視用の拡張機能**(`あなたのBundle ID.FocusMonitor`)の両方について申請する
2. 許可が下りたら、`Config/Config.xcconfig` の `RELEASE_SCREEN_TIME_SUFFIX =` を `RELEASE_SCREEN_TIME_SUFFIX = -ScreenTime` に書きかえて、TestFlight に上げなおす

---

## Xcode でエラーが出たとき(ビルドエラー)

このアプリのコードは、Mac のない環境(Linux)で書いて検査しました。
通信・同期・日付計算などのロジックは実際にコンパイルしてテスト済みですが、
**画面(SwiftUI)と端末内保存(SwiftData)の部分は、本物の Xcode ではまだ一度もビルドしていません。**
最初のビルドで赤いエラーが出る可能性があります。そのときは次のようにしてください。

1. Xcode の左の一覧の上にある **⚠ のタブ(Issue navigator)** を開く
2. 赤い ● の行をクリックすると、エラーの文と、問題のファイル・行が表示される
3. **エラーの文をそのままコピー**して、ファイル名と行番号といっしょに Claude に伝える
   - 例: 「`DayScreen.swift` の 54 行目で `Cannot find 'xxx' in scope` と出ました」

> 赤いエラーが1つだけでも、ビルドは最後まで進みません。
> いちばん上のエラーから順に直すのがコツです(1つ直すと、ほかも消えることがよくあります)。

実機で動かしたら、次の点も見てもらえると助かります。

- 画面をたてにスクロールできるか(左右スワイプの判定と同時に動くようにしているため)。
  もしスクロールしにくい場合は、`MyStudyApp/Day/DayScreen.swift` の
  `.simultaneousGesture(daySwipeGesture)` の1行を消すと、矢印ボタンだけで日付を切りかえる動きになります

---

## おまけ: Claude(別のチャット)から予定を書きこめるようにする

方法は2つあります。まず (B) で試して、慣れたら (A) にするのがおすすめです。

### (B) かんたんな方法: SQL を貼り付ける

1. Claude のチャットに `docs/FOR_CLAUDE.md` の中身を貼り付けて、「明日の予定を入れる SQL を書いて」とお願いする
2. Claude が書いた SQL を、Supabase の **SQL Editor** に貼り付けて **Run** を押す

毎回貼るのが手間なら、claude.ai の **プロジェクト** を作って、`FOR_CLAUDE.md` をプロジェクトの知識(ナレッジ)に入れておくと、そのプロジェクトのチャットではいつも読んでくれます。
自分の `user_id` もいっしょに書いておくと、毎回調べずに済みます。

### (A) 自動の方法: Supabase のコネクタをつなぐ

Supabase は、Claude から直接 SQL を実行できる「MCP サーバー」を公開しています。

1. Supabase の **Project Settings → General** で **Project ID**(英小文字の並び)を調べる
2. claude.ai の **設定 → コネクタ** で「カスタムコネクタを追加」を選び、次の URL を入れる(`あなたのProjectID` を置きかえる)

   ```
   https://mcp.supabase.com/mcp?project_ref=あなたのProjectID
   ```

3. Supabase のログイン画面が出るので、許可する

> **注意**: このコネクタは、RLS を通らない強い権限でデータベースを操作できます。
> - URL に `project_ref=...` を必ず付けて、**このプロジェクトだけ**に限定してください
> - Claude が SQL を実行する前に出る確認は、内容を読んでから許可してください
> - チェック済みの行を消す操作は、データベース側の安全装置(トリガー)で止まるようにしてあります
>
> claude.ai の画面の名前や場所は変わることがあります。見つからないときは、Supabase 公式の案内
> <https://supabase.com/docs/guides/ai-tools/mcp> を見てください。
