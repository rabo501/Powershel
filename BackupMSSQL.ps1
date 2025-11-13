# Sposób uzycia
# Należy stworzyć zaszyfrowany plik z hasłem do smtp za pomocą funkcji:
# Read-Host "Podaj hasło do SMTP" -AsSecureString | ConvertFrom-SecureString | Set-Content ".\haslo_sql.txt"
# To dziala tylko na danym komputerze i użytkowniku
# przed wykonaniem skryptu na innym komputerze lub użytkowniku należy ponownie wygenerować plik hasła



# Parametry backupu
$server = "dc2\mssql"
$database = "Bestia"
$user = "sa"
$backupPath = "d:\Backup\MSSQL"
$retentionDays = 14 # ile dni trzymać backupy
$passwordFile = ".\haslo_sql.txt" # ścieżka do pliku z hasłem

# Odczytaj hasło z pliku (zaszyfrowane SecureString)
$password = Get-Content $passwordFile | ConvertTo-SecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

# Generuj nazwę pliku backupu z datą
$data = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupPath "$database`_$data.bak"

# Komenda T-SQL do backupu
$query = "BACKUP DATABASE [$database] TO DISK = N'$backupFile' WITH NOFORMAT, NOINIT, NAME = N'$database-Full Database Backup', SKIP, NOREWIND, NOUNLOAD, STATS = 10"

# Wykonaj backup przez sqlcmd
$sqlcmd = "sqlcmd -S `"$server`" -U $user -P $plainPassword -Q `"$query`""

try {
    Invoke-Expression $sqlcmd
    Write-Host "Backup bazy '$database' wykonany: $backupFile"
} catch {
    Write-Host "Błąd podczas backupu: $($_.Exception.Message)"
}

# Wyczyść hasło z pamięci
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

# Usuwanie starych backupów
try {
    $oldBackups = Get-ChildItem -Path $backupPath -Filter "$database*.bak" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) }
    foreach ($file in $oldBackups) {
        Remove-Item $file.FullName -Force
        Write-Host "Usunięto stary backup: $($file.Name)"
    }
    if ($oldBackups.Count -eq 0) {
        Write-Host "Brak starych backupów do usunięcia."
    }
} catch {
    Write-Host "Błąd podczas czyszczenia starych backupów: $($_.Exception.Message)"
}