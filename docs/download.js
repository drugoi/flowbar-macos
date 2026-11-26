const downloadLink = document.querySelector(".download-link");
const releasesURL = new URL("./", downloadLink.href).href;
const latestReleaseAPI = "https://api.github.com/repos/drugoi/flowbar-macos/releases/latest";

async function fetchResponse(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(url, { cache: "no-cache", signal: controller.signal });
    if (!response.ok) throw new Error("Download information unavailable");
    return await response.text();
  } finally {
    clearTimeout(timeout);
  }
}

function releaseZIP(url) {
  return typeof url === "string" && url.startsWith(`${releasesURL}download/`) && url.endsWith(".zip")
    ? url : null;
}

async function latestZIP() {
  const release = await fetchResponse(latestReleaseAPI).then(JSON.parse).catch(() => null);
  if (typeof release?.tag_name === "string" && Array.isArray(release.assets)) {
    const expectedName = `FlowBar-${release.tag_name.replace(/^v/, "")}.zip`;
    const asset = release.assets.find(({ name, state }) => name === expectedName && state === "uploaded");
    const zip = releaseZIP(asset?.browser_download_url);
    if (zip) return zip;
  }

  const xml = await fetchResponse("./appcast.xml");
  const feed = new DOMParser().parseFromString(xml, "application/xml");
  return releaseZIP(feed.querySelector("channel > item > enclosure")?.getAttribute("url"));
}

downloadLink.addEventListener("click", async (event) => {
  event.preventDefault();
  if (downloadLink.getAttribute("aria-busy") === "true") return;

  downloadLink.setAttribute("aria-busy", "true");
  try {
    const zip = await latestZIP().catch(() => null);
    window.location.assign(zip ?? downloadLink.href);
  } finally {
    downloadLink.removeAttribute("aria-busy");
  }
});
