(() => {
  const theme = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
  const logos = document.currentScript.parentElement;
  logos.querySelector(`[data-theme-image="${theme}"] img`).loading = "eager";
})();
