-- Lists current and upcoming events carrying the user's check-in credential.
create or replace function list_user_check_in_events(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(event_row order by in_progress desc, starts_at), '[]'::json)
    from (
        select
            ea.checked_in,
            e.event_id,
            e.event_kind_id as kind,
            e.name,
            floor(extract(epoch from e.starts_at)) as starts_at,
            e.timezone,

            coalesce(e.logo_url, g.logo_url, c.logo_url) as logo_url,
            nullif(concat_ws(
                ', ',
                e.venue_name,
                e.venue_city,
                e.venue_state_name,
                e.venue_country_name
            ), '') as location,
            coalesce(purchase.ticket_title, offer.ticket_title) as ticket_title,

            e.starts_at <= current_timestamp as in_progress
        from event_attendee ea
        join event e using (event_id)
        join "group" g using (group_id)
        join community c using (community_id)
        left join lateral (
            select ep.ticket_title
            from event_purchase ep
            where ep.event_id = ea.event_id
            and ep.user_id = ea.user_id
            and ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested',
                'refunded'
            )
            order by ep.created_at desc, ep.event_purchase_id desc
            limit 1
        ) purchase on true
        left join lateral (
            select coalesce(ao.ticket_title, ett.title) as ticket_title
            from admission_offer ao
            left join event_ticket_type ett using (event_ticket_type_id)
            where ao.event_id = ea.event_id
            and ao.user_id = ea.user_id
            and ao.status = 'completed'
            order by ao.created_at desc, ao.admission_offer_id desc
            limit 1
        ) offer on true
        where ea.user_id = p_user_id
        and ea.status = 'confirmed'
        and e.canceled = false
        and e.deleted = false
        and e.published = true
        and e.starts_at is not null
        and g.active = true
        and g.deleted = false
        and current_timestamp < coalesce(
            e.ends_at,
            (
                date_trunc('day', e.starts_at at time zone e.timezone)
                + interval '1 day'
            ) at time zone e.timezone
        )
    ) event_row;
$$ language sql;
