# Sposób uzycia
# Nalezy strworzyc zaszyfrowany plik z haslem do smtp za pomoca funkcji:
# Read-Host "Podaj hasło do SMTP" -AsSecureString | ConvertFrom-SecureString | Set-Content ".\haslo_smtp.txt"
# TO dsziala tylko na danym komputerze i uzytkowniku
# przed wykonaniem skryptu na innym komputerze lub uzytkowniku nalezy ponownie qygenerowac plik hasla

Add-Type -AssemblyName System.Net.Mail

# Pobierz dane od użytkownika
$recipient = Read-Host "Podaj adres odbiorcy"
$subject = Read-Host "Podaj temat wiadomości"
$body = Read-Host "Podaj treść wiadomości"
$smtpUser = "it@bolkow.pl"
#$smtpPass = Read-Host "Podaj hasło do konta $smtpUser" -AsSecureString
$smtpPass = Get-Content ".\haslo_smtp.txt" | ConvertTo-SecureString

# Dodaj stopkę do treści
$footer = "`n`n---Wiadomość została wysłana automatycznie---"
$bodyWithFooter = $body + $footer

# Zamień SecureString na zwykły tekst (do użycia w .NET)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($smtpPass)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

# Utwórz obiekt MailMessage
$mail = New-Object System.Net.Mail.MailMessage
$mail.From = $smtpUser
$mail.To.Add($recipient)
$mail.Subject = $subject
$mail.Body = $bodyWithFooter

# Utwórz obiekt SmtpClient
$smtp = New-Object System.Net.Mail.SmtpClient("smtp-bolkow.nano.pl", 587)
$smtp.EnableSsl = $true
$smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $password)

# Wyślij wiadomość
try {
    $smtp.Send($mail)
    Write-Host "Wiadomość została wysłana!"
} catch {
    Write-Host "Wystąpił błąd podczas wysyłania: $($_.Exception.Message)"
}

# Wyczyść hasło z pamięci
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)