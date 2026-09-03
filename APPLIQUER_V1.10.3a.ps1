$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "PROJECT XP - Hotfix V1.10.3a Steam return" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host ""

$path = "lib\services\steam_sync_service.dart"

if (-not (Test-Path $path)) {
    throw "Fichier introuvable : $path"
}

$text = Get-Content -Raw -Encoding UTF8 $path
$text = $text -replace "`r`n", "`n"
$text = $text -replace "`r", "`n"

if ($text -match "totalAchievementsKnown:\s*totalAchievementsKnown") {
    Write-Host "[OK] Le return V1.10.3a est deja corrige." -ForegroundColor Green
    exit 0
}

$pattern = @'
    return SteamAllAchievementSyncResult\(
      linkedGames: linked\.length,
      checkedGames: checked,
      skippedFreshGames: skippedFresh,
      gamesWithoutAchievements: noAchievements,
      unavailableGames: unavailable,
      newlyUnlocked: newlyUnlocked,
    \);
'@

$replacement = @'
    return SteamAllAchievementSyncResult(
      linkedGames: linked.length,
      checkedGames: checked,
      skippedFreshGames: skippedFresh,
      gamesWithoutAchievements: noAchievements,
      unavailableGames: unavailable,
      newlyUnlocked: newlyUnlocked,
      totalAchievementsKnown: totalAchievementsKnown,
      issues: List<SteamAchievementSyncIssue>.unmodifiable(
        issues,
      ),
    );
'@

$regex = [regex]::new(
    $pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$matches = $regex.Matches($text)

if ($matches.Count -ne 1) {
    throw "Hotfix impossible : bloc return trouve $($matches.Count) fois."
}

$match = $matches[0]

$updated =
    $text.Substring(0, $match.Index) +
    $replacement +
    $text.Substring($match.Index + $match.Length)

Set-Content -Path $path -Value $updated -Encoding UTF8 -NoNewline

Write-Host "[OK] SteamAllAchievementSyncResult complete." -ForegroundColor Green
Write-Host ""
Write-Host "Lance maintenant :" -ForegroundColor Cyan
Write-Host "  flutter analyze"
Write-Host ""
