const DEFAULT_SEASON = getDefaultSeason();

const seasonInput = document.querySelector("#seasonInput");
const loadButton = document.querySelector("#loadButton");
const statusText = document.querySelector("#statusText");
const metaText = document.querySelector("#metaText");
const tableBody = document.querySelector("#tableBody");
const transferQueryInput = document.querySelector("#transferQueryInput");
const transferSeasonInput = document.querySelector("#transferSeasonInput");
const transferSearchButton = document.querySelector("#transferSearchButton");
const transferStatusText = document.querySelector("#transferStatusText");
const transferTableBody = document.querySelector("#transferTableBody");

seasonInput.value = String(DEFAULT_SEASON);

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

    setStatus(
      `Tabellen er hentet fra offisielt standings-endepunkt.`,
      formatMeta(updatedText, payload.throttle)
    );
  } catch (error) {
    renderEmpty("Kunne ikke laste tabellen.");
    setStatus(error.message || "Noe gikk galt ved henting av data.");
  } finally {
    loadButton.disabled = false;
  }
}

async function fetchStandings(season) {
  const url = new URL("/api/standings", window.location.origin);
  url.searchParams.set("season", String(season));

  const response = await fetch(url);
  const payload = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
  }

  return payload;
}

async function loadTransfers() {
  const query = transferQueryInput.value.trim();
  const season = transferSeasonInput.value.trim();

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
    transferStatusText.textContent = `${payload.count} overganger vist fra datasettet i ewenme/transfers.`;
  } catch (error) {
    renderTransferEmpty("Kunne ikke laste overgangene.");
    transferStatusText.textContent = error.message || "Noe gikk galt ved henting av overgangsdata.";
  } finally {
    transferSearchButton.disabled = false;
  }
}

async function fetchTransfers(query, season) {
  const url = new URL("/api/transfers", window.location.origin);

  if (query) {
    url.searchParams.set("q", query);
  }

  if (season) {
    url.searchParams.set("season", season);
  }

  const response = await fetch(url);
  const payload = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
  }

  return payload;
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

function getDefaultSeason() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();

  return month >= 6 ? year : year - 1;
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
