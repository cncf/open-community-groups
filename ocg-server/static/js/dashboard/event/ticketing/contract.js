import {
  formatMinorUnitsForInput,
  parseCurrencyInputToMinorUnits,
} from "/static/js/dashboard/event/ticketing/money.js";
import {
  toDateTimeLocalInTimezone,
  toUtcIsoInTimezone,
} from "/static/js/dashboard/event/ticketing/datetime.js";
import { toBoolean, toTrimmedString } from "/static/js/dashboard/event/ticketing/shared.js";

/**
 * Normalizes incoming ticket types into editor rows.
 * @param {object} config Normalization config
 * @returns {Array<object>}
 */
export const normalizeTicketTypes = ({ currencyCode, nextRowId, ticketTypes, timezone }) => {
  if (!Array.isArray(ticketTypes) || ticketTypes.length === 0) {
    return [];
  }

  return ticketTypes.map((ticketType) => {
    const priceWindows = Array.isArray(ticketType?.price_windows)
      ? ticketType.price_windows.map((windowRow) => ({
          _row_id: nextRowId(),
          amount:
            windowRow?.amount_minor === null || windowRow?.amount_minor === undefined
              ? ""
              : formatMinorUnitsForInput(windowRow.amount_minor, currencyCode),
          ends_at: toDateTimeLocalInTimezone(windowRow?.ends_at || "", timezone),
          event_ticket_price_window_id: toTrimmedString(windowRow?.event_ticket_price_window_id),
          starts_at: toDateTimeLocalInTimezone(windowRow?.starts_at || "", timezone),
        }))
      : [];

    return {
      _row_id: nextRowId(),
      active: toBoolean(ticketType?.active, true),
      description: String(ticketType?.description || ""),
      event_ticket_type_id: toTrimmedString(ticketType?.event_ticket_type_id),
      price_windows: priceWindows,
      seats_total:
        ticketType?.seats_total === null || ticketType?.seats_total === undefined
          ? ""
          : String(ticketType.seats_total),
      title: String(ticketType?.title || ""),
    };
  });
};

/**
 * Builds hidden input entries for ticket types.
 * @param {object} config Serialization config
 * @returns {Array<{name: string, value: string}>}
 */
export const serializeTicketTypes = ({ currencyCode, fieldNamePrefix, rows, timezone }) =>
  rows.flatMap((row, index) => {
    const rowPrefix = `${fieldNamePrefix}[${index}]`;
    const description = toTrimmedString(row.description);
    const fields = [
      { name: `${rowPrefix}[active]`, value: row.active ? "true" : "false" },
      { name: `${rowPrefix}[order]`, value: String(index + 1) },
      { name: `${rowPrefix}[title]`, value: row.title.trim() },
    ];
    const rowId = toTrimmedString(row.event_ticket_type_id);
    const seatsTotal = Number.parseInt(row.seats_total, 10);

    if (description) {
      fields.push({ name: `${rowPrefix}[description]`, value: description });
    }

    if (rowId) {
      fields.push({ name: `${rowPrefix}[event_ticket_type_id]`, value: rowId });
    }

    if (Number.isFinite(seatsTotal)) {
      fields.push({ name: `${rowPrefix}[seats_total]`, value: String(seatsTotal) });
    }

    return [
      ...fields,
      ...row.price_windows.flatMap((windowRow, windowIndex) => {
        const windowPrefix = `${rowPrefix}[price_windows][${windowIndex}]`;
        const windowFields = [];
        const amountMinor = parseCurrencyInputToMinorUnits(windowRow.amount, currencyCode);
        const endsAt = toUtcIsoInTimezone(windowRow.ends_at, timezone);
        const startsAt = toUtcIsoInTimezone(windowRow.starts_at, timezone);
        const windowId = toTrimmedString(windowRow.event_ticket_price_window_id);

        if (amountMinor !== null) {
          windowFields.push({
            name: `${windowPrefix}[amount_minor]`,
            value: String(amountMinor),
          });
        }

        if (endsAt) {
          windowFields.push({ name: `${windowPrefix}[ends_at]`, value: endsAt });
        }

        if (windowId) {
          windowFields.push({
            name: `${windowPrefix}[event_ticket_price_window_id]`,
            value: windowId,
          });
        }

        if (startsAt) {
          windowFields.push({ name: `${windowPrefix}[starts_at]`, value: startsAt });
        }

        return windowFields;
      }),
    ];
  });

/**
 * Normalizes incoming discount codes into editor rows.
 * @param {object} config Normalization config
 * @returns {Array<object>}
 */
export const normalizeDiscountCodes = ({ currencyCode, discountCodes, nextRowId, timezone }) => {
  if (!Array.isArray(discountCodes) || discountCodes.length === 0) {
    return [];
  }

  return discountCodes
    .map((discountCode) => ({
      _row_id: nextRowId(),
      active: toBoolean(discountCode?.active, true),
      amount:
        discountCode?.amount_minor === null || discountCode?.amount_minor === undefined
          ? ""
          : formatMinorUnitsForInput(discountCode.amount_minor, currencyCode),
      available:
        discountCode?.available === null || discountCode?.available === undefined
          ? ""
          : String(discountCode.available),
      available_dirty: false,
      code: toTrimmedString(discountCode?.code).toUpperCase(),
      ends_at: toDateTimeLocalInTimezone(discountCode?.ends_at || "", timezone),
      event_discount_code_id: toTrimmedString(discountCode?.event_discount_code_id),
      kind: toTrimmedString(discountCode?.kind) || "percentage",
      percentage:
        discountCode?.percentage === null || discountCode?.percentage === undefined
          ? ""
          : String(discountCode.percentage),
      starts_at: toDateTimeLocalInTimezone(discountCode?.starts_at || "", timezone),
      title: String(discountCode?.title || ""),
      total_available:
        discountCode?.total_available === null || discountCode?.total_available === undefined
          ? ""
          : String(discountCode.total_available),
    }))
    .sort((left, right) => left.title.trim().toLowerCase().localeCompare(right.title.trim().toLowerCase()));
};

/**
 * Builds hidden input entries for discount codes.
 * @param {object} config Serialization config
 * @returns {Array<{name: string, value: string}>}
 */
export const serializeDiscountCodes = ({ currencyCode, fieldNamePrefix, rows, timezone }) =>
  rows.flatMap((row, index) => {
    const rowPrefix = `${fieldNamePrefix}[${index}]`;
    const amountMinor = parseCurrencyInputToMinorUnits(row.amount, currencyCode);
    const available = Number.parseInt(row.available, 10);
    const availableValue = toTrimmedString(row.available);
    const discountCodeId = toTrimmedString(row.event_discount_code_id);
    const endsAt = toUtcIsoInTimezone(row.ends_at, timezone);
    const percentage = Number.parseInt(row.percentage, 10);
    const startsAt = toUtcIsoInTimezone(row.starts_at, timezone);
    const totalAvailable = Number.parseInt(row.total_available, 10);
    const fields = [
      { name: `${rowPrefix}[active]`, value: row.active ? "true" : "false" },
      { name: `${rowPrefix}[code]`, value: row.code.trim().toUpperCase() },
      { name: `${rowPrefix}[kind]`, value: row.kind },
      { name: `${rowPrefix}[title]`, value: row.title.trim() },
    ];

    if (row.available_dirty) {
      if (Number.isFinite(available)) {
        fields.push({ name: `${rowPrefix}[available]`, value: String(available) });
      } else if (!availableValue) {
        fields.push({ name: `${rowPrefix}[available_cleared]`, value: "true" });
      }
    }

    if (row.kind === "fixed_amount" && amountMinor !== null) {
      fields.push({ name: `${rowPrefix}[amount_minor]`, value: String(amountMinor) });
    }

    if (endsAt) {
      fields.push({ name: `${rowPrefix}[ends_at]`, value: endsAt });
    }

    if (discountCodeId) {
      fields.push({ name: `${rowPrefix}[event_discount_code_id]`, value: discountCodeId });
    }

    if (row.kind === "percentage" && Number.isFinite(percentage)) {
      fields.push({ name: `${rowPrefix}[percentage]`, value: String(percentage) });
    }

    if (startsAt) {
      fields.push({ name: `${rowPrefix}[starts_at]`, value: startsAt });
    }

    if (Number.isFinite(totalAvailable)) {
      fields.push({
        name: `${rowPrefix}[total_available]`,
        value: String(totalAvailable),
      });
    }

    return fields;
  });
