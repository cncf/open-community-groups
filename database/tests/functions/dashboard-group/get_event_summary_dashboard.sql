-- Tests dashboard event summary information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroup1ID '3a0f0000-0000-0000-0000-000000000009'
\set cohostGroup2ID '3a0f0000-0000-0000-0000-00000000000a'
\set cohostGroup3ID '3a0f0000-0000-0000-0000-00000000000b'
\set communityID '3a0f0000-0000-0000-0000-000000000001'
\set event1ID '3a0f0000-0000-0000-0000-000000000002'
\set event2ID '3a0f0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a0f0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a0f0000-0000-0000-0000-000000000005'
\set groupID '3a0f0000-0000-0000-0000-000000000006'
\set ticketTypeID '3a0f0000-0000-0000-0000-000000000008'
\set user1ID '3a0f0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Groups invited to co-host the created event
select fx_group(:'cohostGroup1ID', :'communityID', :'groupCategoryID');
select fx_group(:'cohostGroup2ID', :'communityID', :'groupCategoryID');
select fx_group(:'cohostGroup3ID', :'communityID', :'groupCategoryID');

-- User
select fx_user(:'user1ID', jsonb_build_object(
    'name', 'Creator User',
    'username', 'creator'
));

-- Event
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'created_by', :'user1ID',
    'payment_currency_code', 'USD',
    'timezone', 'America/New_York'
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'timezone', 'America/New_York'
));

-- Invitation-only ticket type included in organizer summaries
select fx_event_ticket_type(:'ticketTypeID', :'event1ID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 5
));

-- Confirmed attendee for the created event
insert into event_attendee (event_id, user_id)
values (:'event1ID', :'user1ID');

-- Two pending and one rejected co-host invitations for the created event
insert into event_cohost (event_id, event_cohost_status_id, group_id)
values
    (:'event1ID', 'pending', :'cohostGroup1ID'),
    (:'event1ID', 'pending', :'cohostGroup2ID'),
    (:'event1ID', 'rejected', :'cohostGroup3ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should extend the shared event summary with dashboard information
select is(
    get_event_summary_dashboard(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event1ID'::uuid)::jsonb
        || jsonb_build_object(
            'attendee_count', 1,
            'created_by_display_name', 'Creator User',
            'created_by_username', 'creator',
            'delete_eligibility', 'cancel-first',
            'pending_cohosts_count', 2,
            'ticket_types', list_event_ticket_types(:'event1ID'::uuid)
        ),
    'Should extend the shared event summary with dashboard information'
);

-- Should include zero counts for events without creator metadata or co-hosts
select is(
    get_event_summary_dashboard(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb,
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'event2ID'::uuid)::jsonb
        || jsonb_build_object(
            'attendee_count', 0,
            'delete_eligibility', 'allowed',
            'pending_cohosts_count', 0
        ),
    'Should include zero counts for events without creator metadata or co-hosts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
