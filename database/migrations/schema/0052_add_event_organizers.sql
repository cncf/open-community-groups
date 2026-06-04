-- Track event organizer attribution independently from the current group team.

-- Create organizer snapshot storage.
create table event_organizer (
    event_id uuid not null references event,
    user_id uuid not null references "user",

    "order" integer,

    primary key (event_id, user_id)
);

-- Index snapshot lookups by event and user.
create index event_organizer_event_id_idx on event_organizer (event_id);
create index event_organizer_user_id_idx on event_organizer (user_id);

-- Backfill non-legacy events from the current accepted group team.
insert into event_organizer (event_id, user_id, "order")
select e.event_id, gt.user_id, gt."order"
from event e
join group_team gt on gt.group_id = e.group_id
where e.legacy_id is null
and gt.accepted = true;
