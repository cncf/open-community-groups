import { expect } from "@open-wc/testing";

import {
  createNoEmptyValuesExtension,
  registerHtmxNoEmptyValuesExtensions,
} from "/static/js/common/htmx-extensions.js";

const formDataToEntries = (formData) => Array.from(formData.entries());

describe("htmx extensions", () => {
  it('registers both "no-empty-vals" variants', () => {
    const extensions = new Map();
    const htmxMock = {
      defineExtension: (name, extension) => extensions.set(name, extension),
    };

    registerHtmxNoEmptyValuesExtensions(htmxMock);

    expect(Array.from(extensions.keys())).to.deep.equal([
      "no-empty-vals",
      "no-empty-vals-keep-zero",
    ]);
  });

  it('drops empty strings and "0" for the default no-empty-vals extension', () => {
    const extension = createNoEmptyValuesExtension(true);
    const parameters = new FormData();
    parameters.append("blank", "   ");
    parameters.append("free_ticket_amount", "0");
    parameters.append("name", "  Spring meetup  ");

    extension.encodeParameters(null, parameters, null);

    expect(formDataToEntries(parameters)).to.deep.equal([["name", "Spring meetup"]]);
  });

  it('keeps "0" while still trimming and removing blank values for the keep-zero extension', () => {
    const extension = createNoEmptyValuesExtension(false);
    const parameters = new FormData();
    parameters.append("blank", "   ");
    parameters.append("free_ticket_amount", "0");
    parameters.append("name", "  Spring meetup  ");

    extension.encodeParameters(null, parameters, null);

    expect(formDataToEntries(parameters)).to.deep.equal([
      ["free_ticket_amount", "0"],
      ["name", "Spring meetup"],
    ]);
  });

  it("keeps free ticket amount_minor values during event-style request encoding", () => {
    const extension = createNoEmptyValuesExtension(false);
    const parameters = new FormData();
    parameters.append("ticket_types_present", "true");
    parameters.append("ticket_types[0][title]", "Free entry");
    parameters.append("ticket_types[0][price_windows][0][amount_minor]", "0");
    parameters.append("discount_codes[0][amount_minor]", "0");
    parameters.append("description_short", "   ");

    extension.encodeParameters(null, parameters, null);

    expect(formDataToEntries(parameters)).to.deep.equal([
      ["ticket_types_present", "true"],
      ["ticket_types[0][title]", "Free entry"],
      ["ticket_types[0][price_windows][0][amount_minor]", "0"],
      ["discount_codes[0][amount_minor]", "0"],
    ]);
  });

  it("filters GET formData through onEvent with the same keep-zero behavior", () => {
    const extension = createNoEmptyValuesExtension(false);
    const formData = new FormData();
    formData.append("blank", " ");
    formData.append("amount_minor", "0");
    formData.append("title", "  Free entry  ");
    const event = {
      detail: {
        formData,
        parameters: formData,
        useUrlParams: true,
        verb: "get",
      },
    };

    const handled = extension.onEvent("htmx:configRequest", event);

    expect(handled).to.equal(true);
    expect(formDataToEntries(event.detail.formData)).to.deep.equal([
      ["amount_minor", "0"],
      ["title", "Free entry"],
    ]);
    expect(event.detail.parameters).to.equal(event.detail.formData);
  });
});
