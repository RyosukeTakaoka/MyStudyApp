# Claude 向け説明書: MyStudyApp のデータベースに書く・読む方法

このファイルは、**別のチャットの Claude** が、このアプリ(MyStudyApp)のデータベースに
予定・計画・資料を書き込んだり、勉強の実績を読んだりするときに読む説明書です。

- データベース: Supabase(Postgres)
- アプリ: iPhone・iPad アプリが同じデータベースを読み、ユーザーがチェック・タイマー・ふりかえりを記録する
- あなた(Claude)の役割: ユーザーと相談して決めたことを、SQL で書き込む。実績を読んで、次の計画に生かす
- **アーティファクト(HTML のページやチェックリスト)や Claude Doc は作らず、すべてこのデータベースに入れてください**

### 何をどこに書くか

| 書きたいもの | 書く場所 | アプリでの見え方 | 章 |
|---|---|---|---|
| 1日の目標 | `days.goal` | 「今日」タブの上 | 3 |
| その日の予定・やること(手順と注意つき) | `items`(`replace_plan` 関数) | 「今日」タブ。タップでチェック、長押しでタイマー | 1・3 |
| 週の計画(行事・やること・バッファ) | `weeks` / `week_goals`(`replace_week_plan` 関数) | 「週・月」タブの週カード。箱を押して記録 | 6 |
| 期間の計画(そもそも終わる?・月の流れ) | `term_plans`(`replace_term_plan` 関数) | 「週・月」タブのいちばん上 | 6 |
| 予定ではない読み物(ルール・方針・振り返り) | `notes`(`upsert_note` 関数) | 「資料」タブ | 8 |
| 睡眠(寝る時刻・起きる時刻) | `sleep_plans`(`upsert_sleep` 関数) | 「今日」の予定の一覧に「睡眠」として出る(長押しのタイマーで実測)。カレンダーにも出る | 10 |
| 1日の勉強の目標時間・Claude からのひとこと | `days.target_minutes` / `days.coach_note` | 「今日」タブの目標の下に「Claude より」、「予定と実績」の表の目標 | 11 |
| 長期の目標(試験の日・3000時間) | `study_targets` | 「今日」タブのいちばん上の帯 | 11 |
| 答練の予定・成績・振り返り | `exam_results` | 「答練」タブ(点数の推移のグラフ)、次の答練は「今日」の帯 | 11 |
| 予定と週のやることのつながり | `replace_plan` の `"goal"` → `items.week_goal_title` | 予定をチェックすると、その週の箱が1つ埋まる | 11 |
| 読むだけ: チェック・実績・ふりかえり | `items.done` / `actual_minutes` / `study_sessions` / `days.reflection` | — | 7 |

### ユーザーがアプリでできること(計画を立てるときの前提)

- 予定をチェックする、タイマーで時間を測る(**いくつでも同時に動かせる**。一時停止・再開もできる)
- 勉強の予定(`block`)の開始時刻になると、タイマーを始めなくても自動で集中モード(スクリーンタイム)がかかる。
  **終わるのは、ユーザーが「完了(チェック)・一時停止・記録して終了」を押したとき**。予定の終了時刻を過ぎても、押すまで続く
  (押し忘れても、その日の 23:59 で必ず外れる)。押して終えても、次の勉強の予定の開始時刻にまた入る。
  **勉強の予定には `end_time` を入れてください**(終わりの時刻が無い予定には自動でかからない。アプリを開いたときにかけ直すのは、予定の終了時刻までだけ)
- 自動タイマー(予定の時間にアプリを開くとタイマーが始まる)は、ユーザーは使っていない(オフ)。タイマーはユーザーが長押しで始める
- 予定を自分で **足す・直す・明日に回す・消す**(そうした予定は `source = 'app'` になる。9章)
- 週のやることの箱を1つずつ押す、資料の □ を押す
- 勉強中は、スクリーンタイムで Anki など以外のアプリを制限する(集中モード)。予定の時間に自動でかけることもできる
- iPhone のカレンダー(学校の時間割・Google など)の予定は、アプリとウィジェットの「今」に出る(その時間に `items` の予定が無いとき)。
  授業などは `items` に入れなくても「今」に出るので、二重に入れなくてよい

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
| `source` | text | `'claude'` = Claude が入れた / `'app'` = ユーザーがアプリで入れた・直した(9章)。省略すると `'claude'` | **省略する**(`'claude'` になる) |
| `done` | boolean | チェック済みか(ユーザーがアプリで付ける) | **触らない** |
| `done_at` | timestamptz | チェックした日時(自動) | **触らない** |
| `actual_minutes` | integer | 実際にかかった分数(タイマーの区間からサーバーが計算する。手で直した値があればそれ) | **触らない** |
| `actual_override` | integer | ユーザーがアプリで手で直した実績(タイマーの押し忘れなど)。入っていれば `actual_minutes` はこの値 | **触らない** |
| `week_goal_title` | text | つながっている週のやることの題名(`replace_plan` の `"goal"` で入れる。11章) | 関数で入れる |
| `note` | text | メモ。予定の補足を書いてもよい(例「15分(解く10分+答え合わせ5分)」) | 任意 |
| `steps` | jsonb | **手順**。文字の配列(例 `["10分タイマーで解く", "答え合わせ"]`)。アプリで「手順と注意」を開くと番号つきで出る | 任意 |
| `cautions` | jsonb | **注意**。文字の配列。アプリで箇条書きで出る | 任意 |
| `created_at` / `updated_at` | timestamptz | 自動で入る | 触らない |

**`subject` の推奨値**(アプリが色分けに使います。表記をそろえてください)

`鑑定理論` / `行政法規` / `民法` / `経済` / `会計` / `学校` / `その他` / `生活`

- **勉強ではない予定(食事・お風呂・睡眠・移動・休憩など)は、`subject` を `'生活'` にしてください。**
  アプリは `生活` の予定では、集中モード(スクリーンタイムでアプリを制限)と自動タイマーを動かしません
- 食べながら勉強する予定(例「夕食 + Anki」)は、勉強の科目(例 `鑑定理論`)にします。こちらは集中モードがかかります(Anki は使えます)
- `その他` のときは、アプリが題名で見分けます(「夕食」「風呂」「通学」などの言葉があれば勉強ではない、「Anki」「復習」などがあれば勉強)

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
2. **その日にすでに入っている行を見る**(下の「確認用 SQL」)。`source = 'app'`(ユーザーが自分で入れた予定)と重ならないように組む
3. **`replace_plan` 関数で入れる**(下の「いちばんおすすめ」)
4. もう一度「確認用 SQL」を実行して、結果をユーザーに見せる

### 確認用 SQL(書き込む前と後に実行)

```sql
select kind, start_time, end_time, title, subject, source, done, actual_minutes, note, sort_order
from items
where user_id = 'ここにuser_idを入れる'
  and date = '2026-11-13'
order by kind, start_time nulls last, sort_order;
```

`done = true` の行や `source = 'app'` の行がすでにある場合、それらは**残ります**。
同じ内容をもう一度 INSERT すると二重になるので、**残る行と重なる予定は入れない**でください。

### いちばんおすすめ: 関数で入れ直す

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

### 参考: 関数を使わずに入れ直す(ユーザーが SQL Editor に貼って実行するときだけ)

コネクタからは `DELETE` が失敗することがあるので、ふだんは上の関数を使ってください。

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

### 予定を1件だけ追加したいとき

```sql
insert into items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note)
values ('ここにuser_idを入れる', '2026-11-13', 'block', '21:00', '21:30', '経済 ミクロ 復習', '経済', 40, 'テキスト p.30〜45');
```

### 予定の時間や内容を1件だけ直したいとき

消して入れ直すより、UPDATE のほうが安全です(チェックの記録がそのまま残ります)。
**直してよいのは `source = 'claude'` の行だけ**です(ユーザーが自分で入れた・直した予定は動かさない)。

```sql
update items
set start_time = '17:00', end_time = '18:00'
where user_id = 'ここにuser_idを入れる'
  and date = '2026-11-13'
  and source = 'claude'
  and title = 'Anki 鑑定評価基準';
```

---

## 4. やってはいけないこと

1. **チェック済み(`done = true`)の行を消さない。**
   勉強の記録です。DELETE には必ず `and done = false` を付けます。
   (付け忘れるとデータベースがエラーを出して、何も消えないようになっています。
   エラーが出たら、条件を直してやり直してください。安全装置のトリガーを外してはいけません)
2. **`source = 'app'` の行を消さない・書き換えない。** ユーザーがアプリで入れた・直した予定です(9章)。
3. **`done` / `done_at` / `actual_minutes` を書き換えない。** ユーザーの実績です。
4. **`days.reflection` を書き換えない。** `days` を更新するときは `goal` だけにします。
5. **過去の日付の行を消さない・入れ直さない。** 入れ直してよいのは今日と未来の日付だけです。
6. **`where` に `user_id` と `date` の両方がない DELETE / UPDATE を実行しない。**
7. **テーブルの形を変えない**(`alter table`、`drop table`、`truncate`、ポリシーやトリガーの変更など)。
   変更が必要だと思ったら、実行せずにユーザーに提案してください。
8. **`auth` スキーマには読み取り(`select`)以外をしない。**
9. **`study_sessions`(タイマーの記録)と `week_goals.done_boxes`(週の箱)には書き込まない。** アプリが記録するものです。
10. **資料(`notes`)を上書きするときは、今の本文を読んでから書く。** ユーザーが □ を押した `[x]` を消さないようにします(8章)。

## 5. エラーが出たとき

| エラーメッセージの一部 | 原因 | 直し方 |
|---|---|---|
| `チェック済み(done = true)の行は削除できません` | DELETE に `done = false` の条件がない | `and done = false` を付ける |
| `violates check constraint "items_time_matches_kind"` | block なのに開始時刻がない、または task なのに時刻がある | block は開始時刻を入れる(終了は任意)。task は両方 `null` |
| `violates check constraint "items_steps_check"`(または `items_cautions_check`) | 手順・注意が配列になっていない | `"steps":["…","…"]` のように `[ ]` でかこむ |
| `violates check constraint "items_kind_check"` | `kind` が `'block'` `'task'` 以外 | どちらかに直す |
| `null value in column "user_id"` | `user_id` を指定していない | 2章の方法で調べて指定する |
| `violates foreign key constraint` | `user_id` の値がまちがっている | 2章の SQL で正しい `id` を確認する |
| `過去の日付(…)は入れ直せません` | `replace_plan` に昨日以前の日付を渡した | 今日以降の日付にする(過去の予定は記録なので変えない) |
| `p_week_start(…)は月曜日にしてください` | `replace_week_plan` の週の始まりが月曜でない | その週の月曜日の日付にする |
| `violates check constraint "notes_slug_check"` | 資料の slug に大文字・日本語・空白がある | 英小文字・数字・ハイフンだけにする(例 `busy-minimum`) |

---

## 6. 週次・月次(期間)の計画を書き込む

アプリの「週・月」タブに表示される計画です。日ごとの予定(`items`)とは別のテーブルです。
**書き込みは必ず下の関数を `select` で呼んでください**(DELETE 文は使わない)。

### テーブル

| テーブル | 中身 |
|---|---|
| `term_plans` | 期間の計画。タイトル・期間・「そもそも終わる?」の数字カード(`stats`)・「月の流れ」(`phases`) |
| `weeks` | 1週間ごとの情報。`week_start` は**その週の月曜日**。ラベル・色・行事(`events`)・バッファのメモ |
| `week_goals` | その週にやること。`target_count` = 箱の数(例: 数学12問なら12、1回だけのことなら1)。`box_labels` = 箱ごとの名前(任意。下を参照) |

- 色(`color`)に使える値: `blue` / `yellow` / `red` / `purple` / `green` / `gray`
- `week_goals.done_boxes`(できた箱の番号)と `done_count`(できた数)は**アプリで押して記録するので、書き込まない**
- **箱を曜日で出したいときは `box_labels`** に、1つ目の箱から順に名前を入れる(`target_count` と同じ数)。
  アプリの「週・月」タブで「曜日」にすると、箱に番号の代わりにこの名前が出ます
  - 例: 演習30分(毎日1回 + 金曜2回)→ `"target_count":8, "box_labels":["月","火","水","木","金","金","土","日"]`
  - 例: 民法 A論証(平日2個ずつ)→ `"target_count":10, "box_labels":["月","月","火","火","水","水","木","木","金","金"]`
  - 例: 月に3つ・火に1つ・水に2つ → `"target_count":6, "box_labels":["月","月","月","火","水","水"]`
  - 箱ごとに自由に決められます。名前を付けない箱は `""`(空)にすると番号で出ます。途中から番号にしたいときは、
    うしろを省くか `""` にする(例 `["月","月","火","火","","",""]` → 月 月 火 火 5 6 7)
  - 名前の無い箱は、**箱がちょうど7つのやることなら自動で 月〜日**、それ以外は番号で出ます
    (曜日と関係ない7つ〔例: 7問〕のときは、`"box_labels":["1","2","3","4","5","6","7"]` のように番号を入れる)
  - **ユーザーはアプリで箱を長押しして、1つずつ曜日を付けかえられます。** 入れ直しで `box_labels` を**省略すると、
    その名前は残ります**(書けば、書いた名前で上書き)
  - `box_labels` を使うには、マイグレーション `20261122000000_week_goal_box_labels.sql` の実行が必要です
    (実行前は、`box_labels` は無視されて保存されません。エラーにはなりません)

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
    {"group_name":"鑑定士","title":"基準Anki 新規600字","detail":"毎日","target_count":4,"sort_order":30},
    {"group_name":"鑑定士","title":"演習30分","detail":"毎日1回+金曜は2回","target_count":8,
     "box_labels":["月","火","水","木","金","金","土","日"],"sort_order":40}
  ]'::jsonb
);
```

- 入れ直しても、**同じ `group_name` と `title` のやることは、できた箱を引きつぎます**(箱を減らしたときは、はみ出た分だけ消えます)
- だから、やることの名前は週の途中で変えないでください(変えると進み具合が0に戻ります)
- `group_name` はグループの見出しになります(例: 学校 / 鑑定士)。`sort_order` の小さい順に並びます

---

## 7. 実績(実際にやった時間)を読む

アプリのタイマーで測った時間は、次の2か所に入ります。**どちらも読むだけにして、書きかえないでください。**

| 場所 | 中身 |
|---|---|
| `items.actual_minutes` | 予定ごとの合計(分)。**サーバーが `study_sessions` の区間から自動で計算する**(重なった区間は1回だけ数える) |
| `study_sessions` | タイマーの区間ごとの記録。「始めた(再開した)時刻 〜 止めた時刻」が1行 |
| `running_timers` | **今動いている**(一時停止中もふくむ)タイマー。予定1つにつき1行。iPhone と iPad で共有している |

`study_sessions` の列:

| 列 | 中身 |
|---|---|
| `item_id` / `item_date` / `title` / `subject` | どの予定のタイマーか(題名と科目は、その時点の写し) |
| `started_at` / `ended_at` | 始めた・止めた時刻(**世界標準時**。日本時間にするときは `at time zone 'Asia/Tokyo'`) |
| `end_reason` | 止めた理由: `pause`(一時停止)/ `stop`(記録して終了)/ `done`(完了)/ `auto`(予定の終了時刻で自動終了)/ `switch`(古い版で別の予定に切りかえたとき。今は記録されない) |
| `minutes` | その区間の長さ(分、小数1けた。自動で計算される) |

- 実績は、タイマーを**止めたとき**(一時停止・終了)に記録されます。動いている途中の分は、まだ入っていません
- 電波がない場所で止めた分は、アプリが次につながったときに送られます
- **タイマーは同時にいくつも動かせます**(例: 夕食 30分 のあいだに Anki 10分)。時間が重なった区間は、それぞれの予定に記録されます。
  1日の「勉強した合計時間」を出すときは、重なりを二重に数えないように気をつけてください(例: 夕食などの勉強でない予定は合計から外す)
- 同じ予定でタイマーを何回か使うと、`actual_minutes` はその合計になります(区間が重なっていれば1回だけ数える)
- 今タイマーが動いているかは `running_timers` で読めます(`paused_at` が null なら動いている。経過秒数は
  `accumulated_seconds + (now() - started_at)`、一時停止中は `accumulated_seconds`)。ここも**読むだけ**にしてください
- **勉強時間の合計には、生活の時間(`subject = '生活'`、食事・移動など)を入れないでください。**
  アプリの円グラフ(生活も描くが、合計からは外す)と月のカレンダーも、生活の時間を外して合計しています(1章の「`subject` の推奨値」の下にある見分け方と同じ)。
  SQL では `where subject <> '生活'` を付けます

### 予定と実績をくらべる(1週間ぶん)

```sql
select date, title, subject, done,
       extract(epoch from (end_time - start_time)) / 60 as planned_minutes,
       actual_minutes
from items
where user_id = 'ここにuser_idを入れる'
  and date between '2026-11-09' and '2026-11-15'
order by date, start_time nulls last, sort_order;
```

### 科目ごとの合計(1週間ぶん)

```sql
select subject, sum(minutes) as total_minutes, count(*) as sessions
from study_sessions
where user_id = 'ここにuser_idを入れる'
  and (started_at at time zone 'Asia/Tokyo')::date between '2026-11-09' and '2026-11-15'
  and subject <> '生活'   -- 生活の時間(食事・移動など)は勉強時間に入れない
group by subject
order by total_minutes desc;
```

### 1日の流れ(いつ勉強して、いつ休んだか)

```sql
select to_char(started_at at time zone 'Asia/Tokyo', 'HH24:MI') as start_jst,
       to_char(ended_at   at time zone 'Asia/Tokyo', 'HH24:MI') as end_jst,
       title, subject, minutes, end_reason
from study_sessions
where user_id = 'ここにuser_idを入れる'
  and (started_at at time zone 'Asia/Tokyo')::date = '2026-11-13'
order by started_at;
```

**計画に生かすコツ:** 予定の時間より実績がいつも長い科目は、次の計画で時間を多めにとる。一時停止(`pause`)が多い時間帯は、集中しにくい時間帯かもしれない。

---

## 8. 資料ページを書く(アーティファクトの代わり)

予定ではない読み物(教科書の置き場所のルール、忙しい時期の最低ライン、スキマ時間のやり方、計画の説明文、答練の振り返りなど)は、
**アーティファクトや Claude Doc ではなく、`notes` テーブルに書いてください。** アプリの「資料」タブに一覧で出ます。

| 列 | 中身 |
|---|---|
| `slug` | 資料の名前(**英小文字・数字・ハイフンだけ**。例 `textbook-places`)。同じ slug で書くと上書きになる |
| `title` | 題名(日本語でよい) |
| `category` | 分類。`方針` / `ルール` / `答練` / `Anki` / `その他` など。一覧はこの分類ごとにまとまる |
| `body_md` | 本文(Markdown) |
| `pinned` | `true` にすると一覧のいちばん上に出る(よく見るものだけ) |
| `sort_order` | 同じ分類の中の並び順(小さいほど上) |

### 書く・消す

```sql
-- 書く(同じ slug があれば上書き)。最後の2つ(pinned, sort_order)は省略できる
select public.upsert_note(
  'ここにuser_idを入れる',
  'busy-minimum',
  '忙しい時期の最低ライン50分',
  '方針',
  $md$
# 忙しい時期の最低ライン(50分)

テスト前など時間が取れない日は、これだけやれば合格。

- [ ] 基準 Anki 新規 100字(15分)
- [ ] 民法 A論証 1個(15分)
- [ ] 経済 ミニテスト 1問(15分)
- [ ] 振り返り 5分

| 時間帯 | やること |
|---|---|
| 朝 | Anki |
| 夜 | A論証 |
$md$,
  true,
  10
);

-- 消す
select public.remove_note('ここにuser_idを入れる', 'busy-minimum');
```

- 本文は `$md$ 〜 $md$` で囲むと、`'` などの記号を気にせずにそのまま書けます
- アプリで表示できる書き方: 見出し(`#` `##` `###`)、**太字**、箇条書き(`-`)、番号つき(`1.`)、**チェック(`- [ ]` / `- [x]`)**、表(`| |`)、引用(`>`)、区切り線(`---`)、コード(```)、**Anki カード(```` ```anki ````、下の説明)**
- **`- [ ]` はアプリでチェックできます。** チェックすると本文の `[ ]` が `[x]` に書きかわるので、上書きするときは今の本文を読んでから、チェックの状態を残して書いてください

### Anki カード(ワンタップでコピーできるカード)

答練の振り返りなどで **Anki に入れるカード案** を作るときは、資料の本文に次の形で書いてください。
アプリでは、表と裏にそれぞれ「表をコピー」「裏をコピー」ボタンが付いたカードになり、ワンタップでコピーできます。
右上の「追加済み」を押すと、Anki に入れ終わった印になります(資料の一覧の進み具合にも数えられる)。

````md
## 11/12(木)に追加 ①〜⑨

```anki [ ] ① 問1
効用最大化条件の2つは?
---
① MRSxy = px/py(限界代替率=価格比)
② px·x + py·y = M(予算線の上にある)
```

```anki [ ] ② 問1
px だけが下がると、予算線はどう動く?
---
縦軸の切片(M/py)を中心に、反時計回りに回転する
```
````

- 1行目: ```` ```anki [ ] 見出し ```` 。`[ ]` は「追加済み」のチェック(アプリで押すと `[x]` になる)。見出しは「① 問1」のように、何番目か・どの問題から作ったかを書く
- `---` だけの行より上が **表(問題)**、下が **裏(答え)**。裏は何行でもよい
- 1枚ごとに ```` ``` ```` で閉じる。カードとカードのあいだに、見出し(`##`)やふつうの文章を書いてもよい
- **上書きするときは今の本文を読んでから**、`[x]` になっているカード(もう Anki に入れたもの)はそのまま残す
- 1つの答練のカードは1つの資料にまとめ、`category` は `Anki` にする(例 slug `econ-kiso-19`、題名「経済Ankiカード 第19回」)

```sql
-- 今の本文を読む
select slug, title, category, pinned, body_md from notes
where user_id = 'ここにuser_idを入れる' order by pinned desc, category, sort_order;
```

---

## 9. ユーザーがアプリで動かした予定(source = 'app')

ユーザーはアプリで、予定を**足す・直す・明日に回す・消す**ことができます。そうした予定は `source = 'app'` になります。

- `source = 'app'` の行は、**ユーザーが自分で決めた予定**です。消さない・書きかえない・時間を動かさないでください
  (`replace_plan` も `source = 'claude'` の行しか消さないので、入れ直しても残ります)
- Claude が入れた予定をユーザーが直すと、その行は `source = 'app'` に変わります
- **予定を入れ直すときは、先にその日の `source = 'app'` の行を読み、時間が重ならないように組んでください**
- 「明日に回す」を使うと、翌日に同じ予定(`source = 'app'`)ができ、元の予定のメモ(`note`)に「→ 11/15(日)へ」が付きます。
  元の予定は未チェックのまま残ります(やらなかった記録として)

---

## 10. 睡眠の予定を書く

寝る時刻・起きる時刻は、`items` ではなく **`sleep_plans`** に入れます。

- アプリの「今日」タブの**予定の一覧に「睡眠 22:45〜」として出ます**(その夜の日付の欄。夜は「今 → 次」の「今」にも出る)。
  ユーザーは長押しでタイマーを使って、**実際に寝た時間を測れます**。測った時間は `sleep_plans.actual_minutes`(分)に入ります(読むだけ)
- チェック・編集・削除はアプリではできません(変えるときは Claude が `upsert_sleep` / `remove_sleep` で)
- 科目は「生活」として扱うので、集中モード・勉強時間の合計・3000時間・進み具合の数・ウィジェットには入りません
- ユーザーがカレンダー連携をオンにしていると、iPhone の「MyStudy」カレンダーに **「睡眠」** として出ます(アプリを開いて同期したとき)
- **1晩に1行**。同じ夜をもう一度入れると上書きします
- 夜中の0時をまたいでも1行で書けます(`items` と違って、日付を分けなくてよい)
- **睡眠を `items` に入れないでください**(入れるとアプリの予定に出てしまいます)

### `sleep_plans` の列

| 列 | 型 | 説明 | Claude が書くか |
|---|---|---|---|
| `id` | uuid | 自動で入る | 指定しない |
| `user_id` | uuid | ユーザーのID | 関数に渡す |
| `night` | date | **その夜の日付**(11/18 の夜に寝て 11/19 の朝に起きる → `2026-11-18`)。0時すぎに寝る日も、前の日の夜の日付にする | 関数に渡す |
| `start_at` / `end_at` | timestamptz | 寝る時刻・起きる時刻(関数が日本時間から作る) | 関数が入れる |
| `note` | text | メモ(例「睡眠不足を取り返す」)。カレンダーのメモ欄に出る | 任意 |
| `source` | text | `'claude'` | 触らない |

### 入れる・書きかえる: `upsert_sleep`

```sql
-- 11/18(水)の夜 22:45 に寝て、11/19(木)の朝 6:30 に起きる
select public.upsert_sleep('<user_id>', '2026-11-18', '22:45', '06:30', '睡眠不足を取り返す');

-- 0時すぎに寝る日(11/19 の夜 → 11/20 の 0:30 に寝て 7:00 に起きる)。night は 11/19 にする
select public.upsert_sleep('<user_id>', '2026-11-19', '00:30', '07:00');
```

- 引数: `(user_id, その夜の日付, 寝る時刻 'HH:MM', 起きる時刻 'HH:MM', メモ〔省略可〕)`。時刻は**日本時間**
- 寝る時刻が **12:00 より前**(例 `00:30`)なら、その夜の**次の日**の 0:30 とみなします
- 起きる時刻が寝る時刻より前なら、次の日の朝とみなします
- 長さは16時間まで(それより長いとエラー)

### 消す: `remove_sleep`

```sql
select public.remove_sleep('<user_id>', '2026-11-18');   -- 消した数(0 か 1)が返る
```

### 確かめる

```sql
select night,
       start_at at time zone 'Asia/Tokyo' as 寝る,
       end_at   at time zone 'Asia/Tokyo' as 起きる,
       note
from sleep_plans
where user_id = '<user_id>' and night >= current_date - 1
order by night;
```

### エラーが出たとき

| エラーメッセージの一部 | 原因 | 直し方 |
|---|---|---|
| `function public.upsert_sleep(...) does not exist` | マイグレーション `20261118000000_sleep_plans.sql` がまだ実行されていない | ユーザーに SQL Editor で実行してもらう |
| `violates check constraint "sleep_plans_length"` | 寝る〜起きるが16時間より長い | 時刻(とくに午前・午後)を見直す |

---

## 11. 目標時間・Claude より・長期の目標・答練・週のやることとのつながり

(マイグレーション `20261123000000_plan_actual_exams.sql` を実行したあとから使えます)

### 1日の目標時間と「Claude より」(`days`)

| 列 | 中身 |
|---|---|
| `target_minutes` | その日の勉強の目標時間(分)。省略すると **平日240分・土日480分**。祝日や行事の日は入れてください(例 祝日 480) |
| `coach_note` | **Claude からのひとこと**。前日のふりかえりへの返事、その日の作戦・注意点を2〜3行で。アプリの目標の下に「Claude より」として出ます |

```sql
insert into days (user_id, date, target_minutes, coach_note)
values ('<user_id>', '2026-11-24', 240, '昨日は数学が30分押したので、今日は50分に延ばします。')
on conflict (user_id, date) do update set target_minutes = excluded.target_minutes, coach_note = excluded.coach_note;
```

- `reflection`(ユーザーのふりかえり)は上書きしないこと(上の SQL は `reflection` にふれません)
- 翌日の予定を入れるときに、ふりかえり(`days.reflection`)を読んでから `coach_note` を書くと、アプリを開いたときに返事が見えます

### 長期の目標(`study_targets`、1人1行)

「今日」タブのいちばん上の帯に「論文式試験まで ○日」「累計 ○時間 / 3000時間」と出ます。
累計 = `hours_before_app`(アプリを使う前に勉強した時間)+ アプリのタイマーの合計(生活の時間をのぞく)。

```sql
insert into study_targets (user_id, target_name, target_date, total_hours_goal, hours_before_app)
values ('<user_id>', '論文式試験', '2027-08-01', 3000, 0)
on conflict (user_id) do update set target_name = excluded.target_name, target_date = excluded.target_date,
  total_hours_goal = excluded.total_hours_goal, hours_before_app = excluded.hours_before_app;
```

**3000時間の目標・試験の日・アプリより前の勉強時間は、この `study_targets` で Claude が決めます**(上の SQL の数を変えるだけ)。

### 月ごとの勉強時間の配分(`study_month_plans`)

月ごとに何時間勉強するかを決めると、アプリの帯の「今月あと○時間」「1日あたり○時間」と月の目盛りが、その配分どおりになります。
配分の無い月は、残りの時間(目標 − 今月1日の累計 − 決めた月の合計)を等分します。1つも無ければ、試験の日まで同じペース。

```sql
insert into study_month_plans (user_id, month, planned_hours, note) values
  ('<user_id>', '2026-12-01', 250, '期末テストの週は少なめ'),
  ('<user_id>', '2027-01-01', 300, null)
on conflict (user_id, month) do update set planned_hours = excluded.planned_hours, note = excluded.note;
```

- `month` は**その月の1日**、`planned_hours` は**鑑定士の勉強**の時間(学校と生活は入れない)
- 今月どれだけ進んだかは `select public.study_minutes_since(date_trunc('month', now() at time zone 'Asia/Tokyo')::date);`(分)
- 配分の合計が目標(3000時間)と合わなくてもかまいません(目盛りは配分どおりに描きます)

アプリのタイマーの合計(分)は `select public.study_total_minutes();` で読めます。
これは **鑑定士の勉強だけ**の合計です(科目「学校」と生活〔食事・移動など〕は入れない。区間ごとの判定は `public.is_exam_study(subject, title)`)。
アプリの帯には、この累計から「今月あと○時間」「1日あたり○時間」「月あたり○時間」(試験の日までに目標に届くペース)を出しています。

### 答練の予定・成績・振り返り(`exam_results`)

| 列 | 中身 |
|---|---|
| `exam_date` / `start_time` | 受ける(受けた)日・始まる時刻 |
| `subject` / `title` | 科目・名前(例 鑑定理論 / 応用答練 第5回)。**日付・科目・名前の組み合わせで1行** |
| `score` / `full_score` / `average` / `rank` / `examinees` | 点数・満点・平均点・順位・受験者数。**点数が null の答練は「これからの答練」**として扱い、「今日」の帯に次の答練が出ます |
| `good_points` / `missed_points` / `next_actions` / `note` | 良かった点・論点漏れ(できなかった点)・次にやること・メモ |

```sql
-- 予定を入れる(まだ点数なし)
insert into exam_results (user_id, exam_date, start_time, subject, title)
values ('<user_id>', '2026-12-06', '09:00', '鑑定理論', '応用答練 第5回')
on conflict (user_id, exam_date, subject, title) do update set start_time = excluded.start_time;

-- 受けたあと: 成績と振り返りを入れる
update exam_results set score = 64, full_score = 100, average = 52, rank = 2, examinees = 130,
  good_points = '暗記はできている', missed_points = '耐用年数の論点漏れ', next_actions = '論点の目次を白紙で書く'
where user_id = '<user_id>' and exam_date = '2026-12-06' and title = '応用答練 第5回';

-- 消す(コネクタから select で呼べる)
select public.remove_exam_result('<user_id>', '<答練の id>');
```

- ユーザーもアプリで足したり直したりします(`source = 'app'`)。ユーザーが書いた振り返りは、頼まれない限り上書きしないこと
- 点数の推移は、満点が入っていれば満点に対する%でグラフにします。満点はなるべく入れてください

### 予定と週のやることをつなぐ(`replace_plan` の `"goal"`)

予定に `"goal": "週のやることの題名"` を付けると、ユーザーがその予定をチェックしたときに、
**その週(月曜〜日曜)の同じ題名のやることの箱が1つ自動で埋まります**(チェックを外すと1つ戻る)。

```sql
select * from public.replace_plan('<user_id>', '2026-11-27', null, '[
  {"kind":"block","start_time":"20:00","end_time":"20:30","title":"演習30分 1回目","subject":"鑑定理論","goal":"演習30分","sort_order":10},
  {"kind":"block","start_time":"21:00","end_time":"21:30","title":"演習30分 2回目","subject":"鑑定理論","goal":"演習30分","sort_order":20}
]'::jsonb);
```

- `"goal"` は、その週の `week_goals.title` と**完全に同じ文字**にする(ちがうと何も起きません)
- **どの箱を埋めるかは `"goal_boxes"` で1つずつ決められます**(順番どおりにやるとは限らないため、なるべく付けてください)。
  数は**箱に出る番号**(`box_start` があれば問題番号)。例: 数学 176〜181 のうち 178 をやる予定 → `"goal":"数学","goal_boxes":[178]`、
  180 と 181 をまとめてやる予定 → `"goal_boxes":[180,181]`。チェックを外すと、その箱だけ戻ります
  (マイグレーション `20261123020000_goal_boxes_month_plans.sql` のあとから使えます)
- `"goal_boxes"` を省略すると「その日の曜日の名前の箱」(例 金曜なら「金」の箱。7つで名前の無い箱は、その曜日の位置)を先に、無ければいちばん小さい番号の空いた箱
- アプリの予定の行に「→ 数学 178」のように、つながっている箱が出ます
- ユーザーが週の箱を自分で押すこともあるので、つないだやることを「両方押す」必要はなくなります

### 問題番号(`week_goals.box_start`)

数学 176〜181 のような「問題番号」を箱に出したいときは、`replace_week_plan` の各行に `"box_start": 176` を入れます
(`"target_count": 6` なら 176〜181 と出る)。省略すると前の値が残ります(ユーザーがアプリで決めた値も残る)。
