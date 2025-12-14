-- Seed data for Playwright E2E tests.
-- This creates a community, a group (`test-group`), and an event (`test-event`).

insert into community (
  community_id,
  active,
  description,
  display_name,
  header_logo_url,
  host,
  name,
  theme,
  title
) values (
  '11111111-1111-1111-1111-111111111111',
  true,
  'Test community for E2E',
  'Test Community',
  'https://example.com/logo.png',
  'localhost',
  'test-community',
  '{}'::jsonb,
  'Test Community'
) on conflict do nothing;

insert into group_category (
  group_category_id,
  community_id,
  name
) values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'General'
) on conflict do nothing;

insert into event_category (
  event_category_id,
  community_id,
  name,
  slug
) values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'General',
  'general'
) on conflict do nothing;

insert into "user" (
  user_id,
  auth_hash,
  community_id,
  email,
  email_verified,
  username,
  name,
  password
) values (
  '44444444-4444-4444-4444-444444444444',
  auth_hash gen_random_bytes(32),
  '11111111-1111-1111-1111-111111111111',
  'e2e@example.com',
  true,
  'e2e-user',
  'E2E User',
  '$argon2id$v=19$m=19456,t=2,p=1$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
) on conflict do nothing;

insert into "group" (
  group_id,
  community_id,
  group_category_id,
  name,
  slug
) values (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Test Group',
  'test-group'
) on conflict do nothing;

insert into event (
  event_id,
  description,
  event_category_id,
  event_kind_id,
  group_id,
  name,
  published,
  slug,
  timezone,
  published_at,
  published_by,
  starts_at,
  ends_at
) values (
  '66666666-6666-6666-6666-666666666666',
  'Test event for E2E',
  '33333333-3333-3333-3333-333333333333',
  'virtual',
  '55555555-5555-5555-5555-555555555555',
  'Test Event',
  true,
  'test-event',
  'UTC',
  current_timestamp,
  '44444444-4444-4444-4444-444444444444',
  current_timestamp + interval '1 day',
  current_timestamp + interval '1 day' + interval '2 hours'
) on conflict do nothing;

