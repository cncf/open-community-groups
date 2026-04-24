-- Add aggregate notification kinds for linked event series actions.

insert into notification_kind (name) values
    ('event-series-canceled'),
    ('event-series-published'),
    ('speaker-series-welcome');
