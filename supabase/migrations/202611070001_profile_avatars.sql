create table if not exists public.profile_avatars (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  image_data text not null,
  updated_at timestamptz not null default now(),
  constraint profile_avatars_image_data_size check (char_length(image_data) <= 400000)
);

alter table public.profile_avatars enable row level security;
revoke all on public.profile_avatars from anon, authenticated;

create or replace function public.app_profile_avatar_get(p_token uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare a accounts; v_image text;
begin
  a := bm_auth(p_token);
  select image_data into v_image
    from profile_avatars
   where account_id = a.id;
  return v_image;
end;
$$;

create or replace function public.app_profile_avatar_set(p_token uuid, p_image_data text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare a accounts;
begin
  a := bm_auth(p_token);
  if p_image_data is null or btrim(p_image_data) = '' then
    delete from profile_avatars where account_id = a.id;
    return jsonb_build_object('ok', true, 'removed', true);
  end if;

  if char_length(p_image_data) > 400000
     or p_image_data !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'فایل تصویر معتبر نیست یا حجم آن بیش از حد مجاز است';
  end if;

  insert into profile_avatars(account_id, image_data, updated_at)
  values (a.id, p_image_data, now())
  on conflict (account_id) do update
    set image_data = excluded.image_data,
        updated_at = now();

  return jsonb_build_object('ok', true, 'removed', false);
end;
$$;

revoke all on function public.app_profile_avatar_get(uuid) from public;
revoke all on function public.app_profile_avatar_set(uuid, text) from public;
grant execute on function public.app_profile_avatar_get(uuid) to anon, authenticated;
grant execute on function public.app_profile_avatar_set(uuid, text) to anon, authenticated;
