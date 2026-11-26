-- Adds a concurrent partial index on notification(notification_template_data_id) for template-data cleanup.

---- tern: disable-tx ----

set lock_timeout = '5s';
set statement_timeout = '30min';

drop index concurrently if exists notification_template_data_id_idx;
create index concurrently notification_template_data_id_idx
    on notification (notification_template_data_id)
    where notification_template_data_id is not null;

reset lock_timeout;
reset statement_timeout;
