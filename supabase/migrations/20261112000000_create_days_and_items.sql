-- =====================================================================
-- MyStudyApp: テーブル作成と RLS(行レベルセキュリティ)の設定
--
-- 使い方: Supabase の画面 → SQL Editor にこのファイルの中身を全部貼り付けて
--         「Run」を押す(1回だけ)。
--
-- 作るもの:
--   1. days  テーブル … 1日ごとの「目標」と「ふりかえり」
--   2. items テーブル … 予定ブロック(時間あり)とタスク(時間なし)
--   3. トリガー      … updated_at / done_at を自動で入れる、チェック済みの行を守る
--   4. RLS           … 「自分の行だけ読み書きできる」というルール
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. days: 1日ごとの情報
-- ---------------------------------------------------------------------
create table public.days (
  -- だれのデータか。アプリから入れるときは自動でログイン中のユーザーになる
  user_id    uuid not null default auth.uid()
             references auth.users (id) on delete cascade,
  -- 日付(日本時間の日付をそのまま入れる。例: 2026-11-13)
  date       date not null,
  goal       text,          -- 1日の目標(Claude が書く)
  reflection text,          -- ふりかえり(アプリで自分が書く)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- 「同じ人の同じ日」は1行だけ、という決まり(主キー)
  primary key (user_id, date)
);

comment on table  public.days            is '1日ごとの目標とふりかえり。1ユーザー1日につき1行。';
comment on column public.days.date       is '日本時間(JST)の日付';
comment on column public.days.goal       is '1日の目標。Claude が書き込む';
comment on column public.days.reflection is 'ふりかえり。アプリでユーザーが書く。Claude は上書きしないこと';


-- ---------------------------------------------------------------------
-- 2. items: 予定ブロックとタスク
-- ---------------------------------------------------------------------
create table public.items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
             references auth.users (id) on delete cascade,
  date       date not null,

  -- 'block' = 時間つきの予定 / 'task' = 時間なしのやること
  kind       text not null check (kind in ('block', 'task')),
  start_time time,          -- 例 16:30(block のときだけ入れる)
  end_time   time,          -- 例 17:30(block のときだけ入れる)

  title      text not null check (length(trim(title)) > 0),

  -- 科目。あえて「決まった値しか入らない」制限は付けていない。
  -- 科目を増やしたいとき(例: 行政法規)に、DBもアプリも変更せずに済むようにするため。
  subject    text not null default 'その他',

  sort_order integer not null default 0,   -- 並び順(小さいほど上)

  -- だれが作った行か。'claude' = Claude が計画として入れた / 'app' = アプリで手入力した
  -- Claude が予定を入れ直すとき、'claude' かつ未チェックの行だけを消す、というルールに使う
  source     text not null default 'claude' check (source in ('claude', 'app')),

  done           boolean not null default false,  -- チェック済みか
  done_at        timestamptz,                     -- チェックした日時
  actual_minutes integer check (actual_minutes >= 0), -- 実際にかかった分数(任意)
  note           text,                            -- メモ(任意)

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- block には開始・終了の両方が必要。task には時間を入れない。
  constraint items_time_matches_kind check (
    (kind = 'block' and start_time is not null and end_time is not null)
    or
    (kind = 'task'  and start_time is null     and end_time is null)
  )
);

comment on table  public.items            is '予定ブロック(block)とタスク(task)。';
comment on column public.items.kind       is $$'block' = 時間つきの予定 / 'task' = 時間なしのやること$$;
comment on column public.items.start_time is '開始時刻(日本時間)。block のみ必須、task は NULL';
comment on column public.items.end_time   is '終了時刻(日本時間)。block のみ必須、task は NULL';
comment on column public.items.subject    is '科目。推奨値: 鑑定理論 / 行政法規 / 民法 / 経済 / 会計 / 学校 / その他';
comment on column public.items.source     is $$'claude' = Claude が入れた計画 / 'app' = アプリで手入力$$;
comment on column public.items.done       is 'チェック済みか。チェック済みの行は削除できない(トリガーで保護)';

-- 「ある人の、ある日の予定」をすばやく取り出すための索引
create index items_user_date_idx on public.items (user_id, date);


-- ---------------------------------------------------------------------
-- 3. トリガー(行が変更されたときに自動で動く小さなプログラム)
-- ---------------------------------------------------------------------

-- 3-1. 更新のたびに updated_at を「今」にする
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger days_set_updated_at
  before update on public.days
  for each row execute function public.set_updated_at();

create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

-- 3-2. チェックを付けたら done_at を入れ、外したら done_at を消す
--      (アプリが done_at を指定してきたときは、その値をそのまま使う。
--        オフライン中にチェックした「本当の時刻」を残すため)
create function public.sync_done_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.done and new.done_at is null then
    new.done_at := now();
  elsif not new.done then
    new.done_at := null;
  end if;
  return new;
end;
$$;

create trigger items_sync_done_at
  before insert or update on public.items
  for each row execute function public.sync_done_at();

-- 3-3. チェック済みの行は削除させない(勉強の記録を守る安全装置)
--      Claude がうっかり「その日の予定を全部削除」しても、エラーになって何も消えない。
--      どうしても消したいときは、先に done = false に戻してから削除する。
create function public.prevent_delete_done_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception
    'チェック済み(done = true)の行は削除できません。DELETE 文に "and done = false" を付けてください。(item id: %)', old.id
    using errcode = 'P0001';
end;
$$;

create trigger items_prevent_delete_done
  before delete on public.items
  for each row
  when (old.done)
  execute function public.prevent_delete_done_item();


-- ---------------------------------------------------------------------
-- 4. 権限と RLS(Row Level Security)
--
--   守りは2段階になっている:
--   (a) GRANT … 「このテーブルに触ってよい役割」を決める(入口のカギ)
--   (b) RLS   … 「その中のどの行に触ってよいか」を決める(部屋ごとのカギ)
-- ---------------------------------------------------------------------

-- (a) ログイン済みユーザー(authenticated)だけがテーブルに触れる。
--     未ログイン(anon)には何も許可しない。
revoke all on public.days, public.items from anon;
grant select, insert, update, delete on public.days, public.items to authenticated;

-- (b) RLS を有効にする。有効にすると「許可するルール(ポリシー)」が無い操作は全部拒否される。
alter table public.days  enable row level security;
alter table public.items enable row level security;

-- ルール: user_id が自分(auth.uid())の行だけ、読む・追加・更新・削除ができる。
--   using      … すでにある行のうち、どれに触れるか
--   with check … 追加・更新した後の行が、この条件を満たしていないとダメ
create policy "days: 自分の行だけ読める"
  on public.days for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "days: 自分の行だけ追加できる"
  on public.days for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "days: 自分の行だけ更新できる"
  on public.days for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "days: 自分の行だけ削除できる"
  on public.days for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "items: 自分の行だけ読める"
  on public.items for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "items: 自分の行だけ追加できる"
  on public.items for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "items: 自分の行だけ更新できる"
  on public.items for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "items: 自分の行だけ削除できる"
  on public.items for delete to authenticated
  using ((select auth.uid()) = user_id);
