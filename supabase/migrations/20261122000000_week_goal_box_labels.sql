-- =====================================================================
-- 週のやることの箱に、名前(曜日など)を付けられるようにする
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
-- 例: 演習30分(毎日1回 + 金曜は2回)の8つの箱 → box_labels = {月,火,水,木,金,金,土,日}
-- アプリの「週・月」タブで「曜日」にすると、箱に番号の代わりにこの名前が出ます。
-- アプリで箱を長押しして、1つずつ曜日を付けることもできます。
-- 名前が無い箱は、箱がちょうど7つのやることなら自動で 月〜日、それ以外は番号で出ます。
-- =====================================================================

alter table public.week_goals
  add column if not exists box_labels text[] not null default '{}';

comment on column public.week_goals.box_labels is
  '箱ごとの名前(1つ目の箱から順に。例 {月,火,水,木,金,金,土,日})。足りない箱は番号で出る';

-- replace_week_plan を、p_goals の各行で "box_labels": ["月","火",…] も受け取れるようにする(ほかは前と同じ)。
-- box_labels を省略したやることは、前の名前(アプリで付けた名前)を残す。
-- (このファイルは2回実行しても大丈夫です)
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
  create temp table if not exists pg_temp.old_progress (group_name text, title text, done_boxes integer[], box_labels text[]) on commit drop;
  delete from pg_temp.old_progress;
  insert into pg_temp.old_progress
  select g.group_name, g.title, g.done_boxes, g.box_labels from public.week_goals g
  where g.user_id = p_user_id and g.week_start = p_week_start;

  delete from public.week_goals where user_id = p_user_id and week_start = p_week_start and source = 'claude';

  insert into public.week_goals (user_id, week_start, group_name, title, detail, target_count, done_boxes, box_labels, sort_order)
  select p_user_id, p_week_start,
         coalesce(nullif(x.group_name, ''), 'その他'), x.title, x.detail,
         coalesce(x.target_count, 1),
         coalesce(o.done_boxes, '{}'),   -- 箱が減った分は、トリガーが自動で捨てる
         -- 箱ごとの名前(例 曜日)。省略したら、前の名前(アプリで長押しして付けた名前など)を残す
         coalesce(x.box_labels, o.box_labels, '{}'),
         coalesce(x.sort_order, 0)
  from jsonb_to_recordset(coalesce(p_goals, '[]'::jsonb))
       as x(group_name text, title text, detail text, target_count integer, box_labels text[], sort_order integer)
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
