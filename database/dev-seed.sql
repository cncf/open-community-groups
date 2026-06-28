insert into site (site_id, title, description, theme)
values (
  '00000000-0000-0000-0000-000000000000',
  'GOUP Alliance',
  'dream. connect. achieve.',
  '{"primary_color":"#0EA5E9"}'
)
on conflict do nothing;

insert into alliance (
  alliance_id,
  name,
  display_name,
  description,
  banner_url,
  banner_mobile_url,
  logo_url
) values (
  '11111111-1111-1111-1111-111111111111',
  'goup',
  'GOUP Alliance',
  'dream. connect. achieve.',
  '/static/images/e2e/alliance-primary-banner.svg',
  '/static/images/e2e/alliance-primary-banner-mobile.svg',
  '/static/images/e2e/alliance-primary-logo.svg'
)
on conflict do nothing;

insert into group_category (group_category_id, alliance_id, name)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'General'
)
on conflict do nothing;

insert into "group" (
  group_id,
  alliance_id,
  group_category_id,
  name,
  slug,
  description
) values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'GOUP Baku',
  'goup-baku',
  'Default development group'
)
on conflict do nothing;

do $$
declare
  v_user_id uuid;
begin
  select user_id
  into v_user_id
  from "user"
  where lower(email) = 'team@goup.vc';

  if v_user_id is null then
    v_user_id := '44444444-4444-4444-4444-444444444444';

    insert into "user" (
      user_id,
      auth_hash,
      email,
      email_verified,
      username,
      name,
      bio,
      registration_status
    ) values (
      v_user_id,
      encode(gen_random_bytes(32), 'hex'),
      'team@goup.vc',
      true,
      'team-goup-chat-bot',
      'Team GOUP Chat Bot',
      'Automated GOUP team contact for member questions and support.',
      'registered'
    );
  end if;

  insert into group_member (group_id, user_id)
  values (
    '33333333-3333-3333-3333-333333333333',
    v_user_id
  )
  on conflict do nothing;
end $$;
