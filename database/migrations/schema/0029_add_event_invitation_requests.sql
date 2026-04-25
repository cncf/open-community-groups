-- Add invitation request support for approval-required event attendance.

alter table event
    add column attendee_approval_required boolean not null default false,
    add constraint event_attendee_approval_waitlist_exclusive_chk check (
        not (attendee_approval_required = true and waitlist_enabled = true)
    );

create table event_invitation_request (
    event_id uuid not null references event,
    user_id uuid not null references "user",
    created_at timestamptz default current_timestamp not null,
    status text not null default 'pending' check (status in ('accepted', 'pending', 'rejected')),

    reviewed_at timestamptz,
    reviewed_by uuid references "user",

    primary key (event_id, user_id),
    check (
        (status = 'pending' and reviewed_at is null and reviewed_by is null)
        or (status in ('accepted', 'rejected') and reviewed_at is not null and reviewed_by is not null)
    )
);

create index event_invitation_request_event_id_status_created_at_idx
    on event_invitation_request (event_id, status, created_at);
create index event_invitation_request_user_id_idx on event_invitation_request (user_id);
