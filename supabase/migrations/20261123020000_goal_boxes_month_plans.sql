-- =====================================================================
-- 予定と週の箱を1つずつ結びつける + 月ごとの勉強時間の配分
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ。2回実行しても大丈夫です)
--         20261123000000_plan_actual_exams.sql と 20261123010000_exam_study_total.sql のあとに実行してください。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 予定が埋める週の箱を、1つずつ決める
--    items.week_goal_boxes = 箱に出る番号(問題番号があれば問題番号)。例 数学178 の予定 → {178}
--    空なら今までどおり(その曜日の箱 → 空いているいちばん小さい番号の箱)
-- ---------------------------------------------------------------------
alter table public.items
  add column if not exists week_goal_boxes integer[] not null default '{}';
comment on column public.items.week_goal_boxes is
  'この予定が埋める週の箱(箱に出る番号。問題番号の始まり box_start があれば問題番号)。空なら自動で選ぶ';

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
  v_boxes  integer[];
begin
  select * into g from public.week_goals
  where user_id = new.user_id and week_start = v_monday and title = new.week_goal_title
  order by sort_order limit 1;
  if not found then
    return null;
  end if;

  -- 予定に「どの箱か」(week_goal_boxes)が決めてあれば、その箱だけを埋める・戻す。
  -- 数は箱に出る番号(問題番号の始まり box_start があれば問題番号。例 178)。範囲の外の数は無視する
  if coalesce(cardinality(new.week_goal_boxes), 0) > 0 then
    select coalesce(array_agg(distinct n - coalesce(g.box_start, 1) + 1), '{}') into v_boxes
    from unnest(new.week_goal_boxes) as n
    where n - coalesce(g.box_start, 1) + 1 between 1 and g.target_count;
    if cardinality(v_boxes) = 0 then
      return null;
    end if;
    if new.done then
      update public.week_goals
      set done_boxes = (select array_agg(distinct b) from unnest(done_boxes || v_boxes) as b)
      where id = g.id;
    else
      update public.week_goals
      set done_boxes = coalesce((select array_agg(b) from unnest(done_boxes) as b where not (b = any (v_boxes))), '{}')
      where id = g.id;
    end if;
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

-- replace_plan: p_items の各行で "goal_boxes": [178] も受け取る(ほかは前と同じ)
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

  insert into public.items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note, steps, cautions, week_goal_title, week_goal_boxes)
  select p_user_id, p_date, x.kind, x.start_time, x.end_time, x.title,
         coalesce(nullif(x.subject, ''), 'その他'), coalesce(x.sort_order, 0), x.note,
         coalesce(x.steps, '[]'::jsonb), coalesce(x.cautions, '[]'::jsonb),
         nullif(trim(coalesce(x.goal, '')), ''),  -- つながる週のやることの題名
         coalesce(x.goal_boxes, '{}')              -- その予定が埋める箱(箱に出る番号。例 {178} や {176,177})
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
       as x(kind text, start_time time, end_time time, title text, subject text,
            sort_order integer, note text, steps jsonb, cautions jsonb, goal text, goal_boxes integer[]);
  get diagnostics v_inserted = row_count;

  return query select v_deleted, v_inserted;
end;
$$;

revoke all on function public.replace_plan(uuid, date, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 月ごとの勉強時間の配分(Claude が決める)
--    例 2026-12 は 250時間、2027-01 は 300時間 …
--    アプリの帯の「今月あと」「1日あたり」と月の目盛りが、この配分どおりになる。
--    配分の無い月は、残りの時間を等分する
-- ---------------------------------------------------------------------
create table if not exists public.study_month_plans (
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  month         date not null check (extract(day from month) = 1),   -- その月の1日(例 2026-12-01)
  planned_hours numeric not null check (planned_hours >= 0),        -- その月に勉強する時間(鑑定士の勉強)
  note          text,
  updated_at    timestamptz not null default now(),
  primary key (user_id, month)
);
comment on table public.study_month_plans is '月ごとの勉強時間の配分(鑑定士の勉強)。Claude が書き、アプリは読むだけ';

drop trigger if exists study_month_plans_set_updated_at on public.study_month_plans;
create trigger study_month_plans_set_updated_at before update on public.study_month_plans
  for each row execute function public.set_updated_at();

revoke all on public.study_month_plans from anon;
grant select on public.study_month_plans to authenticated;
alter table public.study_month_plans enable row level security;
drop policy if exists "study_month_plans: 自分の行だけ読める" on public.study_month_plans;
create policy "study_month_plans: 自分の行だけ読める" on public.study_month_plans for select to authenticated
  using ((select auth.uid()) = user_id);

-- その日(日本時間の 0:00)からあとの、鑑定士の勉強時間(分)。今月どれだけ進んだかに使う
create or replace function public.study_minutes_since(p_from date)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(minutes), 0) from public.study_sessions
  where public.is_exam_study(subject, title)
    and started_at >= (p_from::timestamp at time zone 'Asia/Tokyo');
$$;
revoke all on function public.study_minutes_since(date) from public, anon;
grant execute on function public.study_minutes_since(date) to authenticated;
