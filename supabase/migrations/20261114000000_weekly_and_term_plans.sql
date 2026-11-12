-- =====================================================================
-- 週次計画・月次(期間)計画のテーブル
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
--   term_plans  … 期間の計画(例: 期末までの計画)。「そもそも終わる?」の数字と「月の流れ」
--   weeks       … 1週間ごとの情報(ラベル・その週の行事・バッファのメモ)
--   week_goals  … その週にやること(例: 数学 12問)。どの箱ができたかを done_boxes で覚える
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. term_plans: 期間の計画
-- ---------------------------------------------------------------------
create table public.term_plans (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title      text not null,                 -- 例: 期末までの週次計画
  start_date date not null,
  end_date   date not null,
  overview_title text,                      -- 例: そもそも終わる?(11/12〜11/29の学校課題)
  -- 数字のカード。例: [{"label":"必要な時間","value":"約24時間","detail":"数学59問・読書8枚"}]
  stats      jsonb not null default '[]'::jsonb,
  overview_note text,                       -- 数字カードの下の説明
  -- 月の流れ。例: [{"range":"〜11/15","color":"blue","text":"通常期。…"}]
  phases     jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, title),
  check (end_date >= start_date),
  check (jsonb_typeof(stats) = 'array'),
  check (jsonb_typeof(phases) = 'array')
);

-- ---------------------------------------------------------------------
-- 2. weeks: 1週間ごとの情報(week_start は、その週の月曜日)
-- ---------------------------------------------------------------------
create table public.weeks (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),  -- 月曜日だけ
  label      text,                          -- 例: 通常期 / ちょっと忙しい / ガチテストモード
  color      text,                          -- blue / yellow / red / purple / green / gray
  subtitle   text,                          -- 例: 今日11/12(木)から
  events     jsonb not null default '[]'::jsonb,  -- その週の行事。例: ["11/13(金) 会計③ 配信"]
  buffer     text,                          -- バッファのメモ
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, week_start),
  check (jsonb_typeof(events) = 'array')
);

-- ---------------------------------------------------------------------
-- 3. week_goals: その週にやること
-- ---------------------------------------------------------------------
create table public.week_goals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  week_start   date not null,
  group_name   text not null default 'その他',   -- 例: 学校 / 鑑定士
  title        text not null check (length(trim(title)) > 0),  -- 例: 数学(B・II)
  detail       text,                              -- 例: 木金土日に3問ずつ
  target_count integer not null default 1 check (target_count between 1 and 200),  -- 箱の数
  -- できた箱の番号(1から)。例: {1,2,5}。アプリで1つずつ押すと増える/減る
  done_boxes   integer[] not null default '{}',
  -- できた数(done_boxes から自動で計算される。書きこまない)
  done_count   integer generated always as (cardinality(done_boxes)) stored,
  sort_order   integer not null default 0,
  source       text not null default 'claude' check (source in ('claude', 'app')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (user_id, week_start) references public.weeks (user_id, week_start) on delete cascade
);
create index week_goals_user_week_idx on public.week_goals (user_id, week_start);

-- done_boxes をととのえる: 箱の範囲(1〜target_count)の外を捨て、重複をなくして小さい順にする
create function public.normalize_done_boxes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.done_boxes := coalesce(
    (select array_agg(distinct b order by b) from unnest(new.done_boxes) as b
     where b between 1 and new.target_count),
    '{}'
  );
  return new;
end;
$$;

create trigger week_goals_normalize_done_boxes before insert or update on public.week_goals
  for each row execute function public.normalize_done_boxes();

-- updated_at を自動で更新(ステップ1で作った関数を使う)
create trigger term_plans_set_updated_at before update on public.term_plans
  for each row execute function public.set_updated_at();
create trigger weeks_set_updated_at before update on public.weeks
  for each row execute function public.set_updated_at();
create trigger week_goals_set_updated_at before update on public.week_goals
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- 4. 権限と RLS(自分の行だけ読み書きできる)
-- ---------------------------------------------------------------------
revoke all on public.term_plans, public.weeks, public.week_goals from anon;
grant select, insert, update, delete on public.term_plans, public.weeks, public.week_goals to authenticated;

alter table public.term_plans enable row level security;
alter table public.weeks      enable row level security;
alter table public.week_goals enable row level security;

create policy "term_plans: 自分の行だけ" on public.term_plans for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "weeks: 自分の行だけ" on public.weeks for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "week_goals: 自分の行だけ" on public.week_goals for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- 5. Claude が書き込むための関数(DELETE 文を直接使わずに入れ直せる)
-- ---------------------------------------------------------------------

-- 期間の計画を入れる/入れ直す(同じ title があれば上書き)
create or replace function public.replace_term_plan(
  p_user_id uuid, p_title text, p_start date, p_end date,
  p_overview_title text, p_stats jsonb, p_overview_note text, p_phases jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.term_plans (user_id, title, start_date, end_date, overview_title, stats, overview_note, phases)
  values (p_user_id, p_title, p_start, p_end, p_overview_title,
          coalesce(p_stats, '[]'::jsonb), p_overview_note, coalesce(p_phases, '[]'::jsonb))
  on conflict (user_id, title) do update set
    start_date = excluded.start_date, end_date = excluded.end_date,
    overview_title = excluded.overview_title, stats = excluded.stats,
    overview_note = excluded.overview_note, phases = excluded.phases
  returning id into v_id;
  return v_id;
end;
$$;

-- 期間の計画を消す
create or replace function public.remove_term_plan(p_user_id uuid, p_title text)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.term_plans where user_id = p_user_id and title = p_title;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 1週間の計画を入れる/入れ直す。
-- やること(p_goals)は入れ直すが、「同じ group_name と title」のものは、できた箱(done_boxes)を引きつぐ
--   p_goals の例: '[{"group_name":"学校","title":"数学(B・II)","detail":"木金土日に3問ずつ","target_count":12,"sort_order":10}]'
create or replace function public.replace_week_plan(
  p_user_id uuid, p_week_start date, p_label text, p_color text, p_subtitle text,
  p_events jsonb, p_buffer text, p_goals jsonb
)
returns table (goal_count integer, kept_progress integer)
language plpgsql
set search_path = ''
as $$
declare
  v_kept integer := 0;
  v_count integer;
begin
  if extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start(%)は月曜日にしてください', p_week_start;
  end if;

  insert into public.weeks (user_id, week_start, label, color, subtitle, events, buffer)
  values (p_user_id, p_week_start, p_label, p_color, p_subtitle, coalesce(p_events, '[]'::jsonb), p_buffer)
  on conflict (user_id, week_start) do update set
    label = excluded.label, color = excluded.color, subtitle = excluded.subtitle,
    events = excluded.events, buffer = excluded.buffer;

  -- 今のできた箱を覚えておく
  create temp table if not exists pg_temp.old_progress (group_name text, title text, done_boxes integer[]) on commit drop;
  delete from pg_temp.old_progress;
  insert into pg_temp.old_progress
  select g.group_name, g.title, g.done_boxes from public.week_goals g
  where g.user_id = p_user_id and g.week_start = p_week_start;

  delete from public.week_goals where user_id = p_user_id and week_start = p_week_start and source = 'claude';

  insert into public.week_goals (user_id, week_start, group_name, title, detail, target_count, done_boxes, sort_order)
  select p_user_id, p_week_start,
         coalesce(nullif(x.group_name, ''), 'その他'), x.title, x.detail,
         coalesce(x.target_count, 1),
         coalesce(o.done_boxes, '{}'),   -- 箱が減った分は、トリガーが自動で捨てる
         coalesce(x.sort_order, 0)
  from jsonb_to_recordset(coalesce(p_goals, '[]'::jsonb))
       as x(group_name text, title text, detail text, target_count integer, sort_order integer)
  left join pg_temp.old_progress o
    on o.group_name = coalesce(nullif(x.group_name, ''), 'その他') and o.title = x.title;
  get diagnostics v_count = row_count;

  select count(*) into v_kept
  from public.week_goals g join pg_temp.old_progress o on o.group_name = g.group_name and o.title = g.title
  where g.user_id = p_user_id and g.week_start = p_week_start and g.done_count > 0;

  return query select v_count, v_kept;
end;
$$;

revoke all on function public.replace_term_plan(uuid, text, date, date, text, jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function public.remove_term_plan(uuid, text) from public, anon, authenticated;
revoke all on function public.replace_week_plan(uuid, date, text, text, text, jsonb, text, jsonb) from public, anon, authenticated;
