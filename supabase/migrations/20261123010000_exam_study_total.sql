-- =====================================================================
-- 累計の勉強時間(3000時間の帯)を「鑑定士の勉強だけ」にする
--
-- 使い方: Supabase の SQL Editor で「+」を押して新しいタブを開き、
--         このファイルの中身を全部貼り付けて「Run」(1回だけ。2回実行しても大丈夫です)
--         20261123000000_plan_actual_exams.sql のあとに実行してください。
--
-- 前は「生活」だけを外していたので、学校の勉強(科目「学校」)も累計に入っていました。
-- これからは、学校の勉強と生活(食事・移動など)の両方を外します。
-- 見分け方は、アプリの「勉強かどうか」の決まりと同じです(題名の言葉も見る)。
-- =====================================================================

-- 鑑定士の勉強の区間か
--   ・科目が「学校」「生活」(と食事・休憩などの生活の科目)→ 入れない
--   ・科目が鑑定士の科目(鑑定理論・行政法規・民法・経済・会計)→ 入れる
--   ・科目が「その他」などのとき: 題名に Anki・勉強・復習・暗記・問題・答練・演習 があれば入れる。
--     食事・風呂・通学などの生活の言葉があれば入れない。どちらも無ければ入れる
create or replace function public.is_exam_study(p_subject text, p_title text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(trim(p_subject), '') in ('学校', '生活', '食事', '休憩', '睡眠', '移動', '自由', '風呂', '家事') then false
    when trim(p_subject) in ('鑑定理論', '行政法規', '民法', '経済', '会計') then true
    when coalesce(p_title, '') ~* '(anki|勉強|復習|暗記|問題|答練|演習)' then true
    when coalesce(p_title, '') ~ '(食事|朝食|昼食|夕食|夜食|朝ごはん|昼ごはん|夜ごはん|ご飯|ごはん|弁当|風呂|入浴|シャワー|睡眠|就寝|寝る|起床|昼寝|仮眠|休憩|移動|通学|登校|下校|帰宅|身支度|支度|自由時間|家事)' then false
    else true
  end;
$$;

-- 累計の勉強時間(分)。鑑定士の勉強だけ(学校・生活は入れない)
create or replace function public.study_total_minutes()
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(minutes), 0) from public.study_sessions
  where public.is_exam_study(subject, title);
$$;
revoke all on function public.study_total_minutes() from public, anon;
grant execute on function public.study_total_minutes() to authenticated;
