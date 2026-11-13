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
| `end_time` | time | 終了時刻(例 `'17:30'`)。**block では任意**(「6:30 起きる」のように開始だけでもよい)、task は NULL | block のみ(任意) |
| `title` | text | 内容(例「Anki 鑑定評価基準」) | 必ず指定 |
| `subject` | text | 科目。下の「推奨値」から選ぶ。省略すると `'その他'` | 指定する |
| `sort_order` | integer | 並び順(小さいほど上)。10, 20, 30… と10きざみで付ける | 指定する |
| `source` | text | `'claude'` = Claude が入れた / `'app'` = アプリで手入力。省略すると `'claude'` | **省略する**(`'claude'` になる) |
| `done` | boolean | チェック済みか(ユーザーがアプリで付ける) | **触らない** |
| `done_at` | timestamptz | チェックした日時(自動) | **触らない** |
| `actual_minutes` | integer | 実際にかかった分数(アプリのタイマーが記録する) | **触らない** |
| `note` | text | メモ。予定の補足を書いてもよい(例「15分(解く10分+答え合わせ5分)」) | 任意 |
| `steps` | jsonb | **手順**。文字の配列(例 `["10分タイマーで解く", "答え合わせ"]`)。アプリで「手順と注意」を開くと番号つきで出る | 任意 |
| `cautions` | jsonb | **注意**。文字の配列。アプリで箇条書きで出る | 任意 |
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
    {"kind":"block","start_time":"06:30","title":"起きる","sort_order":10},
    {"kind":"block","start_time":"06:40","end_time":"06:55","title":"経済 ミニテスト1問","subject":"経済",
     "note":"15分(解く10分+答え合わせ5分)",
     "steps":["10分タイマーで解く","答え合わせで間違えたところに赤ペン","最後に「なぜそうなるか」を1文で書く"],
     "cautions":["解けなかった所は、TACでAnkiに入れる候補としてメモしておく"],
     "sort_order":20},
    {"kind":"block","start_time":"16:30","end_time":"17:30","title":"Anki 鑑定評価基準","subject":"鑑定理論","sort_order":30},
    {"kind":"task","title":"英語の宿題を提出する","subject":"学校","sort_order":40}
  ]'::jsonb
);
-- 結果: deleted_count(消した数)と inserted_count(入れた数)が返る

-- id を指定して消す(消せるのは Claude が入れた・未チェック・今日以降の行だけ)
select public.remove_plan_items('ここにuser_idを入れる', array['消したい行のid']::uuid[]);
```

- `p_items` の各行で使えるキー: `kind`(必須)、`title`(必須)、`start_time`(block は必須)、`end_time`(任意)、`subject`、`sort_order`、`note`、`steps`(手順の配列)、`cautions`(注意の配列)
- **手順と注意の書き方のコツ:** 1つの手順は1つの動作にして、短く書く(例「10分タイマーで解く」)。順番が大事なものは `steps`、気をつけることは `cautions` に分ける
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
| `violates check constraint "items_time_matches_kind"` | block なのに開始時刻がない、または task なのに時刻がある | block は開始時刻を入れる(終了は任意)。task は両方 `null` |
| `violates check constraint "items_steps_check"`(または `items_cautions_check`) | 手順・注意が配列になっていない | `"steps":["…","…"]` のように `[ ]` でかこむ |
| `violates check constraint "items_kind_check"` | `kind` が `'block'` `'task'` 以外 | どちらかに直す |
| `null value in column "user_id"` | `user_id` を指定していない | 2章の方法で調べて指定する |
| `violates foreign key constraint` | `user_id` の値がまちがっている | 2章の SQL で正しい `id` を確認する |

---

## 6. 週次・月次(期間)の計画を書き込む

アプリの「週・月」タブに表示される計画です。日ごとの予定(`items`)とは別のテーブルです。
**書き込みは必ず下の関数を `select` で呼んでください**(DELETE 文は使わない)。

### テーブル

| テーブル | 中身 |
|---|---|
| `term_plans` | 期間の計画。タイトル・期間・「そもそも終わる?」の数字カード(`stats`)・「月の流れ」(`phases`) |
| `weeks` | 1週間ごとの情報。`week_start` は**その週の月曜日**。ラベル・色・行事(`events`)・バッファのメモ |
| `week_goals` | その週にやること。`target_count` = 箱の数(例: 数学12問なら12、1回だけのことなら1) |

- 色(`color`)に使える値: `blue` / `yellow` / `red` / `purple` / `green` / `gray`
- `week_goals.done_boxes`(できた箱の番号)と `done_count`(できた数)は**アプリで押して記録するので、書き込まない**

### 期間の計画を入れる(同じ title があれば上書き)

```sql
select public.replace_term_plan(
  'ここにuser_idを入れる',
  '期末までの週次計画',          -- タイトル
  '2026-11-12', '2026-12-06',     -- 期間
  'そもそも終わる?(11/12〜11/29の学校課題)',
  '[
    {"label":"必要な時間","value":"約24時間","detail":"数学59問・読書8枚・提出物4つ"},
    {"label":"使える時間","value":"約28時間","detail":"平日22-23時×11日・土日午前2h×6日・11/23祝5h"},
    {"label":"余り","value":"約4時間","detail":"英語・化学Ankiは移動中で全部やる前提"}
  ]'::jsonb,
  'ほかの教科のテスト勉強は「前日に詰め込む」ので、この計算には入れていません。',
  '[
    {"range":"〜11/15","color":"blue","text":"通常期。学校課題の数学を毎日3問ずつ始める。"},
    {"range":"11/16〜22","color":"yellow","text":"ちょっと忙しい。基準Ankiの新規は1日300字に減らす。"},
    {"range":"11/23〜29","color":"red","text":"ガチテストモード。鑑定士は最低ライン50分だけ。"}
  ]'::jsonb
);
-- 消すとき: select public.remove_term_plan('ここにuser_idを入れる', '期末までの週次計画');
```

### 1週間の計画を入れる/入れ直す

```sql
select * from public.replace_week_plan(
  'ここにuser_idを入れる',
  '2026-11-09',            -- その週の月曜日(月曜以外はエラー)
  '通常期', 'blue',         -- ラベルと色
  '今日11/12(木)から',      -- 小さい説明(不要なら null)
  '["11/13(金) 会計③ 配信", "11/14(土) 演習基礎答練① 16:00-19:00"]'::jsonb,  -- 行事
  'バッファ:11/15(日)の22-23時。',  -- バッファのメモ(不要なら null)
  '[
    {"group_name":"学校","title":"数学(B・II)","detail":"木金土日に3問ずつ","target_count":12,"sort_order":10},
    {"group_name":"学校","title":"化学 アルデヒド実験考察(30分)","detail":"11/15(日)22:00締切 → 11/14(土)に","target_count":1,"sort_order":20},
    {"group_name":"鑑定士","title":"基準Anki 新規600字","detail":"毎日","target_count":4,"sort_order":30}
  ]'::jsonb
);
```

- 入れ直しても、**同じ `group_name` と `title` のやることは、できた箱を引きつぎます**(箱を減らしたときは、はみ出た分だけ消えます)
- だから、やることの名前は週の途中で変えないでください(変えると進み具合が0に戻ります)
- `group_name` はグループの見出しになります(例: 学校 / 鑑定士)。`sort_order` の小さい順に並びます
