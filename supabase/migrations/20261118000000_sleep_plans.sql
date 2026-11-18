-- =====================================================================
-- 睡眠の予定(sleep_plans)
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
-- 寝る時刻・起きる時刻を、1晩に1行で置く場所です。
--   ・アプリの画面には出しません(予定の一覧・ウィジェット・進み具合には入らない)
--   ・カレンダー連携をオンにしていると、iPhone の「MyStudy」カレンダーに「睡眠」として書き出します
--   ・夜中の0時をまたいでも1行で書けます(例 22:45〜翌6:30)
-- 書きこむのは Claude(別のチャット)で、下の upsert_sleep 関数を使います。
-- =====================================================================

create table public.sleep_plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  night       date not null,          -- その夜の日付(例 11/18 の夜に寝て 11/19 の朝に起きる → 2026-11-18)
  start_at    timestamptz not null,   -- 寝る時刻
  end_at      timestamptz not null,   -- 起きる時刻
  note        text,                   -- メモ(例: 睡眠不足を取り返す)
  source      text not null default 'claude' check (source in ('claude', 'app')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, night),
  constraint sleep_plans_order check (end_at > start_at),
  constraint sleep_plans_length check (end_at - start_at <= interval '16 hours')
);

comment on table public.sleep_plans is '睡眠の予定。1晩に1行。アプリの画面には出さず、カレンダーにだけ書き出す';

create trigger sleep_plans_set_updated_at before update on public.sleep_plans
  for each row execute function public.set_updated_at();

-- アプリは読むだけ(書きこむのは Claude が関数で行う)
revoke all on public.sleep_plans from anon;
grant select on public.sleep_plans to authenticated;
alter table public.sleep_plans enable row level security;
create policy "sleep_plans: 自分の行だけ読める" on public.sleep_plans for select to authenticated
  using ((select auth.uid()) = user_id);

-- 睡眠の予定を入れる/書きかえる(同じ夜があれば上書き)。時刻は日本時間の "HH:MM"。
--   ・寝る時刻が 12:00 より前(例 00:30)なら、その夜の次の日の 0:30 とみなす
--   ・起きる時刻が寝る時刻より前なら、次の日の朝とみなす
-- 例: select public.upsert_sleep('<user_id>', '2026-11-18', '22:45', '06:30', '睡眠不足を取り返す');
create or replace function public.upsert_sleep(
  p_user_id uuid, p_night date, p_start time, p_end time, p_note text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
  v_id    uuid;
begin
  -- 日付 + 時刻 を、日本時間として時刻(timestamptz)にする
  v_start := (p_night + p_start) at time zone 'Asia/Tokyo';
  if p_start < time '12:00' then
    v_start := v_start + interval '1 day';
  end if;
  v_end := (p_night + p_end) at time zone 'Asia/Tokyo';
  while v_end <= v_start loop
    v_end := v_end + interval '1 day';
  end loop;

  insert into public.sleep_plans (user_id, night, start_at, end_at, note)
  values (p_user_id, p_night, v_start, v_end, nullif(trim(coalesce(p_note, '')), ''))
  on conflict (user_id, night) do update set
    start_at = excluded.start_at, end_at = excluded.end_at, note = excluded.note, source = 'claude'
  returning id into v_id;
  return v_id;
end;
$$;

-- 睡眠の予定を消す(消した数を返す)
create or replace function public.remove_sleep(p_user_id uuid, p_night date)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.sleep_plans where user_id = p_user_id and night = p_night;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.upsert_sleep(uuid, date, time, time, text) from public, anon, authenticated;
revoke all on function public.remove_sleep(uuid, date) from public, anon, authenticated;
