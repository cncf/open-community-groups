-- Tests loading the event, group and community rows of a checkout.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3020000-0000-0000-0000-000000000001'
\set eventCategoryID 'f3020000-0000-0000-0000-000000000002'
\set eventID 'f3020000-0000-0000-0000-000000000003'
\set groupCategoryID 'f3020000-0000-0000-0000-000000000004'
\set groupID 'f3020000-0000-0000-0000-000000000005'
\set missingEventID 'f3020000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community with the display name shown in checkout summaries
select fx_community(:'communityID', jsonb_build_object('display_name', 'Checkout Context Community'));

-- Baseline categories
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group with the payment recipient used by checkout
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'payment_recipient', jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_context')
));

-- Event of the group
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('name', 'Context Event'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the event with its group and community rows
select is(
    (
        select jsonb_build_object(
            'community_display_name', (c.community_row).display_name,
            'community_id', (c.community_row).community_id,
            'event_id', (c.event_row).event_id,
            'event_name', (c.event_row).name,
            'group_id', (c.group_row).group_id,
            'payment_recipient', (c.group_row).payment_recipient
        )
        from load_checkout_context(:'eventID') c
    ),
    format('{
        "community_display_name": "Checkout Context Community",
        "community_id": "%s",
        "event_id": "%s",
        "event_name": "Context Event",
        "group_id": "%s",
        "payment_recipient": {"provider": "stripe", "recipient_id": "acct_context"}
    }', :'communityID', :'eventID', :'groupID')::jsonb,
    'Should return the event with its group and community rows'
);

-- Should return exactly one row for an event
select is(
    (select count(*) from load_checkout_context(:'eventID')),
    1::bigint,
    'Should return exactly one row for an event'
);

-- Should return no row for a missing event
select is(
    (select count(*) from load_checkout_context(:'missingEventID')),
    0::bigint,
    'Should return no row for a missing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
