alter table "group"
    add column if not exists event_defaults jsonb;
