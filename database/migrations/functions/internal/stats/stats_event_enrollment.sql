-- Returns the current enrollment counts of an event.
--
-- Registrations are attributed to the path that admitted them: the source of
-- the admission offer claimed by the purchase holding the seat, a direct
-- purchase, or a manual invitation recorded without a purchase.
create or replace function stats_event_enrollment(p_event event)
returns json as $$
-- Count attendee outcomes
with attendees as (
    select
        count(*) filter (where ea.status = 'attendance-canceled')::bigint as cancellations,
        count(*) filter (where ea.status = 'confirmed' and ea.checked_in)::bigint as checked_in,
        count(*) filter (where ea.status = 'confirmed')::bigint as registrations
    from event_attendee ea
    where ea.event_id = p_event.event_id
),
-- Count invitation requests by review status
invitation_requests as (
    select
        count(*) filter (where eir.status = 'accepted')::bigint as accepted,
        count(*) filter (where eir.status = 'pending')::bigint as pending,
        count(*) filter (where eir.status = 'rejected')::bigint as rejected
    from event_invitation_request eir
    where eir.event_id = p_event.event_id
),
-- Attribute each confirmed registration to the path that admitted it
registration_paths as (
    select
        case
            -- Credit the source of the offer claimed by the seat purchase
            when ao.source is not null then ao.source
            -- Credit a direct purchase made without an offer
            when sp.user_id is not null then 'direct'
            -- Credit a manual invitation recorded without a purchase
            when ea.manually_invited then 'organizer_invitation'
            -- Report registrations with no recorded path
            else 'unknown'
        end as path
    from event_attendee ea
    left join event_seat_purchases(p_event.event_id) sp on sp.user_id = ea.user_id
    left join admission_offer ao on ao.admission_offer_id = sp.admission_offer_id
    where ea.event_id = p_event.event_id
    and ea.status = 'confirmed'
),
-- Count admission offers by source and outcome
admission_offers as (
    select
        count(*)::bigint as count,
        case
            -- Report offers still reserving a seat as active
            when admission_offer_reserves_seat(ao.status, ao.expires_at) then 'active'
            -- Report active offers whose deadline passed before expiry ran
            when admission_offer_is_lapsed(ao.status, ao.expires_at) then 'deadline-passed'
            -- Report settled offers by their stored status
            else ao.status
        end as outcome,
        ao.source
    from admission_offer ao
    where ao.event_id = p_event.event_id
    group by outcome, ao.source
)
-- Build the enrollment counts payload
select json_build_object(
    'admission_offers', coalesce((
        select json_agg(
            json_build_object(
                'count', ao.count,
                'outcome', ao.outcome,
                'source', ao.source
            )
            order by ao.source, ao.outcome
        )
        from admission_offers ao
    ), '[]'::json),
    'cancellations', a.cancellations,
    'checked_in', a.checked_in,
    'invitation_requests', json_build_object(
        'accepted', ir.accepted,
        'pending', ir.pending,
        'rejected', ir.rejected
    ),
    'registrations', a.registrations,
    'registrations_by_path', (
        select json_build_object(
            'approval', count(*) filter (where rp.path = 'approval'),
            'direct', count(*) filter (where rp.path = 'direct'),
            'organizer_invitation', count(*) filter (where rp.path = 'organizer_invitation'),
            'unknown', count(*) filter (where rp.path = 'unknown'),
            'waitlist', count(*) filter (where rp.path = 'waitlist')
        )
        from registration_paths rp
    ),
    'waitlist', (
        select count(*)::bigint
        from event_waitlist ew
        where ew.event_id = p_event.event_id
    )
)
from attendees a
cross join invitation_requests ir;
$$ language sql stable;
