-- Tests lifecycle traffic and registration statistics of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'ea030000-0000-0000-0000-000000000001'
\set eventCategoryID 'ea030000-0000-0000-0000-000000000002'
\set eventDayInconsistentID 'ea030000-0000-0000-0000-000000000003'
\set eventID 'ea030000-0000-0000-0000-000000000004'
\set eventOverallInconsistentID 'ea030000-0000-0000-0000-000000000005'
\set groupCategoryID 'ea030000-0000-0000-0000-000000000006'
\set groupID 'ea030000-0000-0000-0000-000000000007'
\set ticketTypeGeneralID 'ea030000-0000-0000-0000-000000000008'
\set ticketTypeVipID 'ea030000-0000-0000-0000-000000000009'
\set userAfterEndID 'ea030000-0000-0000-0000-00000000000a'
\set userBaselineID 'ea030000-0000-0000-0000-00000000000b'
\set userCanceledID 'ea030000-0000-0000-0000-00000000000c'
\set userLocalBoundaryID 'ea030000-0000-0000-0000-00000000000d'
\set userMultiPurchaseID 'ea030000-0000-0000-0000-00000000000e'
\set userUnknownID 'ea030000-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_user(:'userAfterEndID');
select fx_user(:'userBaselineID');
select fx_user(:'userCanceledID');
select fx_user(:'userLocalBoundaryID');
select fx_user(:'userMultiPurchaseID');
select fx_user(:'userUnknownID');

-- Event whose lifecycle traffic and registrations are analyzed
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event with more tagged than total views on one day of the range
select fx_event(:'eventDayInconsistentID', :'groupID', :'eventCategoryID');

-- Event with more tagged than total views outside the range
select fx_event(:'eventOverallInconsistentID', :'groupID', :'eventCategoryID');

-- Ticket types ordered general first and VIP second
select fx_event_ticket_type(:'ticketTypeGeneralID', :'eventID', jsonb_build_object(
    'order', 1,
    'title', 'General'
));
select fx_event_ticket_type(:'ticketTypeVipID', :'eventID', jsonb_build_object(
    'order', 2,
    'title', 'VIP'
));

-- Attendees covering the baseline, the range, the UTC boundary and exclusions
insert into event_attendee (event_id, user_id, created_at, status, attendance_canceled_at) values
    (:'eventID', :'userAfterEndID', '2030-01-05 23:30:00-05', 'confirmed', null),
    (:'eventID', :'userBaselineID', '2029-12-31 23:30:00+00', 'confirmed', null),
    (:'eventID', :'userCanceledID', '2030-01-02 10:00:00+00', 'attendance-canceled', '2030-01-03 10:00:00+00'),
    (:'eventID', :'userLocalBoundaryID', '2030-01-02 01:00:00+05', 'confirmed', null),
    (:'eventID', :'userMultiPurchaseID', '2030-01-01 00:30:00+00', 'confirmed', null),
    (:'eventID', :'userUnknownID', '2030-01-03 12:00:00+00', 'confirmed', null);

-- Seat purchases, including two seat-holding purchases for one attendee
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (0, '2030-01-01 00:20:00+00', :'eventID', :'ticketTypeGeneralID', 'completed', 'General', :'userLocalBoundaryID', '2030-01-01 20:00:00+00'),
    (0, '2030-01-01 00:20:00+00', :'eventID', :'ticketTypeGeneralID', 'refund-pending', 'General', :'userMultiPurchaseID', '2030-01-01 01:00:00+00'),
    (0, '2030-01-01 00:25:00+00', :'eventID', :'ticketTypeVipID', 'completed', 'VIP', :'userMultiPurchaseID', '2030-01-01 02:00:00+00'),
    (0, '2030-01-01 00:30:00+00', :'eventID', :'ticketTypeVipID', 'expired', 'VIP', :'userUnknownID', null);

-- Daily views before, inside and after the range
insert into event_views (event_id, day, total) values
    (:'eventDayInconsistentID', '2030-01-01', 1),
    (:'eventDayInconsistentID', '2030-01-02', 10),
    (:'eventID', '2029-12-30', 4),
    (:'eventID', '2030-01-01', 20),
    (:'eventID', '2030-01-02', 10),
    (:'eventID', '2030-01-05', 30),
    (:'eventID', '2030-01-06', 7),
    (:'eventOverallInconsistentID', '2029-12-01', 1),
    (:'eventOverallInconsistentID', '2030-01-01', 2);

-- Tagged views with tied sources, a literal other source and a campaign-only row
insert into event_views_utm (event_id, day, total, utm_campaign, utm_source) values
    (:'eventDayInconsistentID', '2030-01-01', 3, '', 'alpha'),
    (:'eventID', '2029-12-30', 4, '', 'zulu'),
    (:'eventID', '2030-01-01', 6, '', 'alpha'),
    (:'eventID', '2030-01-01', 5, '', 'beta'),
    (:'eventID', '2030-01-01', 1, '', 'golf'),
    (:'eventID', '2030-01-01', 5, '', 'other'),
    (:'eventID', '2030-01-02', 4, '', 'delta'),
    (:'eventID', '2030-01-02', 3, '', 'echo'),
    (:'eventID', '2030-01-05', 3, '', 'foxtrot'),
    (:'eventID', '2030-01-05', 2, 'launch', ''),
    (:'eventOverallInconsistentID', '2029-12-01', 5, '', 'alpha');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accumulate registrations from the baseline
select is(
    (
        select stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->'registrations_running_total'
        from event e
        where e.event_id = :'eventID'
    ),
    '[["2030-01-01", 3], ["2030-01-02", 3], ["2030-01-03", 4], ["2030-01-04", 4], ["2030-01-05", 4]]'::jsonb,
    'Should accumulate registrations from the baseline'
);

-- Should count all-time views and the views outside the range
select is(
    (
        select jsonb_build_object(
            'views_after_end', traffic->'views_after_end',
            'views_before_start', traffic->'views_before_start',
            'views_total', traffic->'views_total'
        )
        from (
            select stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb as traffic
            from event e
            where e.event_id = :'eventID'
        ) stats
    ),
    '{"views_after_end": 7, "views_before_start": 4, "views_total": 71}'::jsonb,
    'Should count all-time views and the views outside the range'
);

-- Should count registrations before the range as the baseline
select is(
    (
        select (stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->>'registrations_baseline')::int
        from event e
        where e.event_id = :'eventID'
    ),
    1,
    'Should count registrations before the range as the baseline'
);

-- Should date registrations by their UTC day
select is(
    (
        select stats_event_traffic(e, '2030-01-01', '2030-01-06')::jsonb->'registrations_running_total'->5
        from event e
        where e.event_id = :'eventID'
    ),
    '["2030-01-06", 5]'::jsonb,
    'Should date registrations by their UTC day'
);

-- Should flag attribution as consistent when tagged views fit the totals
select is(
    (
        select (stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->>'attribution_consistent')::boolean
        from event e
        where e.event_id = :'eventID'
    ),
    true,
    'Should flag attribution as consistent when tagged views fit the totals'
);

-- Should flag attribution as inconsistent when a day has more tagged views
select is(
    (
        select (stats_event_traffic(e, '2030-01-01', '2030-01-02')::jsonb->>'attribution_consistent')::boolean
        from event e
        where e.event_id = :'eventDayInconsistentID'
    ),
    false,
    'Should flag attribution as inconsistent when a day has more tagged views'
);

-- Should flag attribution as inconsistent when all-time tagged views exceed the total
select is(
    (
        select (stats_event_traffic(e, '2030-01-01', '2030-01-02')::jsonb->>'attribution_consistent')::boolean
        from event e
        where e.event_id = :'eventOverallInconsistentID'
    ),
    false,
    'Should flag attribution as inconsistent when all-time tagged views exceed the total'
);

-- Should include the end day in a single day range
select is(
    (
        select stats_event_traffic(e, '2030-01-05', '2030-01-05')::jsonb->'views_by_source_per_day'
        from event e
        where e.event_id = :'eventID'
    ),
    '[
        {"kind": "source", "series": [["2030-01-05", 3]], "source": "foxtrot"},
        {"kind": "no-source", "series": [["2030-01-05", 2]], "source": null},
        {"kind": "untagged", "series": [["2030-01-05", 25]], "source": null}
    ]'::jsonb,
    'Should include the end day in a single day range'
);

-- Should keep totals and return empty series for missing bounds
select is(
    (
        select stats_event_traffic(e, null, null)::jsonb
        from event e
        where e.event_id = :'eventID'
    ),
    '{
        "attribution_consistent": true,
        "registrations_baseline": 0,
        "registrations_by_ticket_type_per_day": [],
        "registrations_running_total": [],
        "views_after_end": 0,
        "views_before_start": 0,
        "views_by_source_per_day": [],
        "views_total": 71
    }'::jsonb,
    'Should keep totals and return empty series for missing bounds'
);

-- Should return empty series when the start is after the end
select is(
    (
        select stats_event_traffic(e, '2030-01-05', '2030-01-01')::jsonb->'views_by_source_per_day'
        from event e
        where e.event_id = :'eventID'
    ),
    '[]'::jsonb,
    'Should return empty series when the start is after the end'
);

-- Should stack daily views up to the daily totals
select is(
    (
        select jsonb_agg(day_total order by day)
        from (
            select point->>0 as day, sum((point->>1)::int) as day_total
            from event e
            cross join lateral jsonb_array_elements(
                stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->'views_by_source_per_day'
            ) as views_series
            cross join lateral jsonb_array_elements(views_series->'series') as point
            where e.event_id = :'eventID'
            group by point->>0
        ) day_totals
    ),
    '[20, 10, 0, 0, 30]'::jsonb,
    'Should stack daily views up to the daily totals'
);

-- Should stack registrations by the latest seat-holding ticket type
select is(
    (
        select stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->'registrations_by_ticket_type_per_day'
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'ticket-type',
            'series', '[["2030-01-01", 1], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 0]]'::jsonb,
            'event_ticket_type_id', :'ticketTypeGeneralID',
            'order', 1,
            'title', 'General'
        ),
        jsonb_build_object(
            'kind', 'ticket-type',
            'series', '[["2030-01-01", 1], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 0]]'::jsonb,
            'event_ticket_type_id', :'ticketTypeVipID',
            'order', 2,
            'title', 'VIP'
        ),
        jsonb_build_object(
            'kind', 'unknown',
            'series', '[["2030-01-01", 0], ["2030-01-02", 0], ["2030-01-03", 1], ["2030-01-04", 0], ["2030-01-05", 0]]'::jsonb,
            'event_ticket_type_id', null,
            'order', null,
            'title', null
        )
    ),
    'Should stack registrations by the latest seat-holding ticket type'
);

-- Should stack views by top sources, other sources, no source and untagged
select is(
    (
        select stats_event_traffic(e, '2030-01-01', '2030-01-05')::jsonb->'views_by_source_per_day'
        from event e
        where e.event_id = :'eventID'
    ),
    '[
        {"kind": "source", "series": [["2030-01-01", 6], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 0]], "source": "alpha"},
        {"kind": "source", "series": [["2030-01-01", 5], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 0]], "source": "beta"},
        {"kind": "source", "series": [["2030-01-01", 5], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 0]], "source": "other"},
        {"kind": "other-sources", "series": [["2030-01-01", 1], ["2030-01-02", 7], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 3]], "source": null},
        {"kind": "no-source", "series": [["2030-01-01", 0], ["2030-01-02", 0], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 2]], "source": null},
        {"kind": "untagged", "series": [["2030-01-01", 3], ["2030-01-02", 3], ["2030-01-03", 0], ["2030-01-04", 0], ["2030-01-05", 25]], "source": null}
    ]'::jsonb,
    'Should stack views by top sources, other sources, no source and untagged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
