param(
  [string]$OutputPath = "site/data/transfers.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceRepo = "https://github.com/eordo/transfermarkt-data"
$baseUri = "https://raw.githubusercontent.com/eordo/transfermarkt-data/master/premier_league"
$startSeason = 1992
$currentYear = (Get-Date).Year
$currentMonth = (Get-Date).Month
$endSeason = if ($currentMonth -ge 7) { $currentYear } else { $currentYear - 1 }

function Convert-SeasonLabel {
  param([int]$StartYear)
  return "{0}/{1}" -f $StartYear, ($StartYear + 1)
}

function Convert-WindowLabel {
  param([string]$Window)

  $normalizedWindow = if ($null -eq $Window) { "" } else { $Window.Trim().ToLowerInvariant() }

  switch ($normalizedWindow) {
    "summer" { return "Sommer" }
    "winter" { return "Vinter" }
    default { return $Window }
  }
}

function Format-Fee {
  param($Fee, [bool]$IsLoan, [string]$DealingClub)

  if ($DealingClub -eq "Retired") {
    return "Lagt opp"
  }

  if ($IsLoan) {
    return "loan transfer"
  }

  if ($null -eq $Fee -or [string]::IsNullOrWhiteSpace([string]$Fee)) {
    return "-"
  }

  $parsed = 0.0
  if (-not [double]::TryParse([string]$Fee, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return [string]$Fee
  }

  if ($parsed -eq 0) {
    return "free transfer"
  }

  if ($parsed -ge 1000000) {
    return ("€{0:0.00}m" -f ($parsed / 1000000.0))
  }

  if ($parsed -ge 1000) {
    return ("€{0:0}k" -f ($parsed / 1000.0))
  }

  return ("€{0:0}" -f $parsed)
}

function Convert-TransferRow {
  param(
    $Row,
    [int]$StartYear
  )

  $movement = ([string]$Row.movement).Trim().ToLowerInvariant()
  $club = [string]$Row.club
  $dealingClub = [string]$Row.dealing_club
  $window = ([string]$Row.window).Trim().ToLowerInvariant()
  $isLoan = [string]$Row.is_loan
  $dateYear = if ($window -eq "winter") { $StartYear + 1 } else { $StartYear }

  $fromClub = if ($movement -eq "in") { $dealingClub } else { $club }
  $toClub = if ($movement -eq "in") { $club } else { $dealingClub }

  return [PSCustomObject]@{
    playerName = [string]$Row.player_name
    fromClub   = $fromClub
    toClub     = $toClub
    fee        = Format-Fee -Fee $Row.fee -IsLoan ($isLoan -eq "1") -DealingClub $dealingClub
    movement   = $movement
    period     = Convert-WindowLabel $window
    season     = Convert-SeasonLabel $StartYear
    year       = [string]$dateYear
    position   = [string]$Row.position
  }
}

function Get-DedupedTransfers {
  param([object[]]$Rows)

  $deduped = @{}

  foreach ($row in $Rows) {
    if (-not $row.playerName -or -not $row.fromClub -or -not $row.toClub) {
      continue
    }

    $key = "{0}|{1}|{2}|{3}|{4}" -f `
      $row.playerName.Trim().ToLowerInvariant(), `
      $row.fromClub.Trim().ToLowerInvariant(), `
      $row.toClub.Trim().ToLowerInvariant(), `
      $row.season, `
      $row.period

    $deduped[$key] = $row
  }

  return @($deduped.Values | Sort-Object `
    @{ Expression = { [int]($_.season.Split('/')[0]) }; Descending = $true }, `
    @{ Expression = { if ($_.period -eq "Vinter") { 2 } elseif ($_.period -eq "Sommer") { 1 } else { 0 } }; Descending = $true }, `
    @{ Expression = { [int]$_.year }; Descending = $true }, `
    @{ Expression = { $_.playerName } })
}

$results = New-Object System.Collections.Generic.List[object]
$seasonCounts = @{}

for ($season = $startSeason; $season -le $endSeason; $season++) {
  $uri = "$baseUri/$season.csv"
  Write-Host "Fetching $uri"

  try {
    $csvText = Invoke-WebRequest -Uri $uri -UseBasicParsing | Select-Object -ExpandProperty Content
  } catch {
    Write-Host "Skipping $season because file could not be fetched."
    continue
  }

  if ([string]::IsNullOrWhiteSpace($csvText)) {
    continue
  }

  $rows = @($csvText | ConvertFrom-Csv)
  if (-not $rows.Count) {
    continue
  }

  $converted = @($rows | ForEach-Object { Convert-TransferRow -Row $_ -StartYear $season })
  $seasonCounts[(Convert-SeasonLabel $season)] = $converted.Count
  foreach ($item in $converted) {
    $results.Add($item)
  }
}

$dedupedResults = @(Get-DedupedTransfers -Rows $results)
if (-not $dedupedResults.Count) {
  throw "No transfer results were generated from $sourceRepo."
}

$parent = Split-Path -Parent $OutputPath
if ($parent) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$payload = [PSCustomObject]@{
  generatedAt = (Get-Date).ToString("o")
  source = $sourceRepo
  count = $dedupedResults.Count
  seasonCounts = $seasonCounts
  results = $dedupedResults
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Wrote $($dedupedResults.Count) transfers to $OutputPath"
