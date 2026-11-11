(() => {
  const params = location.search.slice(1).split("&").filter(Boolean);
  const keptParams = params.filter((param) => param.split("=")[0] !== "ocg_refresh");
  if (keptParams.length === params.length) {
    return;
  }

  const search = keptParams.length ? `?${keptParams.join("&")}` : "";
  history.replaceState(history.state, "", `${location.pathname}${search}${location.hash}`);
})();
