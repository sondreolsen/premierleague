param(
  [string]$OutputDir = "data",
  [int]$StartSeason = 2020
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-DefaultSeason {
  $now = Get-Date
  $year = $now.Year

  if ($now.Month -ge 7) {
    return $year
  }

  return ($year - 1)
}

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-EnvFileValues {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $envPath = Join-Path $ProjectRoot ".env.local"
  if (-not (Test-Path -LiteralPath $envPath)) {
    return @{}
  }

  $values = @{}
  foreach ($line in Get-Content -LiteralPath $envPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }

    $pair = $trimmed -split "=", 2
    if ($pair.Count -eq 2) {
      $values[$pair[0].Trim()] = $pair[1].Trim().Trim('"')
    }
  }

  return $values
}

function Convert-TransferRow {
  param([Parameter(Mandatory = $true)]$Row)

  $movement = [string]$Row.transfer_movement
  $fromClub = if ($movement -eq "in") { $Row.club_involved_name } else { $Row.club_name }
  $toClub = if ($movement -eq "in") { $Row.club_name } else { $Row.club_involved_name }

  return @{
    playerName = $Row.player_name
    fromClub = $fromClub
    toClub = $toClub
    fee = $Row.fee
    movement = $movement
    period = $Row.transfer_period
    season = $Row.season
    year = $Row.year
    position = $Row.position
  }
}

function Get-TransferSnapshot {
  $uri = "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-league.csv"
  $csvText = Invoke-RestMethod -Uri $uri -Method Get
  $rows = $csvText | ConvertFrom-Csv

  $results = foreach ($row in $rows) {
    Convert-TransferRow -Row $row
  }

  return @{
    generatedAt = (Get-Date).ToString("o")
    source = "https://github.com/ewenme/transfers"
    count = @($results).Count
    results = @($results)
  }
}

function Get-StandingsSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][int]$FromSeason,
    [Parameter(Mandatory = $true)][int]$ToSeason
  )

  $seasons = @{}

  foreach ($season in $FromSeason..$ToSeason) {
    $uri = "https://api.football-data.org/v4/competitions/PL/standings?season=$season"
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers @{ "X-Auth-Token" = $Token } -Method Get
    } catch {
      Write-Warning "Hopper over sesong $season fordi API-et svarte med feil."
      continue
    }

    $payload = $response.Content | ConvertFrom-Json
    $standings = @($payload.standings)
    $tableBlock = $standings | Where-Object { $_.type -eq "TOTAL" } | Select-Object -First 1

    if (-not $tableBlock) {
      $tableBlock = $standings | Select-Object -First 1
    }

    $table = @()
    foreach ($entry in @($tableBlock.table)) {
      $name = $entry.team.shortName
      if (-not $name) {
        $name = $entry.team.name
      }

      $table += @{
        position = $entry.position
        name = $name
        playedGames = $entry.playedGames
        won = $entry.won
        draw = $entry.draw
        lost = $entry.lost
        goalsFor = $entry.goalsFor
        goalsAgainst = $entry.goalsAgainst
        goalDifference = $entry.goalDifference
        points = $entry.points
      }
    }

    $requestsAvailable = $response.Headers["X-Requests-Available-Minute"]
    if (-not $requestsAvailable) {
      $requestsAvailable = $response.Headers["X-Requests-Available"]
    }

    $seasons[[string]$season] = @{
      season = $season
      competition = $payload.competition.name
      lastUpdated = $response.Headers["Date"]
      throttle = @{
        requestsAvailable = $requestsAvailable
        requestCounterReset = $response.Headers["X-RequestCounter-Reset"]
      }
      table = $table
    }
  }

  return @{
    generatedAt = (Get-Date).ToString("o")
    source = "https://api.football-data.org/v4/competitions/PL/standings"
    seasons = $seasons
  }
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outputPath = Join-Path $projectRoot $OutputDir
Ensure-Directory -Path $outputPath

$token = $env:FOOTBALL_DATA_API_TOKEN
if (-not $token) {
  $envFileValues = Get-EnvFileValues -ProjectRoot $projectRoot
  if ($envFileValues.ContainsKey("FOOTBALL_DATA_API_TOKEN")) {
    $token = $envFileValues["FOOTBALL_DATA_API_TOKEN"]
  }
}

if (-not $token) {
  throw "FOOTBALL_DATA_API_TOKEN mangler."
}

$endSeason = Get-DefaultSeason
$effectiveStartSeason = [Math]::Min($StartSeason, $endSeason)
$standings = Get-StandingsSnapshot -Token $token -FromSeason $effectiveStartSeason -ToSeason $endSeason

if ($standings.seasons.Count -eq 0) {
  throw "Fant ingen sesonger som kunne bygges fra football-data.org med dette tokenet."
}

$transfers = Get-TransferSnapshot

$standings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputPath "standings.json") -Encoding UTF8
$transfers | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputPath "transfers.json") -Encoding UTF8

Write-Host "Skrev standings og transfers til $outputPath"
