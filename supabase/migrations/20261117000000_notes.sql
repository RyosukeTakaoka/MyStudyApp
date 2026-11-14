-- =====================================================================
-- 資料(ノート)ページ
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ)
--
-- 予定ではない読み物(教科書の置き場所のルール、忙しい時期の最低ライン、計画の説明など)を
-- Markdown で置く場所です。アプリの「資料」タブに一覧で出ます。
-- 本文の中の「- [ ] 〜」は、アプリでチェックできます。
-- =====================================================================

create table public.notes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  slug        text not null check (slug ~ '^[a-z0-9][a-z0-9-]*$'),  -- 英小文字・数字・ハイフンの名前(例: textbook-places)
  title       text not null check (length(trim(title)) > 0),
  category    text not null default 'その他',                       -- 方針 / ルール / 答練 / Anki / その他 など
  body_md     text not null default '',                              -- 本文(Markdown)
  pinned      boolean not null default false,                        -- 一覧のいちばん上に出す
  sort_order  integer not null default 0,
  source      text not null default 'claude' check (source in ('claude', 'app')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, slug)
);

create trigger notes_set_updated_at before update on public.notes
  for each row execute function public.set_updated_at();

revoke all on public.notes from anon;
grant select, insert, update, delete on public.notes to authenticated;
alter table public.notes enable row level security;
create policy "notes: 自分の行だけ" on public.notes for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 資料を入れる/書きかえる(同じ slug があれば上書き)。p_sort_order を省略すると 0
create or replace function public.upsert_note(
  p_user_id uuid, p_slug text, p_title text, p_category text, p_body_md text,
  p_pinned boolean default false, p_sort_order integer default 0
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.notes (user_id, slug, title, category, body_md, pinned, sort_order)
  values (p_user_id, p_slug, p_title, coalesce(nullif(p_category, ''), 'その他'),
          coalesce(p_body_md, ''), coalesce(p_pinned, false), coalesce(p_sort_order, 0))
  on conflict (user_id, slug) do update set
    title = excluded.title, category = excluded.category, body_md = excluded.body_md,
    pinned = excluded.pinned, sort_order = excluded.sort_order
  returning id into v_id;
  return v_id;
end;
$$;

-- 資料を消す(消した数を返す)
create or replace function public.remove_note(p_user_id uuid, p_slug text)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.notes where user_id = p_user_id and slug = p_slug;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.upsert_note(uuid, text, text, text, text, boolean, integer) from public, anon, authenticated;
revoke all on function public.remove_note(uuid, text) from public, anon, authenticated;
