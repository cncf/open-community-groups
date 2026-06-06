import { expect } from "@open-wc/testing";

import {
  createNoEmptyValuesExtension,
  handleCommitShaBeforeOnLoad,
  handleCommitShaBeforeSwap,
  handleCommitShaConfigRequest,
  handleDeclarativeHtmxResponse,
  handleNotFoundBeforeSwap,
  isSuccessfulRefreshBodyResponse,
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  REFRESH_HEADER,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";

// Convert form data into comparable entries.
const formDataToEntries = (formData) => Array.from(formData.entries());
const waitForDelay = (delay = 0) =>
  new Promise((resolve) => setTimeout(resolve, delay));

// Set the loaded commit SHA meta tag for deployment header checks.
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

describe("htmx extensions", () => {
  const originalDateNow = Date.now;
  let swal;

  beforeEach(() => {
    swal = mockSwal();
  });

  afterEach(() => {
    swal.restore();
    Date.now = originalDateNow;
    document.head.innerHTML = "";
    resetDeploymentReloadState();
  });

  it('registers both "no-empty-vals" variants', () => {
    // Capture extension registrations through a mock HTMX API.
    const extensions = new Map();
    const htmxMock = {
      defineExtension: (name, extension) => extensions.set(name, extension),
    };

    // Register both no-empty-values extension variants.
    registerHtmxNoEmptyValuesExtensions(htmxMock);

    // The default and keep-zero variants are both available by name.
    expect(Array.from(extensions.keys())).to.deep.equal(["no-empty-vals", "no-empty-vals-keep-zero"]);
  });

  it('drops empty strings and "0" for the default no-empty-vals extension', () => {
    // Build parameters with blank, zero, and trimmed string values.
    const extension = createNoEmptyValuesExtension(true);
    const parameters = new FormData();
    parameters.append("blank", "   ");
    parameters.append("free_ticket_amount", "0");
    parameters.append("name", "  Spring meetup  ");

    // Encode parameters with the default empty-value filtering.
    extension.encodeParameters(null, parameters, null);

    // Blank strings and zero values are removed while text is trimmed.
    expect(formDataToEntries(parameters)).to.deep.equal([["name", "Spring meetup"]]);
  });

  it('keeps "0" while still trimming and removing blank values for the keep-zero extension', () => {
    // Build parameters where zero is meaningful and blanks are not.
    const extension = createNoEmptyValuesExtension(false);
    const parameters = new FormData();
    parameters.append("blank", "   ");
    parameters.append("free_ticket_amount", "0");
    parameters.append("name", "  Spring meetup  ");

    // Encode parameters with keep-zero filtering.
    extension.encodeParameters(null, parameters, null);

    // Zero values are preserved while blank strings are removed.
    expect(formDataToEntries(parameters)).to.deep.equal([
      ["free_ticket_amount", "0"],
      ["name", "Spring meetup"],
    ]);
  });

  it("keeps free ticket amount_minor values during event-style request encoding", () => {
    // Build ticketing parameters with free ticket and discount amounts.
    const extension = createNoEmptyValuesExtension(false);
    const parameters = new FormData();
    parameters.append("ticket_types_present", "true");
    parameters.append("ticket_types[0][title]", "Free entry");
    parameters.append("ticket_types[0][price_windows][0][amount_minor]", "0");
    parameters.append("discount_codes[0][amount_minor]", "0");
    parameters.append("description_short", "   ");

    // Encode event-style parameters without dropping free amounts.
    extension.encodeParameters(null, parameters, null);

    // Free amount_minor values remain while blank description fields are removed.
    expect(formDataToEntries(parameters)).to.deep.equal([
      ["ticket_types_present", "true"],
      ["ticket_types[0][title]", "Free entry"],
      ["ticket_types[0][price_windows][0][amount_minor]", "0"],
      ["discount_codes[0][amount_minor]", "0"],
    ]);
  });

  it("filters GET formData through onEvent with the same keep-zero behavior", () => {
    // Build a GET configRequest event with formData parameters.
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

    // Run the extension through the HTMX configRequest event hook.
    const handled = extension.onEvent("htmx:configRequest", event);

    // GET formData is filtered in place and kept as the request parameters.
    expect(handled).to.equal(true);
    expect(formDataToEntries(event.detail.formData)).to.deep.equal([
      ["amount_minor", "0"],
      ["title", "Free entry"],
    ]);
    expect(event.detail.parameters).to.equal(event.detail.formData);
  });

  it("allows marked not found pages to swap on htmx 404 responses", () => {
    // Build a marked 404 swap event from the server.
    const event = {
      detail: {
        isError: true,
        shouldSwap: false,
        xhr: {
          status: 404,
          getResponseHeader: (name) => (name === "X-OCG-Not-Found" ? "true" : null),
        },
      },
    };

    // Apply the not-found swap policy to the marked response.
    handleNotFoundBeforeSwap(event);

    // Marked not-found responses are allowed to swap without error state.
    expect(event.detail.shouldSwap).to.equal(true);
    expect(event.detail.isError).to.equal(false);
  });

  it("keeps unmarked 404 responses on the default htmx error path", () => {
    // Build an unmarked 404 swap event from the server.
    const event = {
      detail: {
        isError: true,
        shouldSwap: false,
        xhr: {
          status: 404,
          getResponseHeader: () => null,
        },
      },
    };

    // Apply the not-found swap policy to the unmarked response.
    handleNotFoundBeforeSwap(event);

    // Unmarked 404 responses stay on the default HTMX error path.
    expect(event.detail.shouldSwap).to.equal(false);
    expect(event.detail.isError).to.equal(true);
  });

  it("adds the loaded commit SHA to htmx request headers", () => {
    // Store the current page commit SHA.
    setLoadedCommitSha("abc123");
    const event = {
      detail: {
        headers: {
          Existing: "value",
        },
      },
    };

    // Attach the loaded commit SHA to outgoing HTMX headers.
    handleCommitShaConfigRequest(event);

    // Existing headers stay intact and the commit SHA header is added.
    expect(event.detail.headers).to.deep.equal({
      Existing: "value",
      [COMMIT_SHA_HEADER]: "abc123",
    });
  });

  it("records and owns htmx refresh headers before htmx handles them", () => {
    // Track reloads and build a beforeOnLoad event with the refresh header.
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const event = new CustomEvent("htmx:beforeOnLoad", {
      cancelable: true,
      detail: {
        xhr: {
          getResponseHeader: (name) => (name === REFRESH_HEADER ? "true" : null),
        },
      },
    });

    // Handle the refresh header before HTMX processes the response.
    handleCommitShaBeforeOnLoad(event);

    // The refresh response is owned and stores the pending alert marker.
    expect(event.defaultPrevented).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
  });

  it("owns htmx refresh headers without reloading during the refresh cooldown", () => {
    // Start inside the refresh cooldown window.
    Date.now = () => 1_000;
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });

    handleCommitShaBeforeOnLoad(
      new CustomEvent("htmx:beforeOnLoad", {
        cancelable: true,
        detail: {
          xhr: {
            getResponseHeader: (name) => (name === REFRESH_HEADER ? "true" : null),
          },
        },
      }),
    );
    resetDeploymentReloadState({ clearRefreshHistory: false });
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    Date.now = () => 1_000 + 4 * 60 * 1000;
    const event = new CustomEvent("htmx:beforeOnLoad", {
      cancelable: true,
      detail: {
        xhr: {
          getResponseHeader: (name) => (name === REFRESH_HEADER ? "true" : null),
        },
      },
    });

    handleCommitShaBeforeOnLoad(event);

    // Assert whether the event was prevented.
    expect(event.defaultPrevented).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(false);
  });

  it("cancels the swap and reloads when an htmx response comes from a newer commit", () => {
    // Store the current page commit SHA before a newer response arrives.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    const event = {
      detail: {
        shouldSwap: true,
        xhr: {
          getResponseHeader: (name) => (name === COMMIT_SHA_HEADER ? "def456" : null),
        },
      },
    };

    // Handle a beforeSwap response from a newer commit.
    handleCommitShaBeforeSwap(event);

    // Newer commit responses cancel the swap and request a reload.
    expect(event.detail.shouldSwap).to.equal(false);
    expect(reloads).to.equal(1);
  });

  it("suppresses later swaps while a deployment reload is already pending", () => {
    // Store the current page commit SHA before the first newer response.
    setLoadedCommitSha("abc123");
    let reloads = 0;
    setDeploymentReloadHandler(() => {
      reloads += 1;
    });
    handleCommitShaBeforeSwap({
      detail: {
        shouldSwap: true,
        xhr: {
          getResponseHeader: (name) => (name === COMMIT_SHA_HEADER ? "def456" : null),
        },
      },
    });
    const laterEvent = {
      detail: {
        shouldSwap: true,
        xhr: {
          getResponseHeader: () => null,
        },
      },
    };

    // Handle another swap after a deployment reload is already pending.
    handleCommitShaBeforeSwap(laterEvent);

    // Later swaps are suppressed without requesting another reload.
    expect(laterEvent.detail.shouldSwap).to.equal(false);
    expect(reloads).to.equal(1);
  });

  it("keeps marked not found responses suppressed while a deployment reload is already pending", () => {
    // Deployment reload state is set before processing a marked 404 response.
    setLoadedCommitSha("abc123");
    setDeploymentReloadHandler(() => {});
    handleCommitShaBeforeSwap({
      detail: {
        shouldSwap: true,
        xhr: {
          getResponseHeader: (name) => (name === COMMIT_SHA_HEADER ? "def456" : null),
        },
      },
    });
    const event = {
      detail: {
        isError: true,
        shouldSwap: false,
        xhr: {
          status: 404,
          getResponseHeader: (name) => (name === "X-OCG-Not-Found" ? "true" : null),
        },
      },
    };

    // Apply the not-found policy while deployment reload is pending.
    handleNotFoundBeforeSwap(event);

    // Pending deployment reload keeps marked not-found responses suppressed.
    expect(event.detail.shouldSwap).to.equal(false);
    expect(event.detail.isError).to.equal(true);
  });

  it("handles declarative HTMX response messages", () => {
    // Build a form with declarative response messages.
    const form = document.createElement("form");
    form.dataset.htmxResponse = "";
    form.dataset.successMessage = "Saved successfully.";
    form.dataset.errorMessage = "Save failed.";

    // Dispatch a successful HTMX response from the form.
    handleDeclarativeHtmxResponse({
      detail: {
        elt: form,
        xhr: {
          status: 204,
          responseText: "",
        },
      },
    });

    // The configured success message is shown.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Saved successfully.",
      icon: "success",
    });

    // Dispatch a failed HTMX response from the form.
    handleDeclarativeHtmxResponse({
      detail: {
        elt: form,
        xhr: {
          status: 500,
          responseText: "",
        },
      },
    });

    // The configured error message is shown.
    expect(swal.calls).to.have.length(2);
    expect(swal.calls[1]).to.include({
      text: "Save failed.",
      icon: "error",
    });
  });

  it("detects successful refresh-body responses", () => {
    // Build successful and unsuccessful response fixtures.
    const successfulRefresh = {
      status: 204,
      getResponseHeader: (name) => (name === "HX-Trigger" ? "refresh-body" : null),
    };
    const successfulOtherRefresh = {
      status: 204,
      getResponseHeader: (name) =>
        name === "HX-Trigger" ? "refresh-sidebar, refresh-body" : null,
    };
    const failedRefresh = {
      status: 500,
      getResponseHeader: (name) => (name === "HX-Trigger" ? "refresh-body" : null),
    };

    // Only successful responses that trigger a body refresh match.
    expect(isSuccessfulRefreshBodyResponse(successfulRefresh)).to.equal(true);
    expect(isSuccessfulRefreshBodyResponse(successfulOtherRefresh)).to.equal(true);
    expect(isSuccessfulRefreshBodyResponse(failedRefresh)).to.equal(false);
    expect(isSuccessfulRefreshBodyResponse({ status: 204 })).to.equal(false);
  });

  it("delays refresh-body success messages until the body refresh settles", async () => {
    // Build a form with declarative response messages.
    const form = document.createElement("form");
    form.dataset.htmxResponse = "";
    form.dataset.successMessage = "Saved after refresh.";

    // Dispatch a successful response that will trigger a body refresh.
    handleDeclarativeHtmxResponse({
      detail: {
        elt: form,
        xhr: {
          status: 204,
          responseText: "",
          getResponseHeader: (name) => (name === "HX-Trigger" ? "refresh-body" : null),
        },
      },
    });

    // The success message waits for the triggered body refresh.
    expect(swal.calls).to.have.length(0);
    await waitForDelay();
    document.dispatchEvent(new CustomEvent("htmx:afterSettle", { bubbles: true }));

    // The delayed message is shown after the refresh settles.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Saved after refresh.",
      icon: "success",
    });
  });

  it("registers the shared htmx response handlers", () => {
    // Capture listeners added to the event root.
    const listeners = [];
    const root = {
      body: {},
      addEventListener: (name, handler) => listeners.push([name, handler]),
    };

    // Register the shared HTMX response handlers.
    registerHtmxResponseHandlers(root);

    // All shared response handlers are registered on the event root.
    expect(listeners).to.deep.equal([
      ["htmx:configRequest", handleCommitShaConfigRequest],
      ["htmx:beforeOnLoad", handleCommitShaBeforeOnLoad],
      ["htmx:beforeSwap", handleCommitShaBeforeSwap],
      ["htmx:beforeSwap", handleNotFoundBeforeSwap],
      ["htmx:afterRequest", handleDeclarativeHtmxResponse],
    ]);
  });

  it("registers shared htmx response handlers once per event root", () => {
    // Capture listeners added during repeated registration.
    const listeners = [];
    const root = {
      addEventListener: (name, handler) => listeners.push([name, handler]),
    };

    // Register the shared handlers twice on the same root.
    registerHtmxResponseHandlers(root);
    registerHtmxResponseHandlers(root);

    // The root receives one copy of each shared response handler.
    expect(listeners).to.deep.equal([
      ["htmx:configRequest", handleCommitShaConfigRequest],
      ["htmx:beforeOnLoad", handleCommitShaBeforeOnLoad],
      ["htmx:beforeSwap", handleCommitShaBeforeSwap],
      ["htmx:beforeSwap", handleNotFoundBeforeSwap],
      ["htmx:afterRequest", handleDeclarativeHtmxResponse],
    ]);
  });

  it("keeps shared htmx response handlers active after body replacement", () => {
    // Build a form with declarative response messages in the current body.
    document.body.innerHTML = `
      <form data-htmx-response data-success-message="Saved successfully.">
        <button type="submit">Save</button>
      </form>
    `;
    registerHtmxResponseHandlers(document);

    // Replace the body and dispatch a response from a new swapped form.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <form data-htmx-response data-success-message="Saved after swap.">
        <button type="submit">Save</button>
      </form>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);
    const form = document.querySelector("[data-htmx-response]");
    form.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          elt: form,
          xhr: {
            status: 204,
            responseText: "",
          },
        },
      }),
    );

    // The document-level listener still handles the swapped form response.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Saved after swap.",
      icon: "success",
    });
  });
});
