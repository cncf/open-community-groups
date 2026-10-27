-- Updates the schema for the reworked database functions.

-- Bound lock waits and index builds so the migration fails instead of
-- stalling the app
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Take the trigger locks up front in the app's lock order (group, event,
-- tiers, sponsors), so a transaction holding a row lock cannot deadlock with
-- a later lock upgrade here
lock table "group" in share row exclusive mode;
lock table event, event_ticket_type in access exclusive mode;
lock table event_sponsor in share row exclusive mode;

-- =============================================================================
-- SITE
-- =============================================================================

-- Enforces a single site configuration row.
do $$
declare
    v_site_count bigint;
begin
    -- Refuse to pick a site row on behalf of the operator
    select count(*) into v_site_count from site;
    if v_site_count > 1 then
        raise exception
            'site table has % rows; delete the extra site rows so '
            'exactly one remains before applying this migration',
            v_site_count;
    end if;
end;
$$;

create unique index site_singleton_idx on site ((true));

-- =============================================================================
-- FUNCTION DROPS
-- =============================================================================

-- Drop the community-scoped manual check-in signature replaced by the
-- group-scoped one.
drop function if exists check_in_event(uuid, uuid, uuid, uuid);

-- Drop the event-scoped CFS submission signatures replaced by group-scoped
-- ones.
drop function if exists update_cfs_submission(uuid, uuid, uuid, jsonb);
drop function if exists list_event_cfs_submissions(uuid, jsonb);
drop function if exists list_event_approved_cfs_submissions(uuid);
drop function if exists get_cfs_submission_notification_data(uuid, uuid);

-- Drops the unused get_user_by_email function.
drop function if exists get_user_by_email(text);

-- Drops the unused publication flag from lock_active_event.
drop function if exists lock_active_event(uuid, uuid, uuid, boolean);

-- Adds the optional user lock argument to reconcile_event_enrollment.
drop function if exists reconcile_event_enrollment(uuid, uuid, text);

-- Drops the unused derived state from event_user_enrollment.
drop function if exists event_user_enrollment(uuid, uuid);

-- Drops the checkout hold expiry helper replaced by
-- expire_event_checkout_hold.
drop function if exists prepare_event_checkout_expire_previous_hold(uuid);

-- Drops the free purchase refund helper replaced by
-- refund_event_purchase_locally.
drop function if exists refund_free_event_purchase(uuid);

-- Replaces the refund result validation and claim helpers with one lock entry
-- point.
drop function if exists validate_event_purchase_refund_result(text, text);
drop function if exists ensure_event_purchase_refund_claim(event_purchase_refund, payment_job, uuid);

-- Returns checkout pricing conflicts as a result column instead of raising.
drop function if exists prepare_event_checkout_validate_and_resolve_pricing(uuid, uuid, uuid, text, uuid);

-- Drops single-caller checkout wrappers and the unused discount release
-- quantity, and passes the purchase tax code to the tax cache lookup.
drop function if exists prepare_event_checkout_validate_event(uuid, uuid);
drop function if exists load_checkout_context(uuid);
drop function if exists prepare_event_checkout_reserve_discount_code_availability(uuid);
drop function if exists release_event_discount_code_availability(uuid, integer);
drop function if exists prepare_event_checkout_lookup_tax_cache(text, text, jsonb, text);

-- Replaces jsonb event context in ticketing readiness validators with event
-- rows.
drop function if exists validate_event_ticketing_payment_readiness(text, boolean, text, jsonb, uuid, jsonb, boolean, text, integer, text);
drop function if exists validate_event_ticketing_payload(text, jsonb, text, jsonb, jsonb, boolean, uuid, jsonb);

-- Drop the automatic-tax readiness wrapper replaced by the event id list.
drop function if exists group_requires_automatic_tax_readiness(uuid, uuid);

-- Drops the base URL parameter from enqueue_due_event_reminders.
drop function if exists enqueue_due_event_reminders(text);

-- Drops the redundant recipient count parameter from
-- enqueue_tracked_custom_notification.
drop function if exists enqueue_tracked_custom_notification(text, jsonb, jsonb, uuid[], uuid, uuid, uuid, uuid, int, text, text, jsonb);

-- Drops the group member and team member id lists replaced by
-- list_group_audience_ids.
drop function if exists list_group_members_ids(uuid);
drop function if exists list_group_team_members_ids(uuid);

-- Drops the audit resource name helper replaced by the snapshot-aware
-- signature.
drop function if exists audit_log_resource_name(text, uuid);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Fires the community and group ownership checks only on writes to ownership
-- columns.
create or replace trigger event_category_community_check
    before insert or update of event_category_id, group_id on event
    for each row
    execute function check_event_category_community();

create or replace trigger event_sponsor_group_check
    before insert or update of event_id, group_sponsor_id on event_sponsor
    for each row
    execute function check_event_sponsor_group();

create or replace trigger group_category_community_check
    before insert or update of community_id, group_category_id on "group"
    for each row
    execute function check_group_category_community();

create or replace trigger group_region_community_check
    before insert or update of community_id, region_id on "group"
    for each row
    execute function check_group_region_community();

-- Enforces ticket type presence through the event ticketing consistency
-- trigger.
drop trigger event_has_ticket_type_on_event on event;
drop trigger event_has_ticket_type_on_event_ticket_type on event_ticket_type;
drop function if exists check_event_has_ticket_type();

-- =============================================================================
-- MEETING DATA REPAIR
-- =============================================================================

-- Re-queues provider meeting deletions lost when a disabled meeting was
-- saved again before the worker deleted it. Meetings with captured
-- recordings are kept so their recording links are not lost. Pending
-- deletions with an unset meeting request are stopped when the meeting has
-- captured recordings or its join URL is reused as the manual link.

-- Re-queue lost event meeting deletions
update event e
set meeting_in_sync = false
from meeting m
where m.event_id = e.event_id
and e.meeting_requested = false
and e.meeting_in_sync is null
and e.meeting_join_url is distinct from m.join_url
and cardinality(m.recording_urls) = 0;

-- Stop unset-request event deletions that would lose recordings or a manual link
update event e
set meeting_in_sync = null
from meeting m
where m.event_id = e.event_id
and e.meeting_requested is null
and e.meeting_in_sync = false
and (
    cardinality(m.recording_urls) > 0
    or e.meeting_join_url = m.join_url
);

do $$
begin
    -- Avoid failing this data repair on pre-existing legacy session bounds
    perform set_config('ocg.skip_session_bounds_check', 'on', true);

    -- Re-queue lost session meeting deletions
    update session s
    set meeting_in_sync = false
    from meeting m
    where m.session_id = s.session_id
    and s.meeting_requested = false
    and s.meeting_in_sync is null
    and s.meeting_join_url is distinct from m.join_url
    and cardinality(m.recording_urls) = 0;

    -- Stop unset-request session deletions that would lose recordings or a manual link
    update session s
    set meeting_in_sync = null
    from meeting m
    where m.session_id = s.session_id
    and s.meeting_requested is null
    and s.meeting_in_sync = false
    and (
        cardinality(m.recording_urls) > 0
        or s.meeting_join_url = m.join_url
    );
end;
$$;
