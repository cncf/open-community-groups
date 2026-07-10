-- Adds daily page-view counters for communities, events, and groups.

-- Create the community view counter
create table community_views (
    community_id uuid references community on delete set null,
    day date not null,
    total integer not null,
    unique (community_id, day)
);

-- Create the event view counter
create table event_views (
    event_id uuid references event on delete set null,
    day date not null,
    total integer not null,
    unique (event_id, day)
);

-- Create the group view counter
create table group_views (
    group_id uuid references "group" on delete set null,
    day date not null,
    total integer not null,
    unique (group_id, day)
);
