import { expect } from "@open-wc/testing";

import "/static/js/common/breadcrumb-nav.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("breadcrumb-nav", () => {
  useMountedElementsCleanup("breadcrumb-nav");

  const breadcrumbItems = [
    { label: "Home", href: "/", icon: "home" },
    { label: "Groups", href: "/groups", icon: "groups" },
    { label: "CNCF Madrid", icon: "groups", current: true },
  ];

  it("renders nothing when no items are provided", async () => {
    const element = await mountLitComponent("breadcrumb-nav");

    expect(element.children.length).to.equal(0);
  });

  it("parses json items and renders the current breadcrumb label", async () => {
    const element = await mountLitComponent("breadcrumb-nav", {
      items: JSON.stringify(breadcrumbItems),
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    expect(element.textContent).to.include("CNCF Madrid");
    expect(element.querySelector('img[src="/img/banner-desktop.png"]')).to.not.equal(null);
    expect(element.querySelector('img[src="/img/banner-mobile.png"]')).to.not.equal(null);
  });

  it("falls back to the last breadcrumb item when none is marked current", async () => {
    const element = await mountLitComponent("breadcrumb-nav", {
      items: [
        { label: "Home", href: "/", icon: "home" },
        { label: "Events", href: "/events", icon: "date" },
        { label: "KubeCon", icon: "date" },
      ],
    });

    expect(element._getCurrentItem()).to.deep.equal({ label: "KubeCon", icon: "date" });
    expect(element.textContent).to.include("KubeCon");
  });

  it("closes the mobile dropdown on outside clicks and escape", async () => {
    const element = await mountLitComponent("breadcrumb-nav", { items: breadcrumbItems });

    const trigger = element.querySelector("[data-breadcrumb-trigger]");
    let focused = false;
    trigger.focus = () => {
      focused = true;
    };

    element._isOpen = true;
    element._handleDocumentClick({ target: document.body });
    expect(element._isOpen).to.equal(false);

    element._isOpen = true;
    element._handleKeydown({ key: "Escape" });

    expect(element._isOpen).to.equal(false);
    expect(focused).to.equal(true);
  });

  it("keeps the dropdown open when clicking the trigger or the dropdown itself", async () => {
    const element = await mountLitComponent("breadcrumb-nav", { items: breadcrumbItems });

    const trigger = element.querySelector("[data-breadcrumb-trigger]");
    const dropdown = element.querySelector("[data-breadcrumb-dropdown]");

    element._isOpen = true;
    element._handleDocumentClick({ target: trigger });
    expect(element._isOpen).to.equal(true);

    element._handleDocumentClick({ target: dropdown });
    expect(element._isOpen).to.equal(true);
  });
});
