create table if not exists site_email_template (
    notification_kind_name text primary key references notification_kind(name) on delete restrict,
    subject text not null check (btrim(subject) <> ''),
    preheader text not null check (btrim(preheader) <> ''),
    body text not null check (btrim(body) <> ''),
    cta_text text not null check (btrim(cta_text) <> ''),
    updated_at timestamp with time zone not null default current_timestamp,
    updated_by uuid references "user"(user_id) on delete set null
);

insert into site_email_template (
    notification_kind_name,
    subject,
    preheader,
    body,
    cta_text
)
values (
    'site-onboarding',
    'Welcome to GOUP',
    'Start with events, groups, jobs, and your profile.',
    'Welcome to GOUP. Here are the best places to start:',
    'Open your dashboard'
)
on conflict (notification_kind_name) do nothing;
