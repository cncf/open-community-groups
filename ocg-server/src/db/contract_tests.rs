//! Database contract tests: the ignored `db_contracts` tests run against a real database
//! migrated and seeded with `database/tests/data/contract.sql`, one module per database trait.

mod auth;
mod badges;
mod common;
mod community;
mod dashboard_common;
mod dashboard_community;
mod dashboard_group;
mod dashboard_user;
mod event;
mod group;
mod helpers;
mod meetings;
mod notifications;
mod payments;
mod site;
