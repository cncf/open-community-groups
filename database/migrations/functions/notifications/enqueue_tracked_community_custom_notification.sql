-- Enqueues and tracks a custom notification to the group team members of a
-- community matching the contact filters, returning the recipients count.
-- Recipients are resolved in the same statement that queues and audits them.
create or replace function enqueue_tracked_community_custom_notification(
    p_community_id uuid,
    p_created_by uuid,
    p_filters jsonb,
    p_template_data jsonb,
    p_subject text,
    p_body text
)
returns int as $$
declare
    v_recipients uuid[];
begin
    -- Reject filter values outside the community
    perform validate_community_contact_filters(p_community_id, p_filters);

    -- Resolve each matching person once
    select coalesce(array_agg(distinct s.user_id order by s.user_id), '{}')
    into v_recipients
    from community_contact_team_seats(p_community_id, p_filters) s;

    -- Reject filters that match nobody
    if cardinality(v_recipients) = 0 then
        raise exception 'no group team members match the selected filters' using errcode = 'OCG01';
    end if;

    -- Queue and track the notification for the resolved recipients
    perform enqueue_tracked_custom_notification(
        'community-custom',
        p_template_data,
        '[]'::jsonb,
        v_recipients,
        p_created_by,
        p_community_id,
        null,
        null,
        cardinality(v_recipients),
        p_subject,
        p_body,
        p_filters
    );

    -- Return the number of people the notification was queued for
    return cardinality(v_recipients);
end;
$$ language plpgsql;
