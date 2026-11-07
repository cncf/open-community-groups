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

  const originalMatchMedia = window.matchMedia;

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
  });

  it("renders nothing when no items are provided", async () => {
    // Render the empty breadcrumb navigation fixture.
    const element = await mountLitComponent("breadcrumb-nav");

    // Assert the component leaves the light DOM empty without items.
    expect(element.children.length).to.equal(0);
  });

  it("parses json items and renders the current breadcrumb label", async () => {
    // Render breadcrumb items from JSON attributes with banner images.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: JSON.stringify(breadcrumbItems),
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    // Assert the current label and responsive banners are rendered.
    expect(element.textContent).to.include("CNCF Madrid");
    expect(element.querySelector('img[src="/img/banner-desktop.png"]')).to.not.equal(null);
    expect(element.querySelector('img[src="/img/banner-mobile.png"]')).to.not.equal(null);
  });

  it("falls back to the last breadcrumb item when none is marked current", async () => {
    // Render breadcrumb items without an explicit current item.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: [
        { label: "Home", href: "/", icon: "home" },
        { label: "Events", href: "/events", icon: "date" },
        { label: "KubeCon", icon: "date" },
      ],
    });

    // Assert the last item becomes the current breadcrumb.
    expect(element._getCurrentItem()).to.deep.equal({
      label: "KubeCon",
      icon: "date",
    });
    expect(element.textContent).to.include("KubeCon");
  });

  it("renders breadcrumb items without hrefs as plain text", async () => {
    // Render breadcrumb items that do not include hrefs.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: [
        { label: "Home", icon: "home" },
        { label: "Groups", icon: "groups" },
        { label: "KubeCon", icon: "date", current: true },
      ],
    });

    // Non-link breadcrumbs render as plain text with the current marker.
    expect(element.querySelector("ol a")).to.equal(null);
    expect(element.querySelector('li[aria-current="page"]').textContent).to.include("KubeCon");
  });

  it("names the dropdown listbox on phones", async () => {
    // Stub a matching phone query.
    window.matchMedia = () => ({ matches: true });

    // Render the breadcrumb navigation with a mobile dropdown.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });

    // Verify the listbox has an accessible name.
    expect(element.querySelector("[data-breadcrumb-dropdown]").getAttribute("aria-label")).to.equal(
      "Breadcrumb links",
    );
  });

  it("leaves the dropdown listbox unnamed off phones", async () => {
    // Stub a query that does not match.
    window.matchMedia = () => ({ matches: false });

    // Render the breadcrumb navigation with a mobile dropdown.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });

    // Verify no attribute reaches narrow fine-pointer windows.
    expect(element.querySelector("[data-breadcrumb-dropdown]").hasAttribute("aria-label")).to.equal(false);
  });

  it("hides the closed dropdown from phone focus and screen readers", async () => {
    // Render the breadcrumb navigation with a closed dropdown.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });
    const dropdown = element.querySelector("[data-breadcrumb-dropdown]");

    // Verify the closed state carries the phone token.
    expect(dropdown.classList.contains("phone:invisible")).to.equal(true);

    // Open the dropdown.
    element._isOpen = true;
    await element.updateComplete;

    // Verify the open state drops it.
    expect(dropdown.classList.contains("phone:invisible")).to.equal(false);
  });

  it("uses the mobile layout tokens on phones only", async () => {
    // Render the breadcrumb navigation with both banners.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    // Collect the elements that swap at the phone breakpoint.
    const mobileBanner = element.querySelector('img[src="/img/banner-mobile.png"]').parentElement;
    const desktopBanner = element.querySelector('img[src="/img/banner-desktop.png"]').parentElement;
    const dropdownBlock = element.querySelector("[data-breadcrumb-trigger]").parentElement;
    const desktopList = element.querySelector("nav ol");

    // Verify phones get the uncropped mobile banner and the dropdown at every width.
    expect(mobileBanner.classList.contains("phone:block")).to.equal(true);
    expect(desktopBanner.classList.contains("phone:hidden")).to.equal(true);
    expect(dropdownBlock.classList.contains("phone:block")).to.equal(true);
    expect(desktopList.classList.contains("phone:hidden")).to.equal(true);

    // Verify the existing tokens stay for non-phone widths.
    expect(mobileBanner.classList.contains("sm:hidden")).to.equal(true);
    expect(desktopBanner.classList.contains("sm:block")).to.equal(true);

    // Verify banners keep their natural aspect ratio: full width, auto height,
    // and no forced aspect-ratio or object-cover cropping.
    const mobileImg = mobileBanner.querySelector("img");
    const desktopImg = desktopBanner.querySelector("img");
    for (const banner of [mobileBanner, desktopBanner]) {
      for (const token of banner.classList) {
        expect(token.startsWith("aspect-[")).to.equal(false);
      }
    }
    for (const img of [mobileImg, desktopImg]) {
      expect(img.classList.contains("w-full")).to.equal(true);
      expect(img.classList.contains("h-auto")).to.equal(true);
      expect(img.classList.contains("object-cover")).to.equal(false);
    }
  });

  it("shows a placeholder when a banner image fails to load", async () => {
    // Render the breadcrumb navigation with both responsive banners.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    const mobileImg = element.querySelector('img[src="/img/banner-mobile.png"]');
    const desktopImg = element.querySelector('img[src="/img/banner-desktop.png"]');

    // Each banner fails to load, so the broken image is replaced by a
    // placeholder that keeps the banner's aspect ratio and height.
    for (const [img, aspect] of [
      [mobileImg, "1220 / 192"],
      [desktopImg, "2428 / 192"],
    ]) {
      const banner = img.parentElement;

      // The banner is visible with no placeholder before the load failure.
      expect(banner.style.display).to.not.equal("none");
      expect(banner.style.aspectRatio).to.equal("");

      img.dispatchEvent(new Event("error"));

      // The broken image is hidden but the banner stays visible as a
      // neutral placeholder at the banner's aspect ratio.
      expect(img.style.display).to.equal("none");
      expect(banner.style.display).to.not.equal("none");
      expect(banner.style.aspectRatio.replace(/\s/g, "")).to.equal(aspect.replace(/\s/g, ""));
      expect(banner.style.background).to.contain("linear-gradient");
    }
  });

  it("closes the mobile dropdown on outside clicks and escape", async () => {
    // Render the breadcrumb navigation with a mobile dropdown trigger.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });

    // Track focus calls on the dropdown trigger.
    const trigger = element.querySelector("[data-breadcrumb-trigger]");
    let focused = false;
    trigger.focus = () => {
      focused = true;
    };

    // Close the dropdown from an outside document click.
    element._isOpen = true;
    element._handleDocumentClick({ target: document.body });
    expect(element._isOpen).to.equal(false);

    // Send the keyboard event.
    element._isOpen = true;
    element._handleKeydown({ key: "Escape" });

    // The dropdown closes and focus returns to the trigger.
    expect(element._isOpen).to.equal(false);
    expect(focused).to.equal(true);
  });

  it("keeps the dropdown open when clicking the trigger or the dropdown itself", async () => {
    // Render the breadcrumb navigation with trigger and dropdown content.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });

    // Collect the elements that should not count as outside clicks.
    const trigger = element.querySelector("[data-breadcrumb-trigger]");
    const dropdown = element.querySelector("[data-breadcrumb-dropdown]");

    // Keep the dropdown open when the document click starts from the trigger.
    element._isOpen = true;
    element._handleDocumentClick({ target: trigger });
    expect(element._isOpen).to.equal(true);

    // Keep the dropdown open when the document click starts inside the menu.
    element._handleDocumentClick({ target: dropdown });
    expect(element._isOpen).to.equal(true);
  });
});
