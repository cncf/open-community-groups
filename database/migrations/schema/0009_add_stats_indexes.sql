-- Adds indexes to speed up dashboard statistics queries.

create index group_member_group_id_created_at_idx
    on group_member (group_id, created_at);

create index event_starts_at_idx
    on event (starts_at)
    where published = true
        and canceled = false
        and deleted = false;

create index event_attendee_event_id_created_at_idx
    on event_attendee (event_id, created_at);
