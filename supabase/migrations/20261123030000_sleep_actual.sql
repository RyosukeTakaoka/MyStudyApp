-- =====================================================================
-- 睡眠の実測(タイマーで測った、実際に寝た時間)
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ。2回実行しても大丈夫です)
--         20261123020000_goal_boxes_month_plans.sql のあとに実行してください。
--
-- アプリで睡眠の予定を長押ししてタイマーを始めると、その区間が study_sessions に
-- (item_id = 睡眠の id、科目「生活」)記録されます。ここでは、それを合計して sleep_plans.actual_minutes に入れます。
-- =====================================================================

alter table public.sleep_plans
  add column if not exists actual_minutes integer check (actual_minutes is null or actual_minutes >= 0);
comment on column public.sleep_plans.actual_minutes is
  '実際に寝た時間(分)。アプリのタイマーの区間からサーバーが計算する(重なりは1回だけ)';

-- 区間が増えたときにサーバーの自動の処理が書きこめるように、実測の列だけ書きかえを許す(自分の行だけ)
grant update (actual_minutes) on public.sleep_plans to authenticated;
drop policy if exists "sleep_plans: 自分の行の実測だけ書ける" on public.sleep_plans;
create policy "sleep_plans: 自分の行の実測だけ書ける" on public.sleep_plans for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 区間が増えた・変わった・消えたら、予定の実績と睡眠の実測を計算し直す(前の処理に、睡眠を足したもの)
create or replace function public.study_sessions_touch_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    update public.items set actual_minutes = coalesce(public.session_minutes(old.item_id), actual_minutes)
    where id = old.item_id;
    -- 睡眠の実測も計算し直す
    update public.sleep_plans set actual_minutes = public.session_minutes(old.item_id)
    where id = old.item_id;
    return null;
  end if;
  update public.items set actual_minutes = coalesce(public.session_minutes(new.item_id), actual_minutes)
  where id = new.item_id;
  -- 睡眠のタイマー(item_id が睡眠の id)なら、睡眠の実測を計算し直す
  update public.sleep_plans set actual_minutes = public.session_minutes(new.item_id)
  where id = new.item_id;
  if tg_op = 'UPDATE' and old.item_id is distinct from new.item_id then
    update public.items set actual_minutes = coalesce(public.session_minutes(old.item_id), actual_minutes)
    where id = old.item_id;
    update public.sleep_plans set actual_minutes = public.session_minutes(old.item_id)
    where id = old.item_id;
  end if;
  return null;
end;
$$;

-- これまでの睡眠のタイマーの分も計算する
update public.sleep_plans set actual_minutes = public.session_minutes(id)
where exists (select 1 from public.study_sessions s where s.item_id = sleep_plans.id);
