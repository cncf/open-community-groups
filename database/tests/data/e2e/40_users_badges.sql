-- E2E seed: users and badges.
-- Depends on: 30_events.sql (groups and events for badge awards).

-- ============================================================================
-- USERS
-- Password: Password123!
-- Hash generated with Argon2id (password_auth crate default)
-- ============================================================================

insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777701',
    'e2e-admin-1',
    'e2e-admin-1@example.com',
    true,
    'E2E Admin One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'
), (
    '77777777-7777-7777-7777-777777777702',
    'e2e-admin-2',
    'e2e-admin-2@example.com',
    true,
    'E2E Admin Two',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3'
), (
    '77777777-7777-7777-7777-777777777703',
    'e2e-organizer-1',
    'e2e-organizer-1@example.com',
    true,
    'E2E Organizer One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'
), (
    '77777777-7777-7777-7777-777777777704',
    'e2e-organizer-2',
    'e2e-organizer-2@example.com',
    true,
    'E2E Organizer Two',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'd4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5'
), (
    '77777777-7777-7777-7777-777777777705',
    'e2e-member-1',
    'e2e-member-1@example.com',
    true,
    'E2E Member One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6'
), (
    '77777777-7777-7777-7777-777777777706',
    'e2e-member-2',
    'e2e-member-2@example.com',
    true,
    'E2E Member Two',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1'
), (
    '77777777-7777-7777-7777-777777777707',
    'e2e-pending-1',
    'e2e-pending-1@example.com',
    true,
    'E2E Pending One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b3'
), (
    '77777777-7777-7777-7777-777777777708',
    'e2e-pending-2',
    'e2e-pending-2@example.com',
    true,
    'E2E Pending Two',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c4'
), (
    '77777777-7777-7777-7777-777777777709',
    'e2e-groups-manager-1',
    'e2e-groups-manager-1@example.com',
    true,
    'E2E Groups Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'c4d5e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d5'
), (
    '77777777-7777-7777-7777-777777777710',
    'e2e-community-viewer-1',
    'e2e-community-viewer-1@example.com',
    true,
    'E2E Community Viewer One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'd5e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e6'
), (
    '77777777-7777-7777-7777-777777777711',
    'e2e-events-manager-1',
    'e2e-events-manager-1@example.com',
    true,
    'E2E Events Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'e6f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f7'
), (
    '77777777-7777-7777-7777-777777777712',
    'e2e-group-viewer-1',
    'e2e-group-viewer-1@example.com',
    true,
    'E2E Group Viewer One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'f7a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a2'
), (
    '77777777-7777-7777-7777-777777777713',
    'e2e-empty',
    'e2e-empty@example.com',
    true,
    'E2E Empty User',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'a8b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b3'
);

-- Member reserved for group members pagination coverage.
insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777714',
    'e2e-member-3',
    'e2e-member-3@example.com',
    true,
    'E2E Member Three',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'b9c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1c4d5'
);

-- Check-in manager reserved for scanner and manual check-in coverage.
insert into "user" (
    user_id, username, email, email_verified, name, password, auth_hash
) values (
    '77777777-7777-7777-7777-777777777715',
    'e2e-check-in-manager-1',
    'e2e-check-in-manager-1@example.com',
    true,
    'E2E Check-In Manager One',
    '$argon2id$v=19$m=19456,t=2,p=1$q55jlxUx8bffhFM3xN36ZA$te6OiWkZ/q35lpSEAZbd/A3iJyCByxbive9F61sTp7g',
    'cad4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3e6'
);

update "user"
set
    bio = 'Member Two profile for dashboard modal coverage.',
    company = 'Platform Ops Lab',
    github_url = 'https://github.com/e2e-member-2',
    provider = '{"linuxfoundation": {"username": "e2e-member-2-lf", "issuer": "private-member-issuer", "subject": "private-member-subject"}}'::jsonb,
    title = 'Member Experience Engineer',
    website_url = 'https://example.com/e2e-member-2'
where user_id = '77777777-7777-7777-7777-777777777706';

update "user"
set
    bio = 'Pending One profile for invitation request modal coverage.',
    company = 'Approval Queue',
    github_url = 'https://github.com/e2e-pending-1',
    provider = '{"linuxfoundation": {"username": "e2e-pending-1-lf", "issuer": "private-pending-issuer", "subject": "private-pending-subject"}}'::jsonb,
    title = 'Community Applicant',
    website_url = 'https://example.com/e2e-pending-1'
where user_id = '77777777-7777-7777-7777-777777777707';

-- Member One registers for events across specs; a complete profile keeps the
-- post-registration "complete your profile" prompt from covering the page.
update "user"
set
    bio = 'Member One profile for event registration coverage.',
    company = 'Platform Ops Lab',
    github_url = 'https://github.com/e2e-member-1',
    title = 'Platform Engineer',
    website_url = 'https://example.com/e2e-member-1'
where user_id = '77777777-7777-7777-7777-777777777705';

-- ============================================================================
-- BADGES
-- Reusable artwork and definitions for manual badge management testing
-- ============================================================================

-- Import the host badge image from the committed E2E assets
\lo_import 'ocg-server/static/images/e2e/badges/host.png'
\set hostBadgeImageOid :LASTOID

-- Host badge image stored by the database image provider
insert into images (
    file_name,
    content_type,
    created_by,
    data
) values (
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    'image/png',
    '77777777-7777-7777-7777-777777777703',
    lo_get(:hostBadgeImageOid)
);

-- Use a stored image for public Open Graph page and serving coverage.
update community
set og_image_url = '/images/7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png'
where community_id = '11111111-1111-1111-1111-111111111111';

-- Remove the temporary host image large object
\lo_unlink :hostBadgeImageOid

-- Import the speaker badge image from the committed E2E assets
\lo_import 'ocg-server/static/images/e2e/badges/speaker.png'
\set speakerBadgeImageOid :LASTOID

-- Speaker badge image stored by the database image provider
insert into images (
    file_name,
    content_type,
    created_by,
    data
) values (
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    'image/png',
    '77777777-7777-7777-7777-777777777703',
    lo_get(:speakerBadgeImageOid)
);

-- Remove the temporary speaker image large object
\lo_unlink :speakerBadgeImageOid

-- Disposable badge image copied from committed E2E artwork
insert into images (
    file_name,
    content_type,
    created_by,
    data
)
select
    'e2e-disposable-badge.png',
    content_type,
    created_by,
    data
from images
where file_name = '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png';

-- Removable gallery image copied from committed E2E artwork
insert into images (
    file_name,
    content_type,
    created_by,
    data
)
select
    'e2e-removable-badge.png',
    content_type,
    created_by,
    data
from images
where file_name = 'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png';

-- Host artwork available in the primary group gallery
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab01',
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Speaker artwork available in the primary group gallery
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab02',
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Disposable artwork used by isolated destructive badge scenarios
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab03',
    'e2e-disposable-badge.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Unreferenced artwork used by the removable gallery scenario
insert into badge_artwork (
    badge_artwork_id,
    file_name,
    group_id
) values (
    'abababab-abab-abab-abab-ababababab04',
    'e2e-removable-badge.png',
    '44444444-4444-4444-4444-444444444441'
);

-- Host badge definition available to the primary group
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab001',
    'Serve as a host for a Platform Ops Meetup event.',
    'Recognizes contributors who host Platform Ops Meetup events.',
    '44444444-4444-4444-4444-444444444441',
    '7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png',
    'Host'
);

-- Speaker badge definition available to the primary group
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab002',
    'Speak at a Platform Ops Meetup event.',
    'Recognizes contributors who speak at Platform Ops Meetup events.',
    '44444444-4444-4444-4444-444444444441',
    'eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png',
    'Speaker'
);

-- Mentor badge reserved for manager revocation coverage
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab003',
    'Mentor another Platform Ops Meetup contributor.',
    'Recognizes contributors who mentor other group members.',
    '44444444-4444-4444-4444-444444444441',
    'e2e-disposable-badge.png',
    'Mentor'
);

-- Volunteer badge reserved for self-revocation coverage
insert into badge (
    badge_id,
    criteria,
    description,
    group_id,
    image_file_name,
    name
) values (
    'babababa-baba-baba-baba-babababab004',
    'Volunteer for a Platform Ops Meetup activity.',
    'Recognizes contributors who volunteer for the group.',
    '44444444-4444-4444-4444-444444444441',
    'e2e-disposable-badge.png',
    'Volunteer'
);

-- Status list shared by the primary group's seeded badge awards
insert into badge_status_list (
    badge_status_list_id,
    allocation_offset,
    allocation_position,
    allocation_stride,
    group_id
) values (
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    8,
    1,
    '44444444-4444-4444-4444-444444444441'
);

-- Active Host badge awarded to the primary group's events manager
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '3 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    0,
    'dadadada-dada-dada-dada-dadadadada01',

    'babababa-baba-baba-baba-babababab001',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777711'
);

-- Active Speaker badge awarded to the primary group's events manager
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '2 days 12 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    1,
    'dadadada-dada-dada-dada-dadadadada05',

    'babababa-baba-baba-baba-babababab002',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777711'
);

-- Active Host badge awarded to the primary event's host
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '4 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    2,
    'dadadada-dada-dada-dada-dadadadada02',

    'babababa-baba-baba-baba-babababab001',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777703'
);

-- Active Host badge awarded to the primary event's featured speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '18 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Serve as a host for a Platform Ops Meetup event.",
        "description": "Recognizes contributors who host Platform Ops Meetup events.",
        "image_file_name": "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Host"
    }'::jsonb,
    3,
    'dadadada-dada-dada-dada-dadadadada06',

    'babababa-baba-baba-baba-babababab001',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777705'
);

-- Active Speaker badge awarded to the primary event's featured speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '2 days',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    4,
    'dadadada-dada-dada-dada-dadadadada03',

    'babababa-baba-baba-baba-babababab002',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777705'
);

-- Revoked Speaker badge retained for the primary event's second speaker
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '1 day',
    'cacacaca-caca-caca-caca-cacacacaca01',
    0,
    '44444444-4444-4444-4444-444444444441',
    false,
    '{
        "criteria": "Speak at a Platform Ops Meetup event.",
        "description": "Recognizes contributors who speak at Platform Ops Meetup events.",
        "image_file_name": "eba31486952cc567f080e2d52d0280c40e6c99da7dbad42c762d64b2f1ff9a32.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Speaker"
    }'::jsonb,
    5,
    'dadadada-dada-dada-dada-dadadadada04',

    'babababa-baba-baba-baba-babababab002',
    '55555555-5555-5555-5555-555555555501',
    'Award issued in error',
    now() - interval '12 hours',
    '77777777-7777-7777-7777-777777777703',
    '77777777-7777-7777-7777-777777777706'
);

-- Active Mentor badge reserved for manager revocation coverage
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '6 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    1,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Mentor another Platform Ops Meetup contributor.",
        "description": "Recognizes contributors who mentor other group members.",
        "image_file_name": "e2e-disposable-badge.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Mentor"
    }'::jsonb,
    6,
    'dadadada-dada-dada-dada-dadadadada07',

    'babababa-baba-baba-baba-babababab003',
    '55555555-5555-5555-5555-555555555501',
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777706'
);

-- Active Volunteer badge reserved for self-revocation coverage
insert into user_badge (
    awarded_at,
    badge_status_list_id,
    display_order,
    group_id,
    is_listed,
    snapshot,
    status_list_index,
    user_badge_id,

    badge_id,
    event_id,
    revocation_reason,
    revoked_at,
    revoked_by_user_id,
    user_id
) values (
    now() - interval '4 hours',
    'cacacaca-caca-caca-caca-cacacacaca01',
    2,
    '44444444-4444-4444-4444-444444444441',
    true,
    '{
        "criteria": "Volunteer for a Platform Ops Meetup activity.",
        "description": "Recognizes contributors who volunteer for the group.",
        "image_file_name": "e2e-disposable-badge.png",
        "issuer": {
            "community_id": "11111111-1111-1111-1111-111111111111",
            "community_name": "Platform Engineering Community",
            "group_id": "44444444-4444-4444-4444-444444444441",
            "group_name": "Platform Ops Meetup"
        },
        "name": "Volunteer"
    }'::jsonb,
    7,
    'dadadada-dada-dada-dada-dadadadada08',

    'babababa-baba-baba-baba-babababab004',
    null,
    null,
    null,
    null,
    '77777777-7777-7777-7777-777777777706'
);
