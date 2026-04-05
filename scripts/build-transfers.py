from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable

from premier_league import Transfers


START_SEASON = 1992


@dataclass
class TransferItem:
    playerName: str
    fromClub: str
    toClub: str
    fee: str
    movement: str
    period: str
    season: str
    year: str
    position: str
    date: str


def main() -> None:
    import sys

    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data/transfers.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    current_year = date.today().year
    current_month = date.today().month
    end_season = current_year if current_month >= 7 else current_year - 1

    results: list[dict[str, str]] = []

    season_counts: dict[str, int] = {}

    for start_year in range(START_SEASON, end_season + 1):
        season_id = f"{start_year}-{str(start_year + 1)[-2:]}"
        try:
            transfers = Transfers(target_season=season_id, league="Premier League")
            teams = transfers.get_all_current_teams()
        except Exception as exc:
            print(f"Skipping season {season_id}: {exc}")
            continue

        if not teams:
            print(f"Skipping season {season_id}: no teams returned")
            continue

        season_total = 0
        for team in teams:
            incoming = build_rows(transfers, team, start_year, movement="in")
            outgoing = build_rows(transfers, team, start_year, movement="out")
            results.extend(incoming)
            results.extend(outgoing)
            season_total += len(incoming) + len(outgoing)

        season_counts[f"{start_year}/{start_year + 1}"] = season_total
        print(f"Collected {season_total} rows for {season_id}")

    deduped_results = dedupe(results)

    if not deduped_results:
        raise RuntimeError("No transfer results were generated from premier_league.")

    non_empty_seasons = {season: count for season, count in season_counts.items() if count > 0}
    if not non_empty_seasons:
        raise RuntimeError("premier_league returned zero transfer rows for every season.")

    payload = {
        "generatedAt": datetime.now().astimezone().isoformat(),
        "source": "https://github.com/kayoMichael/premier_league",
        "count": len(deduped_results),
        "seasonCounts": non_empty_seasons,
        "results": deduped_results,
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def build_rows(transfers: Transfers, team: str, start_year: int, movement: str) -> list[dict[str, str]]:
    try:
        raw = transfers.transfer_in_table(team) if movement == "in" else transfers.transfer_out_table(team)
    except Exception:
        return []

    rows = normalize_rows(raw)
    items: list[dict[str, str]] = []

    for row in rows:
        if len(row) < 4:
            continue

        transfer_date, player_name, position, club = row[:4]
        year = infer_year(start_year, transfer_date)
        period = infer_period(transfer_date)
        fee = "-"

        if movement == "in":
            from_club = club
            to_club = team
        else:
            from_club = team
            to_club = club

        items.append(
            TransferItem(
                playerName=player_name,
                fromClub=from_club,
                toClub=to_club,
                fee=fee,
                movement=movement,
                period=period,
                season=f"{start_year}/{start_year + 1}",
                year=str(year),
                position=position,
                date=transfer_date,
            ).__dict__
        )

    return items


def normalize_rows(raw: Any) -> list[list[str]]:
    rows = [row for row in flatten_rows(raw) if len(row) >= 4]
    if rows and [cell.strip().lower() for cell in rows[0][:4]] == ["date", "name", "position", "club"]:
        rows = rows[1:]
    return rows


def flatten_rows(value: Any) -> Iterable[list[str]]:
    if isinstance(value, list):
        if value and all(isinstance(item, str) for item in value):
            yield [str(item).strip() for item in value]
            return

        for item in value:
            yield from flatten_rows(item)


def infer_period(transfer_date: str) -> str:
    month = parse_month(transfer_date)
    return "Vinter" if month in {1, 2, 3} else "Sommer"


def infer_year(start_year: int, transfer_date: str) -> int:
    month = parse_month(transfer_date)
    return start_year if month >= 7 else start_year + 1


def parse_month(transfer_date: str) -> int:
    try:
        return int(transfer_date.split("/")[1])
    except Exception:
        return 7


def dedupe(results: list[dict[str, str]]) -> list[dict[str, str]]:
    seen: dict[tuple[str, str, str, str, str], dict[str, str]] = {}

    for item in results:
        key = (
            item["playerName"].strip().lower(),
            item["fromClub"].strip().lower(),
            item["toClub"].strip().lower(),
            item["season"],
            item["period"],
        )

        if item["fromClub"].strip().lower() == item["toClub"].strip().lower():
            continue

        seen[key] = item

    return sorted(
        seen.values(),
        key=lambda item: (item["season"], item["period"], item["year"], item["playerName"]),
        reverse=True,
    )


if __name__ == "__main__":
    main()
