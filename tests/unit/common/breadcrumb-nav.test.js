import { expect } from "@open-wc/testing";

import "/static/js/common/breadcrumb-nav.js";
import { PHONE_MEDIA_QUERY } from "/static/js/common/phone-viewport.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

describe("breadcrumb-nav", () => {
  useMountedElementsCleanup("breadcrumb-nav");

  const breadcrumbItems = [
    { label: "Home", href: "/", icon: "home" },
    { label: "Groups", href: "/groups", icon: "groups" },
    { label: "CNCF Madrid", icon: "groups", current: true },
  ];

  let media;

  afterEach(() => {
    media?.restore();
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
    media = stubMatchMedia({ [PHONE_MEDIA_QUERY]: true });

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
    media = stubMatchMedia();

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

  it("spans the phone viewport edge to edge only when full-bleed", async () => {
    // Render one breadcrumb boxed and one full-bleed.
    const boxed = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerMobileUrl: "/img/banner-mobile.png",
    });
    const fullBleed = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerMobileUrl: "/img/banner-mobile.png",
      fullBleed: true,
    });

    // Verify the full-bleed box drops the gutter, corners and side borders on phones.
    const tokensOf = (element) => {
      const container = element.querySelector(".container");
      return [container, container.firstElementChild, element.querySelector("img").parentElement].map(
        (node) => node.classList,
      );
    };
    const [boxedContainer, boxedCard, boxedBanner] = tokensOf(boxed);
    const [bleedContainer, bleedCard, bleedBanner] = tokensOf(fullBleed);
    expect(boxedContainer.contains("phone:px-3")).to.equal(true);
    expect(bleedContainer.contains("phone:px-0")).to.equal(true);
    expect(boxedCard.contains("phone:rounded-none")).to.equal(false);
    expect(bleedCard.contains("phone:rounded-none")).to.equal(true);
    expect(bleedCard.contains("phone:border-x-0")).to.equal(true);
    expect(boxedBanner.contains("phone:rounded-none")).to.equal(false);
    expect(bleedBanner.contains("phone:rounded-none")).to.equal(true);
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

  it("frames the trigger caret as a decorative mini button on phones only", async () => {
    // Render the breadcrumb navigation with a mobile dropdown trigger.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
    });

    // Collect the caret and the tap cue around it.
    const caret = element.querySelector("[data-breadcrumb-trigger] .icon-caret-down");
    const tapCue = caret.parentElement;

    // Verify the cue is a mini button on phones and leaves no box elsewhere.
    expect(tapCue.classList.contains("btn-mini")).to.equal(true);
    expect(tapCue.classList.contains("not-phone:contents")).to.equal(true);
    expect(caret.classList.contains("phone:bg-current")).to.equal(true);

    // Verify the cue stays decorative, so the trigger remains the only control.
    expect(tapCue.tagName).to.equal("SPAN");
    expect(tapCue.getAttribute("aria-hidden")).to.equal("true");
  });

  it("holds each banner's place with its natural size before the image loads", async () => {
    // Render both banners with their dark mode variants.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerDarkUrl: "/img/banner-desktop-dark.png",
      bannerMobileUrl: "/img/banner-mobile.png",
      bannerMobileDarkUrl: "/img/banner-mobile-dark.png",
    });

    // Verify every image carries the natural banner size, which the browser turns into the
    // ratio that reserves its height while nothing has loaded.
    for (const [src, width] of [
      ["/img/banner-desktop.png", "2428"],
      ["/img/banner-desktop-dark.png", "2428"],
      ["/img/banner-mobile.png", "1220"],
      ["/img/banner-mobile-dark.png", "1220"],
    ]) {
      const img = element.querySelector(`img[src="${src}"]`);
      expect(img.getAttribute("width"), src).to.equal(width);
      expect(img.getAttribute("height"), src).to.equal("192");
      expect(getComputedStyle(img).aspectRatio, src).to.equal(`auto ${width} / 192`);
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

  it("renders a dark mode banner only together with its light banner", async () => {
    // Render one breadcrumb with both dark banners and one with dark banners alone.
    const paired = await mountLitComponentWithAttributes("breadcrumb-nav", {
      attributes: {
        "banner-dark-url": "/img/banner-desktop-dark.png",
        "banner-mobile-dark-url": "/img/banner-mobile-dark.png",
        "banner-mobile-url": "/img/banner-mobile.png",
        "banner-url": "/img/banner-desktop.png",
        items: JSON.stringify(breadcrumbItems),
      },
    });
    const orphan = await mountLitComponentWithAttributes("breadcrumb-nav", {
      attributes: {
        "banner-dark-url": "/img/banner-desktop-dark.png",
        "banner-mobile-dark-url": "/img/banner-mobile-dark.png",
        items: JSON.stringify(breadcrumbItems),
      },
    });

    // Verify each breakpoint pairs an eager light image with a lazy dark one.
    for (const [lightUrl, darkUrl, aspect] of [
      ["/img/banner-mobile.png", "/img/banner-mobile-dark.png", "1220 / 192"],
      ["/img/banner-desktop.png", "/img/banner-desktop-dark.png", "2428 / 192"],
    ]) {
      const lightImg = paired.querySelector(`img[src="${lightUrl}"]`);
      const darkImg = paired.querySelector(`img[src="${darkUrl}"]`);
      const lightWrapper = lightImg.parentElement;
      const darkWrapper = darkImg.parentElement;

      expect(lightWrapper.dataset.themeImage).to.equal("light");
      expect(darkWrapper.dataset.themeImage).to.equal("dark");
      expect(lightWrapper.dataset.bannerAspect).to.equal(aspect);
      expect(darkWrapper.dataset.bannerAspect).to.equal(aspect);
      expect(lightWrapper.parentElement).to.equal(darkWrapper.parentElement);
      expect(lightWrapper.parentElement.dataset.bannerAspect).to.equal(aspect);
      expect(lightImg.hasAttribute("loading")).to.equal(false);
      expect(darkImg.getAttribute("loading")).to.equal("lazy");
      for (const img of [lightImg, darkImg]) {
        expect(img.getAttribute("alt")).to.equal("Banner");
        expect(img.classList.contains("w-full")).to.equal(true);
        expect(img.classList.contains("h-auto")).to.equal(true);
      }
    }

    // Verify dark banners without their light banners render nothing.
    expect(orphan.querySelector("img")).to.equal(null);
    expect(orphan.querySelector("[data-banner-aspect]")).to.equal(null);
  });

  it("resolves the desktop and mobile dark banners independently", async () => {
    // Render a breadcrumb whose only dark banner is the desktop one.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerDarkUrl: "/img/banner-desktop-dark.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    // Verify the desktop banner is paired and the mobile banner keeps its single image.
    const mobileImg = element.querySelector('img[src="/img/banner-mobile.png"]');
    expect(element.querySelector('img[src="/img/banner-desktop-dark.png"]')).to.not.equal(null);
    expect(element.querySelectorAll('[data-theme-image="dark"]')).to.have.length(1);
    expect(mobileImg.parentElement.hasAttribute("data-theme-image")).to.equal(false);
    expect(mobileImg.parentElement.classList.contains("sm:hidden")).to.equal(true);
  });

  it("keeps the single banner image markup without dark banners", async () => {
    // Render the breadcrumb navigation with light banners only.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });

    // Verify each banner image sits directly in its breakpoint wrapper.
    expect(element.querySelector("[data-theme-image]")).to.equal(null);
    expect(element.querySelectorAll("img")).to.have.length(2);
    for (const img of element.querySelectorAll("img")) {
      expect(img.parentElement.classList.contains("border-b")).to.equal(true);
      expect(img.hasAttribute("loading")).to.equal(false);
    }
  });

  it("styles only the failed dark banner's wrapper as a placeholder", async () => {
    // Render the breadcrumb navigation with a paired desktop banner.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerDarkUrl: "/img/banner-desktop-dark.png",
    });
    const lightImg = element.querySelector('img[src="/img/banner-desktop.png"]');
    const darkImg = element.querySelector('img[src="/img/banner-desktop-dark.png"]');
    const breakpointWrapper = darkImg.parentElement.parentElement;

    // Fail the dark banner.
    darkImg.dispatchEvent(new Event("error"));

    // Verify the dark wrapper becomes the placeholder and the light banner is untouched.
    expect(darkImg.style.display).to.equal("none");
    expect(darkImg.parentElement.style.aspectRatio.replace(/\s/g, "")).to.equal("2428/192");
    expect(darkImg.parentElement.style.background).to.contain("linear-gradient");
    expect(lightImg.style.display).to.equal("");
    expect(lightImg.parentElement.style.background).to.equal("");
    expect(breakpointWrapper.style.background).to.equal("");
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

  it("toggles the dropdown from the mobile banner and its placeholder only", async () => {
    // Render the breadcrumb navigation with both responsive banners.
    const element = await mountLitComponent("breadcrumb-nav", {
      items: breadcrumbItems,
      bannerUrl: "/img/banner-desktop.png",
      bannerMobileUrl: "/img/banner-mobile.png",
    });
    const trigger = element.querySelector("[data-breadcrumb-trigger]");
    const mobileImage = element.querySelector('img[src="/img/banner-mobile.png"]');
    const desktopImage = element.querySelector('img[src="/img/banner-desktop.png"]');

    // Click the mobile banner image and verify the dropdown opens and stays open.
    mobileImage.click();
    await element.updateComplete;
    expect(trigger.getAttribute("aria-expanded")).to.equal("true");

    // Fail the image and click its placeholder to close the dropdown.
    mobileImage.dispatchEvent(new Event("error"));
    mobileImage.parentElement.click();
    await element.updateComplete;
    expect(trigger.getAttribute("aria-expanded")).to.equal("false");

    // Verify the desktop banner leaves the dropdown alone.
    desktopImage.click();
    await element.updateComplete;
    expect(trigger.getAttribute("aria-expanded")).to.equal("false");
  });
});
