import { expect } from "@open-wc/testing";

import {
  createNoEmptyValuesExtension,
  handleCommitShaBeforeOnLoad,
  handleCommitShaBeforeSwap,
  handleCommitShaConfigRequest,
  handleNotFoundBeforeSwap,
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";
import {
  COMMIT_SHA_HEADER,
  consumePendingDeploymentRefreshAlert,
  REFRESH_HEADER,
  resetDeploymentReloadState,
  setDeploymentReloadHandler,
} from "/static/js/common/deployment-version.js";

const formDataToEntries = (formData) => Array.from(formData.entries());
const setLoadedCommitSha = (commitSha) => {
  document.head.innerHTML = `<meta name="ocg-commit-sha" content="${commitSha}">`;
};

describe("htmx extensions", () => {
  afterEach(() => {
    document.head.innerHTML = "";
    resetDeploymentReloadState();
  });

  it('registers both "no-empty-vals" variants', () => {
    const extensions = new Map();
    const htmxMock = {
      defineExtension: (name, extension) => extensions.set(name, extension),
    };

    registerHtmxNoEmptyValuesExtensions(htmxMock);

    expect(Array.from(extensions.keys())).to.deep.equal(["no-empty-vals", "no-empty-vals-keep-zero"]);
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

  it("allows marked not found pages to swap on htmx 404 responses", () => {
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

    handleNotFoundBeforeSwap(event);

    expect(event.detail.shouldSwap).to.equal(true);
    expect(event.detail.isError).to.equal(false);
  });

  it("keeps unmarked 404 responses on the default htmx error path", () => {
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

    handleNotFoundBeforeSwap(event);

    expect(event.detail.shouldSwap).to.equal(false);
    expect(event.detail.isError).to.equal(true);
  });

  it("adds the loaded commit SHA to htmx request headers", () => {
    setLoadedCommitSha("abc123");
    const event = {
      detail: {
        headers: {
          Existing: "value",
        },
      },
    };

    handleCommitShaConfigRequest(event);

    expect(event.detail.headers).to.deep.equal({
      Existing: "value",
      [COMMIT_SHA_HEADER]: "abc123",
    });
  });

  it("records and owns htmx refresh headers before htmx handles them", () => {
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

    handleCommitShaBeforeOnLoad(event);

    expect(event.defaultPrevented).to.equal(true);
    expect(reloads).to.equal(1);
    expect(consumePendingDeploymentRefreshAlert()).to.equal(true);
  });

  it("cancels the swap and reloads when an htmx response comes from a newer commit", () => {
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

    handleCommitShaBeforeSwap(event);

    expect(event.detail.shouldSwap).to.equal(false);
    expect(reloads).to.equal(1);
  });

  it("suppresses later swaps while a deployment reload is already pending", () => {
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

    handleCommitShaBeforeSwap(laterEvent);

    expect(laterEvent.detail.shouldSwap).to.equal(false);
    expect(reloads).to.equal(1);
  });

  it("keeps marked not found responses suppressed while a deployment reload is already pending", () => {
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

    handleNotFoundBeforeSwap(event);

    expect(event.detail.shouldSwap).to.equal(false);
    expect(event.detail.isError).to.equal(true);
  });

  it("registers the shared htmx response handlers", () => {
    const listeners = [];
    const root = {
      body: {
        addEventListener: (name, handler) => listeners.push([name, handler]),
      },
    };

    registerHtmxResponseHandlers(root);

    expect(listeners).to.deep.equal([
      ["htmx:configRequest", handleCommitShaConfigRequest],
      ["htmx:beforeOnLoad", handleCommitShaBeforeOnLoad],
      ["htmx:beforeSwap", handleCommitShaBeforeSwap],
      ["htmx:beforeSwap", handleNotFoundBeforeSwap],
    ]);
  });

  it("registers shared htmx response handlers once per event root", () => {
    const listeners = [];
    const root = {
      body: {
        addEventListener: (name, handler) => listeners.push([name, handler]),
      },
    };

    registerHtmxResponseHandlers(root);
    registerHtmxResponseHandlers(root);

    expect(listeners).to.deep.equal([
      ["htmx:configRequest", handleCommitShaConfigRequest],
      ["htmx:beforeOnLoad", handleCommitShaBeforeOnLoad],
      ["htmx:beforeSwap", handleCommitShaBeforeSwap],
      ["htmx:beforeSwap", handleNotFoundBeforeSwap],
    ]);
  });
});
