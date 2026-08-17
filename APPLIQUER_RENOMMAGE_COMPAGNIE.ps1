param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$LibPath = Join-Path $ProjectRoot 'lib'
$MarkerDirectory = Join-Path $ProjectRoot '.dart_tool'
if (-not (Test-Path $MarkerDirectory)) {
    New-Item -ItemType Directory -Path $MarkerDirectory | Out-Null
}
$MarkerPath = Join-Path $MarkerDirectory 'project_xp_compagnie_rename_done'

if (-not (Test-Path $LibPath)) {
    throw "Le dossier lib est introuvable dans : $ProjectRoot"
}

if (Test-Path $MarkerPath) {
    throw "Le renommage COMPAGNIE a deja ete applique dans ce projet. Ne relance pas ce script."
}

Write-Step "Verification du depot Git"
if (Test-Path (Join-Path $ProjectRoot '.git')) {
    Push-Location $ProjectRoot
    try {
        $dirty = @(git status --porcelain | Where-Object {
            $_ -notmatch 'APPLIQUER_RENOMMAGE_COMPAGNIE\.ps1$' -and
            $_ -notmatch 'README_COMPAGNIE\.txt$'
        })
        if ($dirty.Count -gt 0) {
            $dirty | ForEach-Object { Write-Host $_ }
            throw "Le depot Git n'est pas propre. Commit ou annule les changements avant le renommage."
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Warning "Aucun depot Git detecte. Le script continue, mais aucun point de retour Git n'est disponible."
}

Write-Step "Remplacement de Squad par Compagnie dans le code et les textes"

$roots = @(
    'lib', 'android', 'ios', 'web', 'windows', 'linux', 'macos', 'backend'
)

$extensions = @(
    '.dart', '.yaml', '.yml', '.xml', '.kt', '.kts', '.swift', '.plist',
    '.html', '.json', '.md', '.txt', '.cmake', '.cc', '.cpp', '.h'
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($root in $roots) {
    $rootPath = Join-Path $ProjectRoot $root
    if (-not (Test-Path $rootPath)) {
        continue
    }

    Get-ChildItem -Path $rootPath -Recurse -File | ForEach-Object {
        if ($extensions -notcontains $_.Extension.ToLowerInvariant()) {
            return
        }

        $content = [System.IO.File]::ReadAllText($_.FullName)
        $updated = $content.Replace('SQUAD', 'COMPAGNIE')
        $updated = $updated.Replace('Squad', 'Compagnie')
        $updated = $updated.Replace('squad', 'compagnie')

        if ($updated -ne $content) {
            [System.IO.File]::WriteAllText($_.FullName, $updated, $utf8NoBom)
        }
    }
}

Write-Step "Renommage des fichiers contenant squad"

foreach ($root in $roots) {
    $rootPath = Join-Path $ProjectRoot $root
    if (-not (Test-Path $rootPath)) {
        continue
    }

    $files = Get-ChildItem -Path $rootPath -Recurse -File |
        Where-Object { $_.Name -match '(?i)squad' } |
        Sort-Object { $_.FullName.Length } -Descending

    foreach ($file in $files) {
        $newName = [regex]::Replace(
            $file.Name,
            'squad',
            'compagnie',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($newName -ne $file.Name) {
            Rename-Item -LiteralPath $file.FullName -NewName $newName
        }
    }
}

Write-Step "Renommage des dossiers contenant squad"

foreach ($root in $roots) {
    $rootPath = Join-Path $ProjectRoot $root
    if (-not (Test-Path $rootPath)) {
        continue
    }

    $directories = Get-ChildItem -Path $rootPath -Recurse -Directory |
        Where-Object { $_.Name -match '(?i)squad' } |
        Sort-Object { $_.FullName.Length } -Descending

    foreach ($directory in $directories) {
        $newName = [regex]::Replace(
            $directory.Name,
            'squad',
            'compagnie',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($newName -ne $directory.Name) {
            Rename-Item -LiteralPath $directory.FullName -NewName $newName
        }
    }
}

function Add-LegacyStorageMigration {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$NewKey,
        [Parameter(Mandatory = $true)][string]$LegacyKey
    )

    if (-not (Test-Path $FilePath)) {
        throw "Fichier de stockage attendu introuvable : $FilePath"
    }

    $content = [System.IO.File]::ReadAllText($FilePath)

    if ($content.Contains('_legacyStorageKey')) {
        return
    }

    $storageDeclaration = "static const String _storageKey =`r`n      '$NewKey';"
    if (-not $content.Contains($storageDeclaration)) {
        $storageDeclaration = "static const String _storageKey =`n      '$NewKey';"
    }

    if (-not $content.Contains($storageDeclaration)) {
        throw "Impossible de trouver _storageKey dans $FilePath"
    }

    $replacementDeclaration = $storageDeclaration + "`r`n`r`n  // Compatibilite : copie une seule fois les anciennes donnees Squad.`r`n  static const String _legacyStorageKey =`r`n      '$LegacyKey';"
    $content = $content.Replace($storageDeclaration, $replacementDeclaration)

    $oldReadWindows = "final String? raw =`r`n        prefs.getString(_storageKey);"
    $oldReadUnix = "final String? raw =`n        prefs.getString(_storageKey);"

    $newRead = @"
String? raw =
        prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      final String? legacyRaw =
          prefs.getString(_legacyStorageKey);

      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        await prefs.setString(
          _storageKey,
          legacyRaw,
        );

        raw = legacyRaw;
      }
    }
"@

    if ($content.Contains($oldReadWindows)) {
        $content = $content.Replace($oldReadWindows, $newRead.TrimEnd())
    }
    elseif ($content.Contains($oldReadUnix)) {
        $content = $content.Replace($oldReadUnix, $newRead.TrimEnd())
    }
    else {
        throw "Impossible de trouver la lecture de _storageKey dans $FilePath"
    }

    [System.IO.File]::WriteAllText($FilePath, $content, $utf8NoBom)
}

Write-Step "Migration non destructive des demandes et invitations existantes"

Add-LegacyStorageMigration `
    -FilePath (Join-Path $ProjectRoot 'lib/services/compagnie_request_storage.dart') `
    -NewKey 'project_xp_compagnie_join_requests' `
    -LegacyKey 'project_xp_squad_join_requests'

Add-LegacyStorageMigration `
    -FilePath (Join-Path $ProjectRoot 'lib/services/compagnie_invitation_storage.dart') `
    -NewKey 'project_xp_compagnie_team_invitations' `
    -LegacyKey 'project_xp_squad_team_invitations'

Write-Step "Creation du marqueur de migration"
[System.IO.File]::WriteAllText(
    $MarkerPath,
    "Renommage Squad -> Compagnie applique le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').`r`n",
    $utf8NoBom
)

Write-Step "Controle des anciennes references Squad restantes"
$remaining = @()

foreach ($root in $roots) {
    $rootPath = Join-Path $ProjectRoot $root
    if (-not (Test-Path $rootPath)) {
        continue
    }

    Get-ChildItem -Path $rootPath -Recurse -File | ForEach-Object {
        if ($extensions -notcontains $_.Extension.ToLowerInvariant()) {
            return
        }

        $matches = Select-String -LiteralPath $_.FullName -Pattern 'Squad|SQUAD|squad' -AllMatches
        foreach ($match in $matches) {
            # Les deux anciennes cles doivent rester volontairement pour migrer
            # les donnees locales deja presentes sur l'appareil.
            if ($match.Line -match 'project_xp_squad_join_requests|project_xp_squad_team_invitations|anciennes donnees Squad') {
                continue
            }

            $remaining += "{0}:{1}: {2}" -f $_.FullName, $match.LineNumber, $match.Line.Trim()
        }
    }
}

if ($remaining.Count -gt 0) {
    Write-Warning "Il reste des references Squad a verifier :"
    $remaining | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
}
else {
    Write-Host "OK : aucune reference Squad fonctionnelle restante." -ForegroundColor Green
    Write-Host "Les seules anciennes cles conservees servent a migrer les donnees existantes." -ForegroundColor DarkGray
}

Write-Step "Termine"
Write-Host "Lance maintenant :" -ForegroundColor Green
Write-Host "  flutter analyze"
Write-Host "Puis, si aucune erreur :"
Write-Host "  flutter run"
Write-Host ""
Write-Host "Ne commit pas avant d'avoir teste Compagnie sur le telephone." -ForegroundColor Yellow

if (Test-Path (Join-Path $ProjectRoot '.git')) {
    Push-Location $ProjectRoot
    try {
        Write-Host "`nGit status :" -ForegroundColor Cyan
        git status --short
    }
    finally {
        Pop-Location
    }
}
