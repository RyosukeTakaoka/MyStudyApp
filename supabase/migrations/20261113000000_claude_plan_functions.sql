-- =====================================================================
-- Claude(別のチャット)が予定を「入れ直す」「消す」ための関数
--
-- なぜ必要か:
--   チャットの Claude から DELETE 文を直接実行すると、Supabase のコネクタは
--   「本当に消してよいか」の確認を求めます。ところが claude.ai のチャットでは
--   その確認ボタンが表示されないことがあり、予定を消せませんでした。
--   そこで、消してよい行だけを消す「専用の関数」を用意し、
--   Claude は SELECT 文でこの関数を呼ぶようにします。
--
-- この関数が守るルール(関数の中で強制されるので、Claude がまちがえても破られない):
--   ・消すのは source = 'claude' かつ done = false(未チェック)の行だけ
--   ・過去の日付は変更できない(今日と未来だけ)
--   ・アプリ(ログイン中のユーザー)からは呼べない。管理者権限(コネクタ・SQL Editor)専用
--
-- 使い方: Supabase の SQL Editor にこのファイルの中身を全部貼り付けて「Run」(1回だけ)
-- =====================================================================

-- 1日の予定をまるごと入れ直す
--   p_items の例: '[{"kind":"block","start_time":"16:30","end_time":"17:30",
--                   "title":"Anki 鑑定評価基準","subject":"鑑定理論","sort_order":10}]'
--   p_goal が null のときは、目標を変えない
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

  -- Claude が入れた・未チェックの行だけを消す(チェック済みと手入力は残る)
  delete from public.items
  where user_id = p_user_id
    and date = p_date
    and source = 'claude'
    and done = false;
  get diagnostics v_deleted = row_count;

  insert into public.items (user_id, date, kind, start_time, end_time, title, subject, sort_order, note)
  select p_user_id, p_date, x.kind, x.start_time, x.end_time, x.title,
         coalesce(nullif(x.subject, ''), 'その他'), coalesce(x.sort_order, 0), x.note
  from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb))
       as x(kind text, start_time time, end_time time, title text, subject text, sort_order integer, note text);
  get diagnostics v_inserted = row_count;

  return query select v_deleted, v_inserted;
end;
$$;

-- 予定を id を指定して消す(消せるのは Claude が入れた・未チェック・今日以降の行だけ)
-- 戻り値: 実際に消した行の数
create or replace function public.remove_plan_items(
  p_user_id uuid,
  p_ids     uuid[]
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.items
  where user_id = p_user_id
    and id = any (p_ids)
    and source = 'claude'
    and done = false
    and date >= (now() at time zone 'Asia/Tokyo')::date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- アプリ(anon / authenticated)からは呼べないようにする
revoke all on function public.replace_plan(uuid, date, text, jsonb) from public, anon, authenticated;
revoke all on function public.remove_plan_items(uuid, uuid[]) from public, anon, authenticated;
