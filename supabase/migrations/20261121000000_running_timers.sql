-- =====================================================================
-- 動いているタイマーを、iPhone と iPad で共有する + 予定の実績を区間から計算する
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
-- 1. running_timers: 今動いている(一時停止中もふくむ)タイマー。予定1つにつき1行。
--    アプリが始める・一時停止・再開・終了のたびに書きかえ、ほかの端末が読んで同じタイマーを出す。
-- 2. items.actual_minutes(実績)を、タイマーの区間(study_sessions)から、重なりを1回だけ数えて計算する。
--    端末が古い数で上書きしても、サーバーが区間から計算し直すので、記録が消えたり二重になったりしない。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 動いているタイマー
-- ---------------------------------------------------------------------
create table public.running_timers (
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id             uuid not null,                       -- どの予定のタイマーか
  item_date           date,                                -- その予定の日付
  title               text not null,
  subject             text not null default 'その他',
  started_at          timestamptz not null,                -- 今の区間を始めた(再開した)時刻
  accumulated_seconds double precision not null default 0, -- 一時停止までに測った秒数の合計
  paused_at           timestamptz,                         -- 一時停止した時刻(動いているときは null)
  prior_seconds       double precision not null default 0, -- 始める前にすでに記録してあった秒数(表示用)
  planned_end         timestamptz,                         -- 予定の終了時刻
  is_auto             boolean not null default false,      -- 自動タイマーで始まったか
  updated_at          timestamptz not null default now(),
  primary key (user_id, item_id)
);

comment on table public.running_timers is '動いているタイマー(端末どうしで共有)。アプリが書きこむ。Claude は読むだけにすること';

create trigger running_timers_set_updated_at before update on public.running_timers
  for each row execute function public.set_updated_at();

revoke all on public.running_timers from anon;
grant select, insert, update, delete on public.running_timers to authenticated;
alter table public.running_timers enable row level security;
create policy "running_timers: 自分の行だけ" on public.running_timers for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- 2. 予定の実績を、タイマーの区間から計算する
-- ---------------------------------------------------------------------
create index if not exists study_sessions_item_idx on public.study_sessions (item_id);

-- その予定の区間の合計(分)。重なっている区間(2台で同時に測ったなど)は1回だけ数える。区間が無ければ null
create or replace function public.session_minutes(p_item_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  with ordered as (
    select started_at, ended_at,
           max(ended_at) over (order by started_at, ended_at
                               rows between unbounded preceding and 1 preceding) as prev_end
    from public.study_sessions
    where item_id = p_item_id
  ), grouped as (
    -- 前の区間の終わりより後に始まったら、新しいかたまり
    select started_at, ended_at,
           sum(case when prev_end is null or started_at > prev_end then 1 else 0 end)
             over (order by started_at, ended_at) as grp
    from ordered
  ), merged as (
    select min(started_at) as s, max(ended_at) as e from grouped group by grp
  )
  select case when count(*) = 0 then null
              else round(sum(extract(epoch from (e - s))) / 60.0)::integer end
  from merged;
$$;

-- 予定を入れる・書きかえるとき、区間があれば、実績は区間から計算した値にする(端末が送った数は使わない)
create or replace function public.items_actual_from_sessions()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v integer;
begin
  v := public.session_minutes(new.id);
  if v is not null then
    new.actual_minutes := v;
  end if;
  return new;
end;
$$;

create trigger items_actual_from_sessions before insert or update on public.items
  for each row execute function public.items_actual_from_sessions();

-- 区間が増えた・変わった・消えたら、その予定の実績を計算し直す
create or replace function public.study_sessions_touch_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    update public.items set actual_minutes = coalesce(public.session_minutes(old.item_id), actual_minutes)
    where id = old.item_id;
    return null;
  end if;
  update public.items set actual_minutes = coalesce(public.session_minutes(new.item_id), actual_minutes)
  where id = new.item_id;
  if tg_op = 'UPDATE' and old.item_id is distinct from new.item_id then
    update public.items set actual_minutes = coalesce(public.session_minutes(old.item_id), actual_minutes)
    where id = old.item_id;
  end if;
  return null;
end;
$$;

create trigger study_sessions_touch_item after insert or update or delete on public.study_sessions
  for each row execute function public.study_sessions_touch_item();

-- これまでの記録も、区間から計算し直す(上書きで消えていた分が戻る)
update public.items set actual_minutes = actual_minutes
where id in (select distinct item_id from public.study_sessions where item_id is not null);
