-- Add linked event series for recurring event creation and grouped actions.

create table event_series (
    event_series_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    group_id uuid not null references "group",
    recurrence_additional_occurrences int not null check (
        recurrence_additional_occurrences >= 1
        and recurrence_additional_occurrences <= 12
    ),
    recurrence_anchor_starts_at timestamptz not null,
    recurrence_pattern text not null check (
        recurrence_pattern in ('weekly', 'biweekly', 'monthly')
    ),
    timezone text not null check (btrim(timezone) <> ''),

    created_by uuid references "user"
);

alter table event
    add column event_series_id uuid references event_series;

create index event_event_series_id_idx on event (event_series_id)
    where event_series_id is not null;
create index event_series_group_id_idx on event_series (group_id);
