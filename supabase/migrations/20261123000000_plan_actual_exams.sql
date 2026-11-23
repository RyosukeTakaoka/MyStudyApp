-- =====================================================================
-- 予定と実績・答練の成績・目標の帯・Claude より・週のやることとのつながり・問題番号
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ。2回実行しても大丈夫です)
--
-- 前に 20261121000000_running_timers.sql と 20261122000000_week_goal_box_labels.sql を
-- 実行してから、これを実行してください。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 週のやることの「問題番号」(例 数学 176〜181 → 箱に 176, 177, … と出す)
-- ---------------------------------------------------------------------
alter table public.week_goals
  add column if not exists box_start integer check (box_start is null or box_start >= 0);
comment on column public.week_goals.box_start is '1つ目の箱の番号(例 176)。null なら 1 から';

-- replace_week_plan: "box_start" も受け取る。省略したら前の値を残す(box_labels と同じ)
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
  create temp table if not exists pg_temp.old_progress (group_name text, title text, done_boxes integer[], box_labels text[], box_start integer) on commit drop;
  delete from pg_temp.old_progress;
  insert into pg_temp.old_progress
  select g.group_name, g.title, g.done_boxes, g.box_labels, g.box_start from public.week_goals g
  where g.user_id = p_user_id and g.week_start = p_week_start;

  delete from public.week_goals where user_id = p_user_id and week_start = p_week_start and source = 'claude';

  insert into public.week_goals (user_id, week_start, group_name, title, detail, target_count, done_boxes, box_labels, box_start, sort_order)
  select p_user_id, p_week_start,
         coalesce(nullif(x.group_name, ''), 'その他'), x.title, x.detail,
         coalesce(x.target_count, 1),
         coalesce(o.done_boxes, '{}'),   -- 箱が減った分は、トリガーが自動で捨てる
         -- 箱ごとの名前(例 曜日)。省略したら、前の名前(アプリで長押しして付けた名前など)を残す
         coalesce(x.box_labels, o.box_labels, '{}'),
         -- 問題番号の始まり(例 176)。省略したら、前の値(アプリで決めた値など)を残す
         coalesce(x.box_start, o.box_start),
         coalesce(x.sort_order, 0)
  from jsonb_to_recordset(coalesce(p_goals, '[]'::jsonb))
       as x(group_name text, title text, detail text, target_count integer, box_labels text[], box_start integer, sort_order integer)
  left join pg_temp.old_progress o
    on o.group_name = coalesce(nullif(x.group_name, ''), 'その他') and o.title = x.title;
  get diagnostics v_count = row_count;

  select count(*) into v_kept
  from public.week_goals g join pg_temp.old_progress o on o.group_name = g.group_name and o.title = g.title
  where g.user_id = p_user_id and g.week_start = p_week_start and g.done_count > 0;

  return query select v_count, v_kept;
end;
$$;

revoke all on function public.replace_week_plan(uuid, date, text, text, text, jsonb, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 実績の手直し(タイマーの押し忘れなどを、アプリで「実際は15分」と直す)
-- ---------------------------------------------------------------------
alter table public.items
  add column if not exists actual_override integer check (actual_override is null or actual_override >= 0);
comment on column public.items.actual_override is
  '手で直した実績(分)。入っていれば、タイマーの区間から計算した値より優先する。アプリが書く';

create or replace function public.items_actual_from_sessions()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v integer;
begin
  if new.actual_override is not null then
    new.actual_minutes := new.actual_override;     -- 手で直した値がいちばん優先
    return new;
  end if;
  v := public.session_minutes(new.id);
  if v is not null then
    new.actual_minutes := v;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 1日の目標時間と、Claude からのひとこと
-- ---------------------------------------------------------------------
alter table public.days
  add column if not exists target_minutes integer check (target_minutes is null or target_minutes between 0 and 1440);
alter table public.days
  add column if not exists coach_note text;
comment on column public.days.target_minutes is 'その日の勉強の目標時間(分)。null なら 平日240分・土日480分';
comment on column public.days.coach_note is 'Claude からのひとこと(前日の反省への返事・その日の注意点など)。アプリの目標の下に出る';

-- ---------------------------------------------------------------------
-- 4. 長期の目標(「今日」の上の帯: 試験まで○日・累計○時間 / 3000時間)
-- ---------------------------------------------------------------------
create table if not exists public.study_targets (
  user_id          uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  target_name      text not null default '論文式試験',   -- 例 論文式試験
  target_date      date,                                -- 例 2027-08-01
  total_hours_goal integer not null default 3000 check (total_hours_goal > 0),
  hours_before_app numeric not null default 0 check (hours_before_app >= 0),  -- アプリを使う前に勉強した時間
  updated_at       timestamptz not null default now()
);
comment on table public.study_targets is '長期の目標(1人1行)。Claude が書き、アプリは読むだけ';

drop trigger if exists study_targets_set_updated_at on public.study_targets;
create trigger study_targets_set_updated_at before update on public.study_targets
  for each row execute function public.set_updated_at();

revoke all on public.study_targets from anon;
grant select on public.study_targets to authenticated;
alter table public.study_targets enable row level security;
drop policy if exists "study_targets: 自分の行だけ読める" on public.study_targets;
create policy "study_targets: 自分の行だけ読める" on public.study_targets for select to authenticated
  using ((select auth.uid()) = user_id);

-- 累計の勉強時間(分)。生活の時間(科目「生活」)は入れない
create or replace function public.study_total_minutes()
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(minutes), 0) from public.study_sessions where subject <> '生活';
$$;
revoke all on function public.study_total_minutes() from public, anon;
grant execute on function public.study_total_minutes() to authenticated;

-- ---------------------------------------------------------------------
-- 5. 答練の成績と振り返り
-- ---------------------------------------------------------------------
create table if not exists public.exam_results (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  exam_date     date not null,                 -- 受ける(受けた)日
  start_time    time,                          -- 始まる時刻(例 09:00)
  subject       text not null default 'その他', -- 例 鑑定理論
  title         text not null check (length(trim(title)) > 0),  -- 例 応用答練 第3回
  score         numeric,                       -- 点数(まだ受けていなければ null)
  full_score    numeric,                       -- 満点(例 100)
  average       numeric,                       -- 平均点
  rank          integer,                       -- 順位
  examinees     integer,                       -- 受験者数
  good_points   text,                          -- 良かった点
  missed_points text,                          -- 論点漏れ・できなかった点
  next_actions  text,                          -- 次にやること
  note          text,
  source        text not null default 'claude' check (source in ('claude', 'app')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, exam_date, subject, title)
);
comment on table public.exam_results is '答練(模試)の予定・成績・振り返り。Claude もアプリも書く';

drop trigger if exists exam_results_set_updated_at on public.exam_results;
create trigger exam_results_set_updated_at before update on public.exam_results
  for each row execute function public.set_updated_at();

revoke all on public.exam_results from anon;
grant select, insert, update, delete on public.exam_results to authenticated;
alter table public.exam_results enable row level security;
drop policy if exists "exam_results: 自分の行だけ" on public.exam_results;
create policy "exam_results: 自分の行だけ" on public.exam_results for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 答練を消す(消した数を返す)。Claude がコネクタから select で呼べるように
create or replace function public.remove_exam_result(p_user_id uuid, p_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.exam_results where user_id = p_user_id and id = p_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.remove_exam_result(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. 週のやることと、日の予定をつなぐ
--    予定(items)の week_goal_title に週のやることの題名を入れておくと、
--    その予定をチェックしたときに、その週のやることの箱が1つ自動で埋まる(外すと1つ戻る)
-- ---------------------------------------------------------------------
alter table public.items
  add column if not exists week_goal_title text;
comment on column public.items.week_goal_title is
  'つながっている週のやること(week_goals.title)。チェックすると、その週の箱が1つ埋まる';

create or replace function public.items_fill_week_goal()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  g        record;
  v_dow    integer := extract(isodow from new.date)::integer;        -- 1 = 月 … 7 = 日
  v_monday date    := new.date - (extract(isodow from new.date)::integer - 1);
  v_day    text    := (array['月','火','水','木','金','土','日'])[extract(isodow from new.date)::integer];
  v_box    integer;
begin
  select * into g from public.week_goals
  where user_id = new.user_id and week_start = v_monday and title = new.week_goal_title
  order by sort_order limit 1;
  if not found then
    return null;
  end if;

  if new.done then
    -- まだの箱のうち、その日の曜日の箱(名前が同じ、または7つで名前の無い箱の同じ曜日)を先に、無ければ小さい番号から
    select b into v_box
    from generate_series(1, g.target_count) as b
    where not (b = any (g.done_boxes))
    order by case
               when b <= cardinality(g.box_labels) and g.box_labels[b] = v_day then 0
               when g.target_count = 7 and b = v_dow
                    and (b > cardinality(g.box_labels) or coalesce(g.box_labels[b], '') = '') then 0
               else 1
             end, b
    limit 1;
    if v_box is not null then
      update public.week_goals set done_boxes = array_append(done_boxes, v_box) where id = g.id;
    end if;
  else
    -- チェックを外したら、その日の曜日の箱を先に、無ければいちばん大きい番号の箱を1つ戻す
    select b into v_box
    from unnest(g.done_boxes) as b
    order by case
               when b <= cardinality(g.box_labels) and g.box_labels[b] = v_day then 0
               when g.target_count = 7 and b = v_dow
                    and (b > cardinality(g.box_labels) or coalesce(g.box_labels[b], '') = '') then 0
               else 1
             end, b desc
    limit 1;
    if v_box is not null then
      update public.week_goals set done_boxes = array_remove(done_boxes, v_box) where id = g.id;
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists items_fill_week_goal on public.items;
create trigger items_fill_week_goal after update of done on public.items
  for each row
  when (old.done is distinct from new.done and new.week_goal_title is not null)
  execute function public.items_fill_week_goal();

-- replace_plan: p_items の各行で "goal": "週のやることの題名" も受け取る(ほかは前と同じ)
create or replace function public.replace_plan(
  p_user_id uuid,
  p_date    date,
  p_goal    text,
  p_items   jsonb
)
returns table (deleted_count integer, inserted_count integer)
language plpgsql
set search_path = ''
as $$
declare
  v_today    date := (now() at time zone 'Asia/Tokyo')::date;
  v_deleted  integer;
  v_inserted integer;
begin
  if p_date < v_today then
    raise exception '過去の日付(%)は入れ直せません。今日(%)以降の日付を指定してください。', p_date, v_today;
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'user_id が見つかりません: %', p_user_id;
  end if;

  if p_goal is not null then
    insert into public.days (user_id, date, goal)
    values (p_user_id, p_date, p_goal)
    on conflict (user_id, date) do update set goal = excluded.goal;
  end if;

  delete from public.items
  where user_id = p_user_id and date = p_date and source = 'claude' and done = false;
  get diagnostics v_deleted = row_count;

  insert into public.items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note, steps, cautions, week_goal_title)
  select p_user_id, p_date, x.kind, x.start_time, x.end_time, x.title,
         coalesce(nullif(x.subject, ''), 'その他'), coalesce(x.sort_order, 0), x.note,
         coalesce(x.steps, '[]'::jsonb), coalesce(x.cautions, '[]'::jsonb),
         nullif(trim(coalesce(x.goal, '')), '')   -- つながる週のやることの題名
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
       as x(kind text, start_time time, end_time time, title text, subject text,
            sort_order integer, note text, steps jsonb, cautions jsonb, goal text);
  get diagnostics v_inserted = row_count;

  return query select v_deleted, v_inserted;
end;
$$;

revoke all on function public.replace_plan(uuid, date, text, jsonb) from public, anon, authenticated;
