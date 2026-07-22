-- Apply safely to both the pre-baseline production schema and fresh baseline databases.
create table if not exists event_organizer (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    "order" integer,
    primary key (event_id, user_id)
);

create index if not exists event_organizer_event_id_idx on event_organizer (event_id);
create index if not exists event_organizer_user_id_idx on event_organizer (user_id);

insert into event_organizer (event_id, user_id, "order")
select e.event_id, gt.user_id, gt."order"
from event e
join group_team gt on gt.group_id = e.group_id
where e.legacy_id is null
  and gt.accepted = true
on conflict (event_id, user_id) do nothing;
