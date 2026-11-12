# セットアップガイド(あなたがやること)

このアプリを自分の iPhone で動かすまでの手順を、ステップごとにまとめています。
上から順番に進めてください。

- [ステップ1: Supabase プロジェクトとテーブルを作る](#ステップ1-supabase-プロジェクトとテーブルを作る)
- [ステップ2: Xcode でプロジェクトを開いて動かす](#ステップ2-xcode-でプロジェクトを開いて動かす)

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
   - 世界で1つだけの名前である必要があります。エラーが出たら `com.自分の名前.MyStudyApp` のように変えてください
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
