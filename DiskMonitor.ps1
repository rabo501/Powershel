# Sposób uzycia
# Należy stworzyć zaszyfrowany plik z hasłem do smtp za pomocą funkcji:
# Read-Host "Podaj hasło do SMTP" -AsSecureString | ConvertFrom-SecureString | Set-Content ".\haslo_smtp.txt"
# To dziala tylko na danym komputerze i użytkowniku
# przed wykonaniem skryptu na innym komputerze lub użytkowniku należy ponownie wygenerować plik hasła

 Add-Type -AssemblyName System.Net.Mail

# Parametry
$alertEmail = "informatyk@bolkow.pl"
$smtpUser = "it@bolkow.pl"
$smtpPass = Get-Content ".\haslo_smtp.txt" | ConvertTo-SecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($smtpPass)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
$smtpServer = "smtp-bolkow.nano.pl"
$smtpPort = 587
$limitGB = 10

# Sprawdź dyski
$disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3"
$lowDisks = @()

foreach ($disk in $disks) {
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    if ($freeGB -lt $limitGB) {
        $lowDisks += "Dysk $($disk.DeviceID): wolne $freeGB GB z $([math]::Round($disk.Size / 1GB, 2)) GB"
    }
}

if ($lowDisks.Count -gt 0) {
    $body = "Uwaga! Na następujących dyskach jest mniej niż $limitGB GB wolnego miejsca:`n`n"
    $body += ($lowDisks -join "`n")
    $body += "`n`nWiadomość została wysłana automatycznie"

    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = $smtpUser
    $mail.To.Add($alertEmail)
    $mail.Subject = "ALERT: Mało wolnego miejsca na dysku"
    $mail.Body = $body

    $smtp = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $password)

    try {
        $smtp.Send($mail)
        Write-Host "Alert wysłany na $alertEmail"
    } catch {
        Write-Host "Błąd wysyłania: $($_.Exception.Message)"
    }
} else {
    Write-Host "Wszystkie dyski mają powyżej $limitGB GB wolnego miejsca."
}


[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
