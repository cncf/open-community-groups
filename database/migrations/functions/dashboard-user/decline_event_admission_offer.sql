-- Declines an admission offer owned by the current user.
create or replace function decline_event_admission_offer(
    p_actor_user_id uuid,
    p_admission_offer_id uuid,
    p_configured_provider text default null
)
returns json as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_event_name text;
    v_event_ticket_type_id uuid;
    v_group_id uuid;
    v_group_name text;
    v_organizer_user_id uuid;
    v_promoted_user_ids uuid[];
    v_recipient_name text;
    v_source text;
    v_theme jsonb;
    v_ticket_title text;
    v_user_id uuid;
begin
    -- Release the owned offer and any linked checkout reservation
    select
        released.community_id,
        released.event_id,
        released.event_ticket_type_id,
        released.group_id,
        released.organizer_user_id,
        released.promoted_user_ids,
        released.source,
        released.user_id
    into
        v_community_id,
        v_event_id,
        v_event_ticket_type_id,
        v_group_id,
        v_organizer_user_id,
        v_promoted_user_ids,
        v_source,
        v_user_id
    from release_event_admission_offer(
        p_admission_offer_id,
        'declined',
        null,
        p_actor_user_id,
        p_configured_provider
    ) released;

    -- Load immutable notification context after the offer release succeeds
    select
        e.name,
        g.name,
        coalesce(u.name, u.username, u.email),
        s.theme,
        coalesce(ao.ticket_title, ett.title)
    into
        v_event_name,
        v_group_name,
        v_recipient_name,
        v_theme,
        v_ticket_title
    from event e
    join "group" g using (group_id)
    join admission_offer ao
        on ao.admission_offer_id = p_admission_offer_id
    join "user" u on u.user_id = v_user_id
    left join lateral (
        select site.theme
        from site
        order by site.created_at desc
        limit 1
    ) s on true
    left join event_ticket_type ett
        on ett.event_ticket_type_id = v_event_ticket_type_id
    where e.event_id = v_event_id;

    -- Notify the assigning organizer when one owns the released offer
    if v_organizer_user_id is not null then
        perform enqueue_notification(
            'event-admission-offer-declined',
            jsonb_build_object(
                'admission_offer_id', p_admission_offer_id,
                'dashboard_url', '/dashboard/group/events/' || v_event_id || '/attendees',
                'event_id', v_event_id,
                'event_name', v_event_name,
                'event_ticket_type_id', v_event_ticket_type_id,
                'group_name', v_group_name,
                'recipient_name', v_recipient_name,
                'theme', v_theme,
                'ticket_title', v_ticket_title,
                'user_id', v_user_id
            ),
            '[]'::jsonb,
            array[v_organizer_user_id]
        );
    end if;

    -- Track the recipient decision after queue reconciliation succeeds
    perform insert_audit_log(
        case
            when v_source = 'organizer_invitation'
                then 'event_attendee_invitation_rejected'
            else 'event_admission_offer_declined'
        end,
        p_actor_user_id,
        'user',
        v_user_id,
        v_community_id,
        v_group_id,
        v_event_id,
        jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', p_admission_offer_id,
            'event_id', v_event_id,
            'event_ticket_type_id', v_event_ticket_type_id,
            'user_id', v_user_id
        ))
    );

    -- Return reconciliation context for required non-ticketed promotion notifications
    return json_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'group_id', v_group_id,
        'non_ticketed_promoted_user_ids', coalesce(v_promoted_user_ids, array[]::uuid[])
    );
end;
$$ language plpgsql;
