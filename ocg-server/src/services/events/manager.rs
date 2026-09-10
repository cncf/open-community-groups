//! Events manager for organizer-facing event mutations.

use std::{collections::HashMap, sync::Arc};

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
#[cfg(test)]
use mockall::automock;
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, MeetingsConfig},
    db::{DBExt, DBOperations, DynDB},
    services::{
        notifications::enqueue::{
            enqueue_event_canceled_notification, enqueue_event_paid_configured_notifications,
            enqueue_event_published_notifications, enqueue_event_rescheduled_notification,
            enqueue_event_series_canceled_notifications,
            enqueue_event_series_published_notifications,
        },
        payments::{
            AutomaticTaxReadiness, AutomaticTaxReadinessError, DynPaymentsManager,
            FiscalSponsorReadinessError,
        },
    },
    types::{
        dashboard::group::events::{EventActionScope, EventInput},
        event::EventSummary,
        meetings::MeetingProvider,
        payments::{
            PaymentConfigurationValidation, TicketTaxBehavior, TicketTaxCalculationMode,
            TicketTaxRate,
        },
    },
};

use super::recurrence::RecurringEventPayloads;

#[cfg(test)]
mod tests;

/// Trait implemented by the events manager used by handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait EventsManager {
    /// Creates a single event or a linked recurring event series.
    ///
    /// Returns the created event identifiers with the base event first.
    async fn add(&self, input: &AddEventInput) -> Result<Vec<Uuid>, EventsError>;

    /// Cancels the selected event or its whole linked series.
    async fn cancel(&self, input: &EventActionInput) -> Result<(), EventsError>;

    /// Checks a saved event's venue with the configured automatic-tax provider.
    async fn check_automatic_tax_readiness(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<AutomaticTaxReadiness, AutomaticTaxCheckError>;

    /// Deletes the selected event or its whole linked series.
    async fn delete(&self, input: &EventActionInput) -> Result<(), EventsError>;

    /// Lists the group's active fiscal-sponsor Tax Rates for a tax behavior.
    async fn list_tax_rates(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        tax_behavior: TicketTaxBehavior,
    ) -> Result<Vec<TicketTaxRate>, EventsError>;

    /// Publishes the selected event or its whole linked series.
    async fn publish(&self, input: &EventActionInput) -> Result<(), EventsError>;

    /// Unpublishes the selected event or its whole linked series.
    async fn unpublish(&self, input: &EventActionInput) -> Result<(), EventsError>;

    /// Updates an existing event.
    async fn update(&self, input: &UpdateEventInput) -> Result<(), EventsError>;
}

/// Shared events manager trait object.
pub(crate) type DynEventsManager = Arc<dyn EventsManager + Send + Sync>;

/// PostgreSQL-backed events manager implementation.
pub(crate) struct PgEventsManager {
    /// Database handle for event persistence.
    db: DynDB,
    /// Maximum participants per configured meetings provider.
    meetings_max_participants: HashMap<MeetingProvider, i32>,
    /// Payments manager used for fiscal sponsor validation.
    payments_manager: DynPaymentsManager,
    /// Server configuration used to build notification links.
    server_cfg: HttpServerConfig,
}

impl PgEventsManager {
    /// Creates a new `PgEventsManager`.
    pub(crate) fn new(
        db: DynDB,
        meetings_cfg: Option<&MeetingsConfig>,
        payments_manager: DynPaymentsManager,
        server_cfg: HttpServerConfig,
    ) -> Self {
        Self {
            db,
            meetings_max_participants: meetings_cfg
                .map(MeetingsConfig::max_participants_by_provider)
                .unwrap_or_default(),
            payments_manager,
            server_cfg,
        }
    }

    /// Validates the configured group sponsor before paid event configuration is persisted.
    async fn validate_group_fiscal_sponsor(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event: &EventInput,
    ) -> Result<PaymentConfigurationValidation, EventsError> {
        // Snapshot tax inputs from the event form before contacting the provider
        let jurisdiction = event.ticket_venue().valid_tax_jurisdiction();
        let manual_tax_rate_ids = event.manual_tax_rate_ids.as_deref().unwrap_or_default();
        let tax_behavior = event.tax_behavior;
        let tax_calculation_mode = event.tax_calculation_mode;

        // Load the current recipient before validating its provider configuration
        let payment_recipient = self.db.get_group_payment_recipient(community_id, group_id).await?;

        // Validate sponsor readiness and any manual Tax Rate selection
        if let Some(recipient) = payment_recipient.as_ref() {
            let automatic_tax_jurisdiction =
                if tax_calculation_mode == TicketTaxCalculationMode::Automatic {
                    jurisdiction.clone()
                } else {
                    None
                };
            self.payments_manager
                .validate_fiscal_sponsor(recipient, automatic_tax_jurisdiction)
                .await?;

            // Recheck manual rate ownership and display behavior
            if tax_calculation_mode == TicketTaxCalculationMode::Manual {
                self.payments_manager
                    .validate_tax_rates(
                        recipient,
                        manual_tax_rate_ids,
                        tax_behavior,
                        jurisdiction.clone(),
                    )
                    .await?;
            }
        } else if tax_calculation_mode == TicketTaxCalculationMode::Manual
            && !manual_tax_rate_ids.is_empty()
        {
            // Reject manual Tax Rate selections without a connected sponsor
            return Err(EventsError::Rejected(
                "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
            ));
        }

        // Bind the validated configuration to the pending database mutation
        Ok(PaymentConfigurationValidation {
            require_automatic_tax: tax_calculation_mode == TicketTaxCalculationMode::Automatic,

            expected_payment_recipient: payment_recipient.clone(),
            manual_tax_rate_ids: Some(manual_tax_rate_ids.to_vec()),
            tax_behavior: Some(tax_behavior),
            tax_calculation_mode: Some(tax_calculation_mode),
            validated_payment_recipient: payment_recipient,
        })
    }

    /// Validates the selected sponsor against every paid event about to be published.
    async fn validate_publish_fiscal_sponsor(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event_ids: &[Uuid],
    ) -> Result<Option<PaymentConfigurationValidation>, EventsError> {
        let mut events = Vec::new();
        let mut paid_events = Vec::new();
        let mut require_automatic_tax = false;

        // Load each event and aggregate the strongest paid sponsor readiness need
        for event_id in event_ids {
            let event = self.db.get_event_full(community_id, group_id, *event_id).await?;
            if event.is_paid_capable() && event.external_payment_url.is_none() {
                require_automatic_tax |=
                    event.tax_calculation_mode == TicketTaxCalculationMode::Automatic;
                paid_events.push(event.clone());
            }
            events.push(event);
        }

        // Select manual-tax events whose rates must be revalidated
        let manual_events = events
            .iter()
            .filter(|event| {
                event.external_payment_url.is_none()
                    && event.tax_calculation_mode == TicketTaxCalculationMode::Manual
                    && (event.is_paid_capable() || !event.manual_tax_rate_ids.is_empty())
            })
            .collect::<Vec<_>>();

        // Skip provider validation when the publish set has no applicable tax state
        if paid_events.is_empty() && manual_events.is_empty() {
            return Ok(None);
        }

        // Validate the sponsor once, then recheck every applicable manual selection
        let payment_recipient = self.db.get_group_payment_recipient(community_id, group_id).await?;
        if let Some(recipient) = payment_recipient.as_ref() {
            self.payments_manager.validate_fiscal_sponsor(recipient, None).await?;
            for event in paid_events
                .iter()
                .filter(|event| event.tax_calculation_mode == TicketTaxCalculationMode::Automatic)
            {
                self.payments_manager
                    .ensure_automatic_tax_readiness(recipient, &event.ticket_venue())
                    .await?;
            }
            for event in manual_events {
                let jurisdiction = event.ticket_venue().valid_tax_jurisdiction();
                self.payments_manager
                    .validate_tax_rates(
                        recipient,
                        &event.manual_tax_rate_ids,
                        event.tax_behavior,
                        jurisdiction,
                    )
                    .await?;
            }
        } else if paid_events
            .iter()
            .any(|event| event.tax_calculation_mode == TicketTaxCalculationMode::Automatic)
        {
            return Err(EventsError::Rejected(
                "configure a fiscal sponsor before publishing this automatic-tax event".to_string(),
            ));
        } else if events.iter().any(|event| {
            event.tax_calculation_mode == TicketTaxCalculationMode::Manual
                && !event.manual_tax_rate_ids.is_empty()
        }) {
            return Err(EventsError::Rejected(
                "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
            ));
        }

        // Bind the first paid event's configuration to the publish mutation
        let Some(first_event) = paid_events.first() else {
            return Ok(None);
        };
        Ok(Some(PaymentConfigurationValidation {
            require_automatic_tax,

            expected_payment_recipient: payment_recipient.clone(),
            manual_tax_rate_ids: Some(first_event.manual_tax_rate_ids.clone()),
            tax_behavior: Some(first_event.tax_behavior),
            tax_calculation_mode: Some(first_event.tax_calculation_mode),
            validated_payment_recipient: payment_recipient,
        }))
    }
}

#[async_trait]
impl EventsManager for PgEventsManager {
    /// [`EventsManager::add`].
    async fn add(&self, input: &AddEventInput) -> Result<Vec<Uuid>, EventsError> {
        let AddEventInput {
            actor_user_id,
            community_id,
            group_id,
            ..
        } = *input;
        let event = &input.event;

        // Prepare and classify the event payload
        let payment_provider = self.payments_manager.configured_provider();
        let mut event_payload = event.to_db_payload()?;
        let is_paid_capable = is_event_payload_paid_capable(&event_payload);

        // Validate the group fiscal sponsor with the provider before persisting a
        // paid event, embedding the validated recipient in the payload so the
        // database can verify it did not change before committing
        if event.external_payment_url.is_none()
            && ((payment_provider.is_some() && is_paid_capable) || event.has_manual_tax_selection())
        {
            let payment_validation = self
                .validate_group_fiscal_sponsor(community_id, group_id, event)
                .await?;
            bind_payment_validation(&mut event_payload, &payment_validation)?;
        }

        // Expand the recurrence request into the series payloads
        let recurring_event_payloads = RecurringEventPayloads::from_event(event, &event_payload)
            .map_err(|err| EventsError::Rejected(err.to_string()))?;

        // Persist the events and required notifications atomically
        let cfg_max_participants = self.meetings_max_participants.clone();
        let event_ids = self
            .db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Create either a single event or a linked recurring event series
                    let event_ids = if let Some(recurring_event_payloads) = recurring_event_payloads
                    {
                        tx.add_event_series(
                            actor_user_id,
                            group_id,
                            &recurring_event_payloads.events,
                            &recurring_event_payloads.recurrence,
                            &cfg_max_participants,
                            payment_provider,
                        )
                        .await?
                    } else {
                        vec![
                            tx.add_event(
                                actor_user_id,
                                group_id,
                                &event_payload,
                                &cfg_max_participants,
                                payment_provider,
                            )
                            .await?,
                        ]
                    };

                    // Enqueue required admin notifications before committing paid events
                    if is_paid_capable {
                        enqueue_event_paid_configured_notifications(
                            tx,
                            community_id,
                            group_id,
                            &event_ids,
                        )
                        .await?;
                    }

                    Ok(event_ids)
                })
            })
            .await?;

        // Require the identifier the caller uses to reload the editor
        if event_ids.is_empty() {
            return Err(EventsError::Other(anyhow!(
                "created event without an identifier"
            )));
        }

        Ok(event_ids)
    }

    /// [`EventsManager::cancel`].
    async fn cancel(&self, input: &EventActionInput) -> Result<(), EventsError> {
        let EventActionInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            scope,
        } = *input;
        let now = Utc::now();
        let server_cfg = self.server_cfg.clone();

        // Cancel the events and enqueue the required notifications atomically
        self.db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Resolve and lock cancellation targets before attendance can change
                    let event_ids = cancel_event_action_ids(tx, group_id, event_id, scope).await?;
                    tx.lock_events_for_cancellation(group_id, &event_ids).await?;

                    // Load summaries while locks preserve notification eligibility and recipients
                    let mut events = Vec::with_capacity(event_ids.len());
                    for event_id in &event_ids {
                        events.push(tx.get_event_summary(community_id, group_id, *event_id).await?);
                    }

                    // Snapshot and enqueue cancellation recipients before attendance is deactivated
                    let events_to_notify = cancellation_notification_events(events, now);
                    match (scope, events_to_notify.as_slice()) {
                        // Multiple notifiable events
                        (EventActionScope::Series, [_, _, ..]) => {
                            let event_ids: Vec<Uuid> =
                                events_to_notify.iter().map(|event| event.event_id).collect();
                            enqueue_event_series_canceled_notifications(
                                tx,
                                &server_cfg,
                                community_id,
                                group_id,
                                &event_ids,
                            )
                            .await?;
                        }
                        // Single notifiable event
                        (_, [event]) => {
                            enqueue_event_canceled_notification(
                                tx,
                                &server_cfg,
                                community_id,
                                group_id,
                                event.event_id,
                            )
                            .await?;
                        }
                        _ => {}
                    }

                    // Mark the selected event or the whole linked series as canceled
                    match scope {
                        EventActionScope::Series => {
                            tx.cancel_event_series_events(actor_user_id, group_id, &event_ids)
                                .await?;
                        }
                        EventActionScope::This => {
                            tx.cancel_event(actor_user_id, group_id, event_id).await?;
                        }
                    }

                    Ok(())
                })
            })
            .await?;

        Ok(())
    }

    /// [`EventsManager::check_automatic_tax_readiness`].
    async fn check_automatic_tax_readiness(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        event_id: Uuid,
    ) -> Result<AutomaticTaxReadiness, AutomaticTaxCheckError> {
        // Load only persisted event and sponsor data for this explicit check
        let (event, payment_recipient) = tokio::try_join!(
            self.db.get_event_full(community_id, group_id, event_id),
            self.db.get_group_payment_recipient(community_id, group_id),
        )?;
        let Some(payment_recipient) = payment_recipient else {
            return Err(AutomaticTaxReadinessError::FiscalSponsorNotReady(
                "configure a fiscal sponsor before checking automatic tax".to_string(),
            )
            .into());
        };

        // Create or reuse the provider performance location for the venue
        let readiness = self
            .payments_manager
            .ensure_automatic_tax_readiness(&payment_recipient, &event.ticket_venue())
            .await?;

        Ok(readiness)
    }

    /// [`EventsManager::delete`].
    async fn delete(&self, input: &EventActionInput) -> Result<(), EventsError> {
        let EventActionInput {
            actor_user_id,
            event_id,
            group_id,
            scope,
            ..
        } = *input;

        // Delete the selected event or the whole linked series
        match scope {
            EventActionScope::Series => {
                let event_ids =
                    event_action_ids(self.db.as_ref(), group_id, event_id, scope).await?;
                self.db
                    .delete_event_series_events(actor_user_id, group_id, &event_ids)
                    .await?;
            }
            EventActionScope::This => {
                self.db.delete_event(actor_user_id, group_id, event_id).await?;
            }
        }

        Ok(())
    }

    /// [`EventsManager::list_tax_rates`].
    async fn list_tax_rates(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        tax_behavior: TicketTaxBehavior,
    ) -> Result<Vec<TicketTaxRate>, EventsError> {
        // Load and validate the connected fiscal sponsor that owns the rates
        let recipient = self
            .db
            .get_group_payment_recipient(community_id, group_id)
            .await?
            .ok_or_else(|| {
                EventsError::Rejected(
                    "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
                )
            })?;
        self.payments_manager
            .validate_fiscal_sponsor(&recipient, None)
            .await?;

        // Return active rates matching the requested inclusive or exclusive behavior
        let rates = self.payments_manager.list_tax_rates(&recipient, tax_behavior).await?;

        Ok(rates)
    }

    /// [`EventsManager::publish`].
    async fn publish(&self, input: &EventActionInput) -> Result<(), EventsError> {
        let EventActionInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            scope,
        } = *input;
        let now = Utc::now();
        let server_cfg = self.server_cfg.clone();

        // Validate the group fiscal sponsor with the provider before publishing
        // paid events, passing the validated recipient to the database so it can
        // verify it did not change before committing
        let payment_provider = self.payments_manager.configured_provider();
        let payment_validation = if payment_provider.is_some() {
            let event_ids = match scope {
                EventActionScope::Series => {
                    self.db
                        .list_event_series_publishable_event_ids(group_id, event_id)
                        .await?
                }
                EventActionScope::This => vec![event_id],
            };
            self.validate_publish_fiscal_sponsor(community_id, group_id, &event_ids)
                .await?
        } else {
            None
        };

        // Publish the events and enqueue the required notifications atomically
        self.db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Resolve and lock target events before loading notification state
                    let event_ids = match scope {
                        EventActionScope::Series => {
                            tx.list_event_series_publishable_event_ids(group_id, event_id).await?
                        }
                        EventActionScope::This => vec![event_id],
                    };
                    tx.lock_group_events(group_id, &event_ids).await?;

                    // Load prior state while locks preserve publication eligibility
                    let mut events = Vec::with_capacity(event_ids.len());
                    for event_id in &event_ids {
                        events.push(tx.get_event_summary(community_id, group_id, *event_id).await?);
                    }

                    // Publish the selected event or the whole linked series
                    match scope {
                        EventActionScope::Series => {
                            tx.publish_event_series_events(
                                actor_user_id,
                                group_id,
                                &event_ids,
                                payment_provider,
                                payment_validation.clone(),
                            )
                            .await?;
                        }
                        EventActionScope::This => {
                            tx.publish_event(
                                actor_user_id,
                                group_id,
                                event_id,
                                payment_provider,
                                payment_validation.clone(),
                            )
                            .await?;
                        }
                    }

                    // Enqueue required publish notifications before committing
                    let events_to_notify = publication_notification_events(events, now);
                    match (scope, events_to_notify.as_slice()) {
                        // Multiple notifiable events
                        (EventActionScope::Series, [_, _, ..]) => {
                            let event_ids: Vec<Uuid> =
                                events_to_notify.iter().map(|event| event.event_id).collect();
                            enqueue_event_series_published_notifications(
                                tx,
                                &server_cfg,
                                community_id,
                                group_id,
                                &event_ids,
                            )
                            .await?;
                        }
                        // Single notifiable event
                        (_, [event]) => {
                            enqueue_event_published_notifications(
                                tx,
                                &server_cfg,
                                community_id,
                                group_id,
                                event.event_id,
                            )
                            .await?;
                        }
                        _ => {}
                    }

                    Ok(())
                })
            })
            .await?;

        Ok(())
    }

    /// [`EventsManager::unpublish`].
    async fn unpublish(&self, input: &EventActionInput) -> Result<(), EventsError> {
        let EventActionInput {
            actor_user_id,
            event_id,
            group_id,
            scope,
            ..
        } = *input;

        // Unpublish the selected event or the whole linked series
        match scope {
            EventActionScope::Series => {
                let event_ids =
                    event_action_ids(self.db.as_ref(), group_id, event_id, scope).await?;
                self.db
                    .unpublish_event_series_events(actor_user_id, group_id, &event_ids)
                    .await?;
            }
            EventActionScope::This => {
                self.db.unpublish_event(actor_user_id, group_id, event_id).await?;
            }
        }

        Ok(())
    }

    /// [`EventsManager::update`].
    async fn update(&self, input: &UpdateEventInput) -> Result<(), EventsError> {
        let UpdateEventInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            ..
        } = *input;
        let event = &input.event;
        let now = Utc::now();

        // Prepare the update payload and ticketing prerequisites
        let payment_provider = self.payments_manager.configured_provider();
        let mut event_json = event.to_db_payload()?;

        // Validate the group fiscal sponsor with the provider when the update
        // changes the ticketing configuration, embedding the validated recipient
        // in the payload so the database can verify it did not change before
        // committing
        let ticketing_configuration_changed = if payment_provider.is_some() {
            self.db
                .event_ticketing_configuration_changed(
                    community_id,
                    group_id,
                    event_id,
                    &event_json,
                )
                .await?
        } else {
            false
        };
        if event.external_payment_url.is_none()
            && (ticketing_configuration_changed || event.has_manual_tax_selection())
        {
            let payment_validation = self
                .validate_group_fiscal_sponsor(community_id, group_id, event)
                .await?;
            bind_payment_validation(&mut event_json, &payment_validation)?;
        }

        // Revalidate provider location readiness before changing a published automatic-tax event
        if event.external_payment_url.is_none()
            && ticketing_configuration_changed
            && event.tax_calculation_mode == TicketTaxCalculationMode::Automatic
            && is_event_payload_paid_capable(&event_json)
        {
            let persisted_event = self.db.get_event_full(community_id, group_id, event_id).await?;
            if persisted_event.published {
                let payment_recipient = self
                    .db
                    .get_group_payment_recipient(community_id, group_id)
                    .await?
                    .ok_or_else(|| {
                        EventsError::Rejected(
                            "configure a fiscal sponsor before updating this published event"
                                .to_string(),
                        )
                    })?;
                self.payments_manager
                    .ensure_automatic_tax_readiness(&payment_recipient, &event.ticket_venue())
                    .await?;
            }
        }

        // Persist the update and required notifications atomically
        let cfg_max_participants = self.meetings_max_participants.clone();
        let server_cfg = self.server_cfg.clone();
        self.db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Lock the group and event before loading notification state
                    tx.lock_group_events(group_id, &[event_id]).await?;

                    // Load prior state before mutating to drive notification decisions
                    let before = tx.get_event_summary(community_id, group_id, event_id).await?;

                    // Update the event
                    let requires_paid_notification = tx
                        .update_event(
                            actor_user_id,
                            group_id,
                            event_id,
                            &event_json,
                            &cfg_max_participants,
                            payment_provider,
                        )
                        .await?;

                    // Enqueue required admin notification after entering the notifiable paid state
                    if requires_paid_notification {
                        enqueue_event_paid_configured_notifications(
                            tx,
                            community_id,
                            group_id,
                            &[event_id],
                        )
                        .await?;
                    }

                    // Enqueue required reschedule notifications before committing
                    enqueue_event_rescheduled_notification(
                        tx,
                        &server_cfg,
                        community_id,
                        group_id,
                        event_id,
                        &before,
                        now,
                    )
                    .await?;

                    Ok(())
                })
            })
            .await?;

        Ok(())
    }
}

// Types.

/// Parameters used to create an event or event series.
#[derive(Clone, Debug)]
pub(crate) struct AddEventInput {
    /// Organizer creating the event.
    pub actor_user_id: Uuid,
    /// Community containing the group.
    pub community_id: Uuid,
    /// Validated event form.
    pub event: EventInput,
    /// Group organizing the event.
    pub group_id: Uuid,
}

/// Errors returned by the explicit automatic-tax readiness check.
///
/// Keeps failures loading the event and sponsor context distinguishable from
/// the organizer-facing readiness outcome so handlers preserve the regular
/// error contract for the former.
#[derive(Debug, thiserror::Error)]
pub(crate) enum AutomaticTaxCheckError {
    /// Failure loading the persisted event or fiscal sponsor context.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
    /// Readiness outcome decided by the manager or the provider.
    #[error(transparent)]
    Readiness(#[from] AutomaticTaxReadinessError),
}

/// Parameters shared by scoped event actions.
#[derive(Clone, Copy, Debug)]
pub(crate) struct EventActionInput {
    /// Organizer performing the action.
    pub actor_user_id: Uuid,
    /// Community containing the group.
    pub community_id: Uuid,
    /// Selected event.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,
    /// Whether the action applies to the event or its linked series.
    pub scope: EventActionScope,
}

/// Errors returned by event management workflows.
#[derive(Debug, thiserror::Error)]
pub(crate) enum EventsError {
    /// Internal failure, including database and provider errors.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
    /// User-facing business rejection decided by the manager or the provider.
    #[error("{0}")]
    Rejected(String),
}

impl From<AutomaticTaxReadinessError> for EventsError {
    fn from(err: AutomaticTaxReadinessError) -> Self {
        match err {
            AutomaticTaxReadinessError::Unexpected(err) => Self::Other(err),
            err => Self::Rejected(err.to_string()),
        }
    }
}

impl From<FiscalSponsorReadinessError> for EventsError {
    fn from(err: FiscalSponsorReadinessError) -> Self {
        match err {
            FiscalSponsorReadinessError::NotReady(message) => Self::Rejected(message),
            FiscalSponsorReadinessError::Unexpected(err) => Self::Other(err),
        }
    }
}

/// Parameters used to update an event.
#[derive(Clone, Debug)]
pub(crate) struct UpdateEventInput {
    /// Organizer updating the event.
    pub actor_user_id: Uuid,
    /// Community containing the group.
    pub community_id: Uuid,
    /// Validated event form.
    pub event: EventInput,
    /// Event being updated.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,
}

// Helpers.

/// Embeds provider validation into the payload committed after database locking.
fn bind_payment_validation(
    event: &mut serde_json::Value,
    payment_validation: &PaymentConfigurationValidation,
) -> Result<()> {
    let event = event
        .as_object_mut()
        .ok_or_else(|| anyhow!("event payload must be an object"))?;
    event.insert(
        "_payment_validation".to_string(),
        serde_json::to_value(payment_validation)?,
    );

    Ok(())
}

/// Resolves the non-completed event identifiers affected by cancellation.
async fn cancel_event_action_ids(
    db: &dyn DBOperations,
    group_id: Uuid,
    event_id: Uuid,
    scope: EventActionScope,
) -> Result<Vec<Uuid>> {
    if scope == EventActionScope::This {
        return Ok(vec![event_id]);
    }

    let event_ids = db.list_event_series_cancelable_event_ids(group_id, event_id).await?;
    if event_ids.is_empty() {
        Ok(vec![event_id])
    } else {
        Ok(event_ids)
    }
}

/// Selects the events whose cancellation is announced: published, not yet
/// canceled, not test events, and not already past at `now`.
fn cancellation_notification_events(
    events: Vec<EventSummary>,
    now: DateTime<Utc>,
) -> Vec<EventSummary> {
    events
        .into_iter()
        .filter(|event| {
            event.published && !event.canceled && !event.test_event && !event.is_past_at(now)
        })
        .collect()
}

/// Resolves the event identifiers affected by a dashboard event action.
async fn event_action_ids(
    db: &dyn DBOperations,
    group_id: Uuid,
    event_id: Uuid,
    scope: EventActionScope,
) -> Result<Vec<Uuid>> {
    if scope == EventActionScope::This {
        return Ok(vec![event_id]);
    }

    let event_ids = db.list_event_series_event_ids(group_id, event_id).await?;
    if event_ids.is_empty() {
        Ok(vec![event_id])
    } else {
        Ok(event_ids)
    }
}

/// Returns whether a normalized event payload contains any positive ticket price.
fn is_event_payload_paid_capable(event: &serde_json::Value) -> bool {
    event
        .get("ticket_types")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|ticket_types| {
            ticket_types.iter().any(|ticket_type| {
                ticket_type
                    .get("price_windows")
                    .and_then(serde_json::Value::as_array)
                    .is_some_and(|price_windows| {
                        price_windows.iter().any(|price_window| {
                            price_window
                                .get("amount_minor")
                                .and_then(serde_json::Value::as_i64)
                                .is_some_and(|amount_minor| amount_minor > 0)
                        })
                    })
            })
        })
}

/// Selects the events whose publication is announced: previously unpublished,
/// not test events, and starting after `now`.
fn publication_notification_events(
    events: Vec<EventSummary>,
    now: DateTime<Utc>,
) -> Vec<EventSummary> {
    events
        .into_iter()
        .filter(|event| {
            matches!(
                (event.published, event.starts_at),
                (false, Some(starts_at)) if !event.test_event && starts_at > now
            )
        })
        .collect()
}
