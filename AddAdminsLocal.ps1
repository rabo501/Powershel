$servers = Get-Content ".\all_servers.txt"
$accountToAdd = "BOLKOW\Administrator"   # Możesz tu wpisać dowolne konto lub grupę domenową

# Pobierz poświadczenia z uprawnieniami administratora (najlepiej konto domenowe)
$cred = Get-Credential

foreach ($server in $servers) {
    Write-Host "Dodaję $accountToAdd do lokalnych administratorów na serwerze $server..."
    try {
        Invoke-Command -ComputerName $server -Credential $cred -ScriptBlock {
            param($account)
            Add-LocalGroupMember -Group "Administratorzy" -Member $account
            Add-LocalGroupMember -Group "Administrators" -Member $account
        } -ArgumentList $accountToAdd -ErrorAction Stop
        Write-Host "OK na $server"
    }
   catch {
    $errMsg = $error[0].Exception.Message
   Write-Host ("Błąd na " + $server + ": " + $errMsg)
    }
}
Write-Host "Operacja zakończona."