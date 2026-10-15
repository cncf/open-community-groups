-- Adds daily event page-view counters attributed to UTM parameters.

-- Create the UTM mediums every group accepts without defining them.
create table utm_medium (
    utm_medium_id text primary key
);

-- Seed the default UTM mediums.
insert into utm_medium (utm_medium_id) values
    ('affiliate'),
    ('cpc'),
    ('display'),
    ('email'),
    ('organic'),
    ('qr'),
    ('referral'),
    ('sms'),
    ('social'),
    ('video');

-- Returns whether a list holds up to 20 UTM values, each made of up to 50
-- lowercase letters, digits, dots, hyphens, and underscores.
create function is_valid_utm_value_list(p_values text[])
returns boolean as $$
    select cardinality(p_values) <= 20
    and not exists (
        select 1
        from unnest(p_values) as v(value)
        where v.value is null
        or v.value !~ '^[a-z0-9._-]{1,50}$'
    );
$$ language sql immutable;

-- Add the UTM values each group accepts for its event page views. Mediums are
-- accepted in addition to the default ones.
alter table "group"
    add column utm_campaigns text[] not null default '{}',
    add column utm_mediums text[] not null default '{}',
    add column utm_sources text[] not null default '{}',
    add constraint group_utm_campaigns_chk check (is_valid_utm_value_list(utm_campaigns)),
    add constraint group_utm_mediums_chk check (is_valid_utm_value_list(utm_mediums)),
    add constraint group_utm_sources_chk check (is_valid_utm_value_list(utm_sources));

-- Create the event view counter attributed to UTM parameters. Missing values
-- are stored as empty strings, so they take part in the counter uniqueness
-- while counters of deleted events stay distinct. Views are attributed to a
-- source, a campaign, or both.
create table event_views_utm (
    event_id uuid references event on delete set null,
    day date not null,
    total integer not null,
    utm_campaign text not null default '',
    utm_medium text not null default '',
    utm_source text not null default '',

    constraint event_views_utm_event_id_day_utm_key unique (
        event_id,
        day,
        utm_campaign,
        utm_medium,
        utm_source
    ),
    constraint event_views_utm_attribution_chk check (
        utm_campaign <> ''
        or utm_source <> ''
    ),
    constraint event_views_utm_utm_campaign_chk check (
        utm_campaign = ''
        or utm_campaign ~ '^[a-z0-9._-]{1,50}$'
    ),
    constraint event_views_utm_utm_medium_chk check (
        utm_medium = ''
        or utm_medium ~ '^[a-z0-9._-]{1,50}$'
    ),
    constraint event_views_utm_utm_source_chk check (
        utm_source = ''
        or utm_source ~ '^[a-z0-9._-]{1,50}$'
    )
);
