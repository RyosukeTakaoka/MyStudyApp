-- =====================================================================
-- タイマーの記録(いつ始めて、いつ止めたか)
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
-- タイマーを「始める(再開する)→ 一時停止・終了する」までを1区間として、1行ずつ記録します。
-- 例: 16:30 開始 → 16:50 一時停止 → 17:00 再開 → 17:25 完了 なら、2行になる
-- =====================================================================

create table public.study_sessions (
  id          uuid primary key,                 -- アプリが決める(送り直しても二重にならないように)
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id     uuid,                             -- どの予定のタイマーか(予定が消えても記録は残すので、つながりは付けない)
  item_date   date,                             -- その予定の日付
  title       text not null,                    -- その時点の予定の題名(予定が消えても読めるように写しておく)
  subject     text not null default 'その他',
  started_at  timestamptz not null,             -- 始めた(再開した)時刻
  ended_at    timestamptz not null,             -- 止めた時刻
  -- 止めた理由: pause = 一時停止 / stop = 記録して終了 / done = 完了 / auto = 予定の終了時刻で自動終了
  --             switch = 長押しで別の予定のタイマーに切りかえた
  end_reason  text not null check (end_reason in ('pause', 'stop', 'done', 'auto', 'switch')),
  -- この区間の長さ(分)。自動で計算される
  minutes     numeric generated always as (round(extract(epoch from (ended_at - started_at)) / 60.0, 1)) stored,
  created_at  timestamptz not null default now(),
  check (ended_at >= started_at)
);

create index study_sessions_user_started_idx on public.study_sessions (user_id, started_at);
create index study_sessions_user_item_idx on public.study_sessions (user_id, item_id);

comment on table public.study_sessions is 'タイマーの区間ごとの記録。アプリが書き込む。Claude は読むだけにすること';

revoke all on public.study_sessions from anon;
grant select, insert, update, delete on public.study_sessions to authenticated;
alter table public.study_sessions enable row level security;
create policy "study_sessions: 自分の行だけ" on public.study_sessions for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
