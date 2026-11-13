-- =====================================================================
-- 予定に「手順」と「注意」を書けるようにする + 終わりの時刻のない予定(例: 6:30 起きる)を許す
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
-- =====================================================================

-- 1. 手順と注意の列を足す(どちらも文字の配列。例: ["10分タイマーで解く", "答え合わせ"])
alter table public.items
  add column steps    jsonb not null default '[]'::jsonb check (jsonb_typeof(steps) = 'array'),
  add column cautions jsonb not null default '[]'::jsonb check (jsonb_typeof(cautions) = 'array');

comment on column public.items.steps    is '手順(文字の配列)。アプリで番号つきの一覧として表示する';
comment on column public.items.cautions is '注意(文字の配列)。アプリで箇条書きとして表示する';

-- 2. 時間つきの予定(block)は、開始時刻だけでもよいことにする(終了時刻は任意)
alter table public.items drop constraint items_time_matches_kind;
alter table public.items add constraint items_time_matches_kind check (
  (kind = 'block' and start_time is not null)
  or
  (kind = 'task' and start_time is null and end_time is null)
);
comment on column public.items.end_time is '終了時刻(日本時間)。block では任意(例: 起きる 6:30 だけ)、task は NULL';

-- 3. replace_plan で、手順と注意も入れられるようにする(引数は前と同じ)
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

  insert into public.items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note, steps, cautions)
  select p_user_id, p_date, x.kind, x.start_time, x.end_time, x.title,
         coalesce(nullif(x.subject, ''), 'その他'), coalesce(x.sort_order, 0), x.note,
         coalesce(x.steps, '[]'::jsonb), coalesce(x.cautions, '[]'::jsonb)
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
       as x(kind text, start_time time, end_time time, title text, subject text,
            sort_order integer, note text, steps jsonb, cautions jsonb);
  get diagnostics v_inserted = row_count;

  return query select v_deleted, v_inserted;
end;
$$;

revoke all on function public.replace_plan(uuid, date, text, jsonb) from public, anon, authenticated;
