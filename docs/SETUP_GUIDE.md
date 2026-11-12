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
