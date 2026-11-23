//! Real-database contracts for the payments webhook reconciler: single-connection
//! atomicity, replay skipping, and rollback behavior that mocks cannot prove,
//! run by `just db-contract-tests`.

use std::sync::Arc;

use anyhow::Result;
use deadpool_postgres::{Client, Pool, PoolConfig};
use serde_json::{Value, json};
use tokio_postgres::NoTls;

use crate::{
    config::HttpServerConfig,
    db::{
        DynDB, PgDB,
        contract_tests::helpers::{
            contract_tests_config, contract_tests_pool, paid_event_id, reconcile_buyer_id,
            reconcile_purchase_id,
        },
        pool::create_pool,
    },
    services::payments::{
        PaymentsWebhookEvent,
        provider::{CheckoutFinancialContext, MockPaymentsProvider},
    },
    types::payments::PaymentProvider,
};

use super::PaymentsWebhookReconciler;

/// Connected account owning the contract checkout reconciliation fixture.
const CONTRACT_CONNECTED_ACCOUNT_ID: &str = "acct_contract";

/// Checkout session identifier of the contract reconciliation fixture.
const CONTRACT_RECONCILE_SESSION_ID: &str = "cs_contract_reconcile";

#[tokio::test]
#[ignore = "requires the contract test database"]
#[allow(clippy::too_many_lines)]
async fn db_contracts_webhook_reconciler_completes_checkout_with_notification_on_one_connection()
-> Result<()> {
    // Setup clean fixture state and single-connection pools before mutating the database
    let admin_client = contract_tests_pool()?.get().await?;
    reset_reconcile_purchase_fixture(&admin_client).await?;
    let completion_pool = single_connection_pool()?;
    let replay_pool = single_connection_pool()?;

    // Run completion, state inspection, and replay before unconditionally restoring the fixture
    let outcome: Result<_> = async {
        // Reconcile the checkout on one connection; a nested checkout fails the 5s pool wait
        let reconciler =
            sample_contract_reconciler(completion_pool.clone(), CONTRACT_RECONCILE_SESSION_ID);
        reconciler
            .handle_webhook_event(checkout_completed_event(CONTRACT_RECONCILE_SESSION_ID))
            .await?;

        // Inspect the SQL statements executed on the single connection
        let completion_client = completion_pool.get().await?;
        let completion_statements = prepared_statements(&completion_client).await?;
        drop(completion_client);

        // Load the committed purchase, attendance, and welcome notification rows
        let purchase_status: String = admin_client
            .query_one(
                "select status::text from event_purchase where event_purchase_id = $1::uuid",
                &[&reconcile_purchase_id()],
            )
            .await?
            .get(0);
        let attendee_status: String = admin_client
            .query_one(
                "select status::text from event_attendee where event_id = $1::uuid and user_id = $2::uuid",
                &[&paid_event_id(), &reconcile_buyer_id()],
            )
            .await?
            .get(0);
        let notification_rows = admin_client
            .query(
                "
                select d.data, a.content_type
                from notification n
                join notification_template_data d using (notification_template_data_id)
                left join notification_attachment na using (notification_id)
                left join attachment a using (attachment_id)
                where n.user_id = $1::uuid
                and n.kind = 'event-welcome'
                ",
                &[&reconcile_buyer_id()],
            )
            .await?;

        // Replay the same completed webhook on a fresh single-connection pool
        let replay_reconciler =
            sample_contract_reconciler(replay_pool.clone(), CONTRACT_RECONCILE_SESSION_ID);
        replay_reconciler
            .handle_webhook_event(checkout_completed_event(CONTRACT_RECONCILE_SESSION_ID))
            .await?;

        // Inspect statements and notification count after the replayed webhook
        let replay_client = replay_pool.get().await?;
        let replay_statements = prepared_statements(&replay_client).await?;
        drop(replay_client);
        let notification_count_after_replay: i64 = admin_client
            .query_one(
                "select count(*) from notification where user_id = $1::uuid and kind = 'event-welcome'",
                &[&reconcile_buyer_id()],
            )
            .await?
            .get(0);

        Ok((
            attendee_status,
            completion_statements,
            notification_count_after_replay,
            notification_rows,
            purchase_status,
            replay_statements,
        ))
    }
    .await;

    // Restore the fixture regardless of whether the body succeeded or returned an error
    reset_reconcile_purchase_fixture(&admin_client).await?;
    let (
        attendee_status,
        completion_statements,
        notification_count_after_replay,
        notification_rows,
        purchase_status,
        replay_statements,
    ) = outcome?;

    // Check reconciliation, event lookup, and notification insert shared one connection
    assert!(has_statement(
        &completion_statements,
        "reconcile_event_purchase_for_checkout_session"
    ));
    assert!(has_statement(
        &completion_statements,
        "get_event_summary_by_id"
    ));
    assert!(has_statement(&completion_statements, "get_site_settings"));
    assert!(has_statement(
        &completion_statements,
        "enqueue_notification"
    ));

    // Check the purchase, attendance, and attendee welcome notification committed together
    assert_eq!(purchase_status, "completed");
    assert_eq!(attendee_status, "confirmed");
    assert_eq!(notification_rows.len(), 1);
    let template_data: Value = notification_rows[0].get(0);
    let attachment_content_type: Option<String> = notification_rows[0].get(1);
    assert_eq!(template_data["event"]["event_id"], json!(paid_event_id()));
    assert!(template_data["dashboard_link"].is_null());
    assert_eq!(
        attachment_content_type.as_deref(),
        Some("text/calendar; charset=utf-8")
    );

    // Check the replayed webhook skipped notification lookups and insert SQL
    assert!(has_statement(
        &replay_statements,
        "reconcile_event_purchase_for_checkout_session"
    ));
    assert!(!has_statement(
        &replay_statements,
        "get_event_summary_by_id"
    ));
    assert!(!has_statement(&replay_statements, "get_site_settings"));
    assert!(!has_statement(&replay_statements, "enqueue_notification"));
    assert_eq!(notification_count_after_replay, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_webhook_reconciler_noop_webhook_skips_notification_lookups() -> Result<()> {
    // Setup a fresh single-connection pool and an unknown checkout session
    let pool = single_connection_pool()?;
    let session_id = "cs_contract_unknown";
    let reconciler = sample_contract_reconciler(pool.clone(), session_id);

    // Reconcile the no-op checkout webhook
    reconciler
        .handle_webhook_event(checkout_completed_event(session_id))
        .await?;

    // Check only reconciliation ran and no notification lookup or insert executed
    let client = pool.get().await?;
    let statements = prepared_statements(&client).await?;
    assert!(has_statement(
        &statements,
        "reconcile_event_purchase_for_checkout_session"
    ));
    assert!(!has_statement(&statements, "get_event_summary_by_id"));
    assert!(!has_statement(&statements, "get_site_settings"));
    assert!(!has_statement(&statements, "enqueue_notification"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_webhook_reconciler_rolls_back_checkout_when_notification_enqueue_fails()
-> Result<()> {
    // Setup clean fixture state and the single-connection pool before installing the trigger
    let admin_client = contract_tests_pool()?.get().await?;
    reset_reconcile_purchase_fixture(&admin_client).await?;
    let pool = single_connection_pool()?;
    let reconciler = sample_contract_reconciler(pool.clone(), CONTRACT_RECONCILE_SESSION_ID);

    // Install a targeted trigger simulating an enqueue failure and run checkout reconciliation
    install_failing_welcome_notification_trigger(&admin_client).await?;
    let webhook_join = tokio::spawn(async move {
        reconciler
            .handle_webhook_event(checkout_completed_event(CONTRACT_RECONCILE_SESSION_ID))
            .await
    })
    .await;

    // Remove the failure trigger immediately, even if reconciliation panicked
    remove_failing_welcome_notification_trigger(&admin_client).await?;
    let webhook_result = match webhook_join {
        Ok(result) => result,
        Err(err) => {
            reset_reconcile_purchase_fixture(&admin_client).await?;
            if err.is_panic() {
                std::panic::resume_unwind(err.into_panic());
            }
            return Err(err.into());
        }
    };

    // Inspect the single-connection statements and persisted tables before any assertion can fail
    let inspection: Result<_> = async {
        let client = pool.get().await?;
        let statements = prepared_statements(&client).await?;
        drop(client);
        let purchase_status: String = admin_client
            .query_one(
                "select status::text from event_purchase where event_purchase_id = $1::uuid",
                &[&reconcile_purchase_id()],
            )
            .await?
            .get(0);
        let attendee_count: i64 = admin_client
            .query_one(
                "select count(*) from event_attendee where event_id = $1::uuid and user_id = $2::uuid",
                &[&paid_event_id(), &reconcile_buyer_id()],
            )
            .await?
            .get(0);
        let notification_count: i64 = admin_client
            .query_one(
                "select count(*) from notification where user_id = $1::uuid and kind = 'event-welcome'",
                &[&reconcile_buyer_id()],
            )
            .await?
            .get(0);

        Ok((attendee_count, notification_count, purchase_status, statements))
    }
    .await;

    // Restore the fixture cleanly in case the webhook unexpectedly committed
    reset_reconcile_purchase_fixture(&admin_client).await?;
    let (attendee_count, notification_count, purchase_status, statements) = inspection?;

    // Check reconciliation, event lookup, and enqueue ran on one connection and rolled back
    let err = webhook_result
        .expect_err("simulated notification enqueue failure should roll back checkout");
    assert!(
        format!("{err:#}").contains("simulated welcome notification enqueue failure"),
        "unexpected error: {err:#}"
    );
    assert!(has_statement(
        &statements,
        "reconcile_event_purchase_for_checkout_session"
    ));
    assert!(has_statement(&statements, "get_event_summary_by_id"));
    assert!(has_statement(&statements, "enqueue_notification"));
    assert_eq!(purchase_status, "pending");
    assert_eq!(attendee_count, 0);
    assert_eq!(notification_count, 0);

    Ok(())
}

// Helpers.

/// Builds a verified `CheckoutCompleted` webhook event for the contract seller.
fn checkout_completed_event(session_id: &str) -> PaymentsWebhookEvent {
    PaymentsWebhookEvent::CheckoutCompleted {
        connected_account_id: CONTRACT_CONNECTED_ACCOUNT_ID.to_string(),
        is_live: false,
        provider_session_id: session_id.to_string(),
    }
}

/// Reports whether any prepared statement on the connection contains `needle`.
fn has_statement(statements: &[String], needle: &str) -> bool {
    statements.iter().any(|statement| statement.contains(needle))
}

/// Installs a targeted trigger that fails welcome notification inserts for the
/// contract reconciliation buyer.
async fn install_failing_welcome_notification_trigger(client: &Client) -> Result<()> {
    client
        .batch_execute(&format!(
            "
            create or replace function fail_contract_welcome_notification_insert()
            returns trigger as $$
            begin
                raise exception 'simulated welcome notification enqueue failure';
            end;
            $$ language plpgsql;

            drop trigger if exists fail_contract_welcome_notification_insert_trg on notification;

            create trigger fail_contract_welcome_notification_insert_trg
            before insert on notification
            for each row
            when (new.kind = 'event-welcome' and new.user_id = '{}'::uuid)
            execute function fail_contract_welcome_notification_insert();
            ",
            reconcile_buyer_id()
        ))
        .await?;

    Ok(())
}

/// Returns every prepared SQL statement recorded on `client`.
async fn prepared_statements(client: &Client) -> Result<Vec<String>> {
    let rows = client
        .query("select statement from pg_prepared_statements", &[])
        .await?;

    Ok(rows.into_iter().map(|row| row.get(0)).collect())
}

/// Drops the targeted trigger used to simulate welcome notification failures.
async fn remove_failing_welcome_notification_trigger(client: &Client) -> Result<()> {
    client
        .batch_execute(
            "
            drop trigger if exists fail_contract_welcome_notification_insert_trg on notification;
            drop function if exists fail_contract_welcome_notification_insert();
            ",
        )
        .await?;

    Ok(())
}

/// Restores the contract reconciliation purchase fixture and clears rows or
/// triggers left behind by prior runs of these contracts.
async fn reset_reconcile_purchase_fixture(client: &Client) -> Result<()> {
    // Drop any leftover failure trigger from an aborted prior focused run
    remove_failing_welcome_notification_trigger(client).await?;

    // Remove welcome notification links and rows created for the fixture buyer
    client
        .execute(
            "
            delete from notification_attachment
            where notification_id in (
                select notification_id
                from notification
                where user_id = $1::uuid
                and kind = 'event-welcome'
            )
            ",
            &[&reconcile_buyer_id()],
        )
        .await?;
    client
        .execute(
            "
            delete from notification
            where user_id = $1::uuid
            and kind = 'event-welcome'
            ",
            &[&reconcile_buyer_id()],
        )
        .await?;

    // Remove confirmed attendance created for the fixture buyer
    client
        .execute(
            "
            delete from event_attendee
            where event_id = $1::uuid
            and user_id = $2::uuid
            ",
            &[&paid_event_id(), &reconcile_buyer_id()],
        )
        .await?;

    // Restore the pending checkout purchase row to its seeded contract values
    client
        .execute(
            "
            update event_purchase
            set
                completed_at = null,
                final_platform_fee_amount_minor = null,
                financially_reconciled_at = null,
                hold_expires_at = '2099-01-01 00:00:00+00',
                provider_application_fee_id = null,
                provider_charge_id = null,
                provider_payment_reference = null,
                provider_total_minor = null,
                status = 'pending',
                subtotal_excluding_tax_minor = null,
                tax_amount_minor = null
            where event_purchase_id = $1::uuid
            ",
            &[&reconcile_purchase_id()],
        )
        .await?;

    Ok(())
}

/// Builds a webhook reconciler backed by `pool` and a mock provider returning
/// the contract financial context for `session_id`.
fn sample_contract_reconciler(pool: Pool, session_id: &'static str) -> PaymentsWebhookReconciler {
    let mut provider = MockPaymentsProvider::new();
    provider.expect_provider().return_const(PaymentProvider::Stripe);
    provider
        .expect_get_checkout_financial_context()
        .withf(move |input| {
            input.connected_seller_id == CONTRACT_CONNECTED_ACCOUNT_ID
                && input.provider_session_id == session_id
        })
        .times(1)
        .returning(|_| {
            Box::pin(async {
                Ok(CheckoutFinancialContext {
                    provider_charge_id: "ch_contract_reconcile".to_string(),
                    provider_payment_reference: "pi_contract_reconcile".to_string(),
                    provider_total_minor: 2_500,
                    tax_amount_minor: 0,

                    provider_application_fee_id: None,
                })
            })
        });

    PaymentsWebhookReconciler::new(
        Arc::new(PgDB::new(pool)) as DynDB,
        Arc::new(provider),
        HttpServerConfig::default(),
    )
}

/// Creates a single-connection server pool whose 5-second wait timeout causes
/// any nested pool checkout inside an open transaction to fail.
fn single_connection_pool() -> Result<Pool> {
    let mut cfg = contract_tests_config()?;
    cfg.pool = Some(PoolConfig::new(1));

    create_pool(&cfg, NoTls)
}
