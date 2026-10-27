-- Returns the ticket title shown for an attendee: the title of their seat
-- purchase for the event, else their latest refunded purchase, else their
-- latest completed admission offer (falling back to the tier title).
create or replace function event_attendee_ticket_title(p_event_id uuid, p_user_id uuid)
returns text as $$
    select coalesce(
        (
            select sp.ticket_title
            from event_seat_purchases(p_event_id) sp
            where sp.user_id = p_user_id
        ),
        (
            select ep.ticket_title
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.user_id = p_user_id
            and ep.status = 'refunded'
            order by ep.created_at desc, ep.event_purchase_id desc
            limit 1
        ),
        (
            select coalesce(ao.ticket_title, ett.title)
            from admission_offer ao
            left join event_ticket_type ett using (event_ticket_type_id)
            where ao.event_id = p_event_id
            and ao.user_id = p_user_id
            and ao.status = 'completed'
            order by ao.created_at desc, ao.admission_offer_id desc
            limit 1
        )
    );
$$ language sql stable;
