create table alliance_views (
    alliance_id uuid references alliance on delete set null,
    day date not null,
    total integer not null,
    unique (alliance_id, day)
);

create table event_views (
    event_id uuid references event on delete set null,
    day date not null,
    total integer not null,
    unique (event_id, day)
);

create table group_views (
    group_id uuid references "group" on delete set null,
    day date not null,
    total integer not null,
    unique (group_id, day)
);
