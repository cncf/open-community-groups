-- Tests deferred waitlist capacity validation across event and ticket writes.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ab170000-0000-0000-0000-000000000001'
\set eventCategoryID 'ab170000-0000-0000-0000-000000000002'
\set groupCategoryID 'ab170000-0000-0000-0000-000000000003'
\set groupID 'ab170000-0000-0000-0000-000000000004'
\set invalidEventID 'ab170000-0000-0000-0000-000000000005'
\set ticketedEventID 'ab170000-0000-0000-0000-000000000006'
\set ticketTypeID 'ab170000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'waitlist-capacity-community',
    'Waitlist Capacity Community',
    'Community for waitlist capacity trigger tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Waitlist Capacity Group',
    'waitlist-capacity-group'
);

-- Test helper creates a waitlisted event and optionally adds ticket capacity
create function pg_temp.create_waitlist_event(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_event_category_id uuid,
    p_group_id uuid,
    p_with_ticket_type boolean
)
returns void as $$
begin
    -- Create the event before its normalized ticket rows
    insert into event (
        event_id,
        capacity,
        description,
        event_category_id,
        event_kind_id,
        group_id,
        name,
        slug,
        timezone,
        waitlist_enabled
    ) values (
        p_event_id,
        null,
        'Event for deferred waitlist capacity validation',
        p_event_category_id,
        'virtual',
        p_group_id,
        'Deferred Waitlist Event',
        'deferred-waitlist-' || p_event_id,
        'UTC',
        true
    );

    -- Add tier capacity in the same transaction when requested
    if p_with_ticket_type then
        insert into event_ticket_type (
            event_ticket_type_id,
            event_id,
            "order",
            seats_total,
            title
        ) values (
            p_event_ticket_type_id,
            p_event_id,
            1,
            10,
            'General admission'
        );
    end if;

    -- Force deferred validation while retaining deferred mode for later tests
    set constraints all immediate;
    set constraints all deferred;
end;
$$ language plpgsql;

-- Test helper removes the final tier and forces deferred validation
create function pg_temp.remove_last_ticket_type(p_event_ticket_type_id uuid)
returns void as $$
begin
    -- Remove the only source of capacity
    delete from event_ticket_type
    where event_ticket_type_id = p_event_ticket_type_id;

    -- Force the settled event configuration to validate
    set constraints all immediate;
    set constraints all deferred;
end;
$$ language plpgsql;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject event-level waitlists without capacity or ticket tiers
select throws_ok(
    format(
        $$
            select pg_temp.create_waitlist_event(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                false
            )
        $$,
        :'invalidEventID',
        :'ticketTypeID',
        :'eventCategoryID',
        :'groupID'
    ),
    'waitlist enabled events must define a capacity or ticket types',
    'Should reject waitlists without event or ticket capacity'
);

-- Should allow ticketed waitlists without event-level capacity
select lives_ok(
    format(
        $$
            select pg_temp.create_waitlist_event(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                true
            )
        $$,
        :'ticketedEventID',
        :'ticketTypeID',
        :'eventCategoryID',
        :'groupID'
    ),
    'Should allow ticketed waitlists without event-level capacity'
);

-- Should reject removing the final tier while the waitlist remains enabled
select throws_ok(
    format(
        $$select pg_temp.remove_last_ticket_type(%L::uuid)$$,
        :'ticketTypeID'
    ),
    'waitlist enabled events must define a capacity or ticket types',
    'Should reject removing the final ticket tier from a waitlisted event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
