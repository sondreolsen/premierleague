const DEFAULT_SEASON = getDefaultSeason();

const seasonInput = document.querySelector("#seasonInput");
const loadButton = document.querySelector("#loadButton");
const statusText = document.querySelector("#statusText");
const metaText = document.querySelector("#metaText");
const tableBody = document.querySelector("#tableBody");
const transferQueryInput = document.querySelector("#transferQueryInput");
const transferSeasonInput = document.querySelector("#transferSeasonInput");
const transferSeasonOptions = document.querySelector("#transferSeasonOptions");
const transferSearchButton = document.querySelector("#transferSearchButton");
const transferStatusText = document.querySelector("#transferStatusText");
const transferTableBody = document.querySelector("#transferTableBody");

populateSeasonOptions();
transferSeasonInput.value = "";

loadButton.addEventListener("click", () => {
  loadTable();
});

transferSearchButton.addEventListener("click", () => {
  loadTransfers();
});

transferQueryInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    loadTransfers();
  }
});

loadTable();

async function loadTable() {
  const season = Number.parseInt(seasonInput.value, 10);

  if (!Number.isInteger(season) || season < 2020) {
    setStatus("Velg en gyldig sesong.");
    return;
  }

  setStatus("Henter offisiell Premier League-tabell ...", "");
  renderEmpty("Laster tabell ...");
  loadButton.disabled = true;

  try {
    const payload = await fetchStandings(season);
    const table = payload.table;

    if (!table.length) {
      renderEmpty("Fant ingen tabell for valgt sesong.");
      setStatus("Ingen tabell tilgjengelig ennå.", formatMeta("", payload.throttle));
      return;
    }

    renderTable(table);

    const updatedText = payload.lastUpdated
      ? `Sist oppdatert: ${formatDate(payload.lastUpdated)}`
      : "";
    const sourceText = payload.mode === "live" ? "Kilde: lokal live-proxy." : "Kilde: publisert GitHub Pages-snapshot.";

    setStatus(
      `Tabellen er hentet fra offisielt standings-endepunkt.`,
      formatMeta([updatedText, sourceText].filter(Boolean).join(" "), payload.throttle)
    );
  } catch (error) {
    renderEmpty("Kunne ikke laste tabellen.");
    setStatus(error.message || "Noe gikk galt ved henting av data.");
  } finally {
    loadButton.disabled = false;
  }
}

async function fetchStandings(season) {
  const liveUrl = new URL("./api/standings", window.location.href);
  liveUrl.searchParams.set("season", String(season));

  try {
    const response = await fetch(liveUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
    }

    payload.mode = "live";
    return payload;
  } catch {
    const snapshotUrl = new URL("./data/standings.json", window.location.href);
    const response = await fetch(snapshotUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error("Fant verken lokal server eller publisert standings-fil.");
    }

    const seasonEntry = payload.seasons?.[String(season)];
    if (!seasonEntry) {
      throw new Error(`Fant ingen publisert tabell for sesongen ${season}.`);
    }

    return {
      ...seasonEntry,
      mode: "snapshot",
      generatedAt: payload.generatedAt
    };
  }
}

async function loadTransfers() {
  const query = transferQueryInput.value.trim();
  const season = normalizeTransferSeason(transferSeasonInput.value.trim());

  transferStatusText.textContent = "Henter overgangsdata ...";
  renderTransferEmpty("Laster overganger ...");
  transferSearchButton.disabled = true;

  try {
    const payload = await fetchTransfers(query, season);

    if (!payload.results.length) {
      renderTransferEmpty("Fant ingen overganger som matcher soket.");
      transferStatusText.textContent = "Ingen treff i overgangsdataene.";
      return;
    }

    renderTransfers(payload.results);
    const sourceText = payload.mode === "live" ? "live backend" : "publisert GitHub Pages-data";
    transferStatusText.textContent = `${payload.count} overganger vist fra ${sourceText}.`;
  } catch (error) {
    renderTransferEmpty("Kunne ikke laste overgangene.");
    transferStatusText.textContent = error.message || "Noe gikk galt ved henting av overgangsdata.";
  } finally {
    transferSearchButton.disabled = false;
  }
}

async function fetchTransfers(query, season) {
  const liveUrl = new URL("./api/transfers", window.location.href);

  if (query) {
    liveUrl.searchParams.set("q", query);
  }

  if (season) {
    liveUrl.searchParams.set("season", season);
  }

  try {
    const response = await fetch(liveUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
    }

    payload.mode = "live";
    return payload;
  } catch {
    const snapshotUrl = new URL("./data/transfers.json", window.location.href);
    const response = await fetch(snapshotUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error("Fant verken lokal server eller publisert transfer-fil.");
    }

    const results = filterTransfers(payload.results || [], query, season);
    return {
      mode: "snapshot",
      count: results.length,
      results
    };
  }
}

function renderTable(table) {
  tableBody.innerHTML = table
    .map(
      (team) => `
        <tr>
          <td>${team.position}</td>
          <td>${team.name}</td>
          <td>${team.playedGames}</td>
          <td>${team.won}</td>
          <td>${team.draw}</td>
          <td>${team.lost}</td>
          <td>${team.goalsFor}</td>
          <td>${team.goalsAgainst}</td>
          <td>${formatGoalDifference(team.goalDifference)}</td>
          <td>${team.points}</td>
        </tr>
      `
    )
    .join("");
}

function renderEmpty(message) {
  tableBody.innerHTML = `<tr><td colspan="10" class="empty-state">${message}</td></tr>`;
}

function renderTransfers(results) {
  transferTableBody.innerHTML = results
    .map(
      (item) => `
        <tr>
          <td>${item.playerName}</td>
          <td>${item.fromClub || "-"}</td>
          <td>${item.toClub || "-"}</td>
          <td>${formatFee(item.fee)}</td>
          <td>${item.period || "-"}</td>
          <td>${item.season || item.year || "-"}</td>
        </tr>
      `
    )
    .join("");
}

function renderTransferEmpty(message) {
  transferTableBody.innerHTML = `<tr><td colspan="6" class="empty-state">${message}</td></tr>`;
}

function setStatus(primary, secondary = "") {
  statusText.textContent = primary;
  metaText.textContent = secondary;
}

function formatGoalDifference(value) {
  return value > 0 ? `+${value}` : String(value);
}

function formatFee(value) {
  if (!value || value === "?" || value === "-") {
    return "Ikke oppgitt";
  }

  return value;
}

function filterTransfers(results, query, season) {
  const normalizedQuery = (query || "").trim().toLowerCase();
  const normalizedSeason = normalizeTransferSeason((season || "").trim());
  let direction = "any";
  let searchText = normalizedQuery;

  if (normalizedQuery.startsWith("til ")) {
    direction = "to";
    searchText = normalizedQuery.slice(4).trim();
  } else if (normalizedQuery.startsWith("fra ")) {
    direction = "from";
    searchText = normalizedQuery.slice(4).trim();
  }

  return results
    .filter((item) => {
      if (normalizedSeason && item.season !== normalizedSeason) {
        return false;
      }

      if (!searchText) {
        return true;
      }

      const player = (item.playerName || "").toLowerCase();
      const fromClub = (item.fromClub || "").toLowerCase();
      const toClub = (item.toClub || "").toLowerCase();

      if (direction === "to") {
        return toClub.includes(searchText);
      }

      if (direction === "from") {
        return fromClub.includes(searchText);
      }

      return player.includes(searchText) || fromClub.includes(searchText) || toClub.includes(searchText);
    })
    .slice(0, 100);
}

function getDefaultSeason() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();

  return month >= 6 ? year : year - 1;
}

function populateSeasonOptions() {
  const seasonYears = [];

  for (let year = DEFAULT_SEASON; year >= 2020; year -= 1) {
    seasonYears.push(year);
  }

  seasonInput.innerHTML = seasonYears
    .map((year) => `<option value="${year}">${formatSeasonLabel(year)}</option>`)
    .join("");

  seasonInput.value = String(DEFAULT_SEASON);

  transferSeasonOptions.innerHTML = seasonYears
    .map((year) => {
      const label = formatSeasonLabel(year);
      const full = `${year}/${year + 1}`;
      return `<option value="${label}"></option><option value="${full}"></option>`;
    })
    .join("");
}

function formatSeasonLabel(startYear) {
  const start = String(startYear).slice(-2);
  const end = String(startYear + 1).slice(-2);
  return `${start}/${end}`;
}

function normalizeTransferSeason(value) {
  if (!value) {
    return "";
  }

  const trimmed = value.trim();
  const shortMatch = trimmed.match(/^(\d{2})\s*\/\s*(\d{2})$/);
  if (shortMatch) {
    const startYear = Number.parseInt(shortMatch[1], 10);
    const fullStartYear = startYear >= 90 ? 1900 + startYear : 2000 + startYear;
    return `${fullStartYear}/${fullStartYear + 1}`;
  }

  const fullMatch = trimmed.match(/^(\d{4})\s*\/\s*(\d{4})$/);
  if (fullMatch) {
    return `${fullMatch[1]}/${fullMatch[2]}`;
  }

  return trimmed;
}

function formatDate(value) {
  return new Intl.DateTimeFormat("nb-NO", {
    dateStyle: "long",
    timeStyle: "short"
  }).format(new Date(value));
}

function formatMeta(baseText, throttle) {
  const parts = [];

  if (baseText) {
    parts.push(baseText);
  }

  if (throttle?.requestsAvailable) {
    parts.push(`Gjenværende kall: ${throttle.requestsAvailable}`);
  }

  if (throttle?.requestCounterReset) {
    parts.push(`Reset om: ${throttle.requestCounterReset} s`);
  }

  return parts.join(" | ");
}
