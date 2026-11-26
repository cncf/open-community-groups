-- Tests checking whether a password-reset notification still matches an active reset token.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set userActiveID '0a190000-0000-0000-0000-000000000001'
\set userExpiredID '0a190000-0000-0000-0000-000000000002'
\set userNoTokenID '0a190000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- User holding an active password reset token
select fx_user(:'userActiveID');

-- User holding an expired password reset token
select fx_user(:'userExpiredID');

-- User with no password reset token
select fx_user(:'userNoTokenID');

-- Active password reset token created 10 minutes ago
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a19-active', 'sha256'),
    current_timestamp - interval '10 minutes',
    :'userActiveID'
);

-- Expired password reset token sitting at the 1-hour validity boundary
insert into password_reset_token (token_hash, created_at, user_id)
values (
    digest('0a19-expired', 'sha256'),
    current_timestamp - interval '1 hour',
    :'userExpiredID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false when the user has no token
select is(
    is_password_reset_notification_active(:'userNoTokenID'::uuid, current_timestamp),
    false,
    'Should return false when the user has no token'
);

-- Should return false when the stored token has expired
select is(
    is_password_reset_notification_active(:'userExpiredID'::uuid, current_timestamp),
    false,
    'Should return false when the stored token has expired'
);

-- Should return false when a newer token superseded the notification
select is(
    is_password_reset_notification_active(
        :'userActiveID'::uuid,
        current_timestamp - interval '15 minutes'
    ),
    false,
    'Should return false when a newer token superseded the notification'
);

-- Should return true when an unexpired token matches the notification timestamp
select is(
    is_password_reset_notification_active(
        :'userActiveID'::uuid,
        current_timestamp - interval '10 minutes'
    ),
    true,
    'Should return true when an unexpired token matches the notification timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
