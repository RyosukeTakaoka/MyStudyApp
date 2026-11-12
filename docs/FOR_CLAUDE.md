# Claude 向け説明書: Supabase に予定を書き込む方法

このファイルは、**別のチャットの Claude** が、このアプリ(MyStudyApp)のデータベースに
「翌日の予定」を書き込むときに読む説明書です。

- データベース: Supabase(Postgres)
- アプリ: iPhone アプリが同じデータベースを読み、ユーザーがタップでチェックを付ける
- あなた(Claude)の役割: ユーザーと相談して決めた予定を、SQL で `days` と `items` に書き込む

> **書き込み方は2通りあります**
> - (A) Supabase のコネクタ(MCP)がつながっている場合: あなたが SQL を直接実行する
> - (B) つながっていない場合: SQL を書いてユーザーに渡し、ユーザーが Supabase の
>   「SQL Editor」に貼り付けて実行する
>
> どちらの場合も、**RLS(行レベルセキュリティ)を通らない管理者権限**で実行されます。
> つまり `user_id` は自動では入りません。**必ず自分で `user_id` を指定**してください。

---

## 1. テーブル構造

### `days` — 1日ごとの情報(1ユーザー1日につき1行)

| 列 | 型 | 説明 | Claude が書くか |
|---|---|---|---|
| `user_id` | uuid | ユーザーのID(主キーの一部) | 必ず指定 |
| `date` | date | 日付。**日本時間**の日付(主キーの一部) | 必ず指定 |
| `goal` | text | 1日の目標 | **書く** |
| `reflection` | text | ふりかえり(ユーザーがアプリで書く) | **書かない・上書きしない** |
| `created_at` / `updated_at` | timestamptz | 自動で入る | 触らない |

### `items` — 予定ブロックとタスク

| 列 | 型 | 説明 | Claude が書くか |
|---|---|---|---|
| `id` | uuid | 自動で入る | 指定しない |
| `user_id` | uuid | ユーザーのID | 必ず指定 |
| `date` | date | 日付(日本時間) | 必ず指定 |
| `kind` | text | `'block'` = 時間つきの予定 / `'task'` = 時間なしのやること | 必ず指定 |
| `start_time` | time | 開始時刻(例 `'16:30'`)。**block は必須、task は NULL** | block のみ |
| `end_time` | time | 終了時刻(例 `'17:30'`)。**block は必須、task は NULL** | block のみ |
| `title` | text | 内容(例「Anki 鑑定評価基準」) | 必ず指定 |
| `subject` | text | 科目。下の「推奨値」から選ぶ。省略すると `'その他'` | 指定する |
| `sort_order` | integer | 並び順(小さいほど上)。10, 20, 30… と10きざみで付ける | 指定する |
| `source` | text | `'claude'` = Claude が入れた / `'app'` = アプリで手入力。省略すると `'claude'` | **省略する**(`'claude'` になる) |
| `done` | boolean | チェック済みか(ユーザーがアプリで付ける) | **触らない** |
| `done_at` | timestamptz | チェックした日時(自動) | **触らない** |
| `actual_minutes` | integer | 実際にかかった分数(アプリのタイマーが記録する) | **触らない** |
| `note` | text | メモ。予定の補足を書いてもよい(例「p.30〜45」) | 任意 |
| `created_at` / `updated_at` | timestamptz | 自動で入る | 触らない |

**`subject` の推奨値**(アプリが色分けに使います。表記をそろえてください)

`鑑定理論` / `行政法規` / `民法` / `経済` / `会計` / `学校` / `その他`

**時刻の決まり**

- `date` と時刻はすべて**日本時間(JST)**として扱う
- 日付をまたぐ予定(例 23:00〜翌1:00)は入れない。`23:00`〜`23:59` で区切るか、2日に分ける
- アプリは block を `start_time` の順に、task を `sort_order` の順に表示する

---

## 2. `user_id` の調べ方

このアプリのユーザーは1人だけです。最初に次の SQL を実行して `id` を確認してください。

```sql
select id, email, created_at from auth.users order by created_at;
```

- **1行だけ**返ってくるはずです。その `id`(例 `a1b2c3d4-...` の形)が `user_id` です
- 0行のとき: ユーザーがまだアプリで一度もログインしていません。先にログインしてもらってください
- 2行以上のとき: 勝手に選ばず、どれを使うかユーザーに確認してください

以下の例では `user_id` を `'ここにuser_idを入れる'` と書いています。**実際の値に置き換えて**ください。

---

## 3. 翌日の予定を入れる SQL の見本

### 手順(毎回この順番で)

1. **日付を確認する**: ユーザーが「明日」と言ったら、日本時間での具体的な日付(例 `2026-11-13`)に直す
2. **その日にすでに入っている行を見る**(下の「確認用 SQL」)
3. **入れ直し用 SQL** を、`begin;` 〜 `commit;` でひとまとめにして実行する
4. もう一度「確認用 SQL」を実行して、結果をユーザーに見せる

### 確認用 SQL(書き込む前と後に実行)

```sql
select kind, start_time, end_time, title, subject, source, done, sort_order
from items
where user_id = 'ここにuser_idを入れる'
  and date = '2026-11-13'
order by kind, start_time, sort_order;
```

`done = true` の行や `source = 'app'` の行がすでにある場合、それらは**残ります**。
同じ内容をもう一度 INSERT すると二重になるので、**残る行と重なる予定は入れない**でください。

### 入れ直し用 SQL(まるごとコピーして、値だけ書き換える)

```sql
begin;

-- (1) 1日の目標を書く。すでに行があるときは goal だけ更新する(ふりかえりは消えない)
insert into days (user_id, date, goal)
values ('ここにuser_idを入れる', '2026-11-13', '鑑定評価基準 総論を1周する')
on conflict (user_id, date) do update set goal = excluded.goal;

-- (2) その日の「Claude が入れた」「まだチェックされていない」行だけを消す
--     ※ この3つの条件(date / source = 'claude' / done = false)は絶対に外さない
delete from items
where user_id = 'ここにuser_idを入れる'
  and date = '2026-11-13'
  and source = 'claude'
  and done = false;

-- (3) 新しい予定を入れる
insert into items (user_id, date, kind, start_time, end_time, title, subject, sort_order)
values
  -- 例1: 時間つきの予定(block)
  ('ここにuser_idを入れる', '2026-11-13', 'block', '16:30', '17:30', 'Anki 鑑定評価基準',       '鑑定理論', 10),
  -- 例2: 時間つきの予定(block)
  ('ここにuser_idを入れる', '2026-11-13', 'block', '19:00', '20:30', '民法 物権 過去問 10問',   '民法',     20),
  -- 例3: 時間なしのやること(task)。start_time と end_time は null にする
  ('ここにuser_idを入れる', '2026-11-13', 'task',  null,    null,    '英語の宿題を提出する',    '学校',     30);

commit;
```

### いちばんおすすめ: 関数で入れ直す(コネクタから使うときはこちら)

チャットのコネクタから `DELETE` 文を実行すると、確認ボタンが出ずに失敗することがあります。
そのため、**入れ直しと削除は、次の2つの関数を `select` で呼んでください。**
関数の中で「Claude が入れた・未チェック・今日以降の行だけを消す」というルールが守られるので、安全です。

```sql
-- 1日の予定をまるごと入れ直す(目標も更新。目標を変えないときは第3引数を null に)
select * from public.replace_plan(
  'ここにuser_idを入れる',
  '2026-11-13',
  '鑑定評価基準 総論を1周する',
  '[
    {"kind":"block","start_time":"16:30","end_time":"17:30","title":"Anki 鑑定評価基準","subject":"鑑定理論","sort_order":10},
    {"kind":"block","start_time":"19:00","end_time":"20:30","title":"民法 物権 過去問 10問","subject":"民法","sort_order":20},
    {"kind":"task","title":"英語の宿題を提出する","subject":"学校","sort_order":30}
  ]'::jsonb
);
-- 結果: deleted_count(消した数)と inserted_count(入れた数)が返る

-- id を指定して消す(消せるのは Claude が入れた・未チェック・今日以降の行だけ)
select public.remove_plan_items('ここにuser_idを入れる', array['消したい行のid']::uuid[]);
```

- `p_items` の各行で使えるキー: `kind`(必須)、`title`(必須)、`start_time`・`end_time`(block は必須)、`subject`、`sort_order`、`note`
- 1行でもまちがいがあると、関数全体が取り消されて何も変わりません(エラー文を読んで直してから、もう一度呼ぶ)

### 予定を1件だけ追加したいとき

```sql
insert into items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note)
values ('ここにuser_idを入れる', '2026-11-13', 'block', '21:00', '21:30', '経済 ミクロ 復習', '経済', 40, 'テキスト p.30〜45');
```

### 予定の時間や内容を1件だけ直したいとき

消して入れ直すより、UPDATE のほうが安全です(チェックの記録がそのまま残ります)。

```sql
update items
set start_time = '17:00', end_time = '18:00'
where user_id = 'ここにuser_idを入れる'
  and date = '2026-11-13'
  and title = 'Anki 鑑定評価基準';
```

---

## 4. やってはいけないこと

1. **チェック済み(`done = true`)の行を消さない。**
   勉強の記録です。DELETE には必ず `and done = false` を付けます。
   (付け忘れるとデータベースがエラーを出して、何も消えないようになっています。
   エラーが出たら、条件を直してやり直してください。安全装置のトリガーを外してはいけません)
2. **`source = 'app'` の行を消さない・書き換えない。** ユーザーがアプリで手入力したものです。
3. **`done` / `done_at` / `actual_minutes` を書き換えない。** ユーザーの実績です。
4. **`days.reflection` を書き換えない。** `days` を更新するときは `goal` だけにします。
5. **過去の日付の行を消さない・入れ直さない。** 入れ直してよいのは今日と未来の日付だけです。
6. **`where` に `user_id` と `date` の両方がない DELETE / UPDATE を実行しない。**
7. **テーブルの形を変えない**(`alter table`、`drop table`、`truncate`、ポリシーやトリガーの変更など)。
   変更が必要だと思ったら、実行せずにユーザーに提案してください。
8. **`auth` スキーマには読み取り(`select`)以外をしない。**

## 5. エラーが出たとき

| エラーメッセージの一部 | 原因 | 直し方 |
|---|---|---|
| `チェック済み(done = true)の行は削除できません` | DELETE に `done = false` の条件がない | `and done = false` を付ける |
| `violates check constraint "items_time_matches_kind"` | block なのに時刻がない、または task なのに時刻がある | block は開始・終了の両方を入れる。task は両方 `null` |
| `violates check constraint "items_kind_check"` | `kind` が `'block'` `'task'` 以外 | どちらかに直す |
| `null value in column "user_id"` | `user_id` を指定していない | 2章の方法で調べて指定する |
| `violates foreign key constraint` | `user_id` の値がまちがっている | 2章の SQL で正しい `id` を確認する |
