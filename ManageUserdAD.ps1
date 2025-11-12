Import-Module ActiveDirectory

function Show-Menu {
    Clear-Host
    Write-Host "      ======== MENU ZARZĄDZANIA UŻYTKOWNIKAMI ========"
    Write-Host "      1. Przegląd użytkowników"
    Write-Host "      2. Dodawanie lub modyfikacja użytkownika"
    Write-Host "      3. Usuwanie użytkownika"
    Write-Host "      4. Przypisywanie użytkownika do grupy"
    Write-Host "      5. Resetowanie hasła użytkownika"
    Write-Host "      6. Odblokowanie konta"
    Write-Host "      7. Wyświetlanie historii logowania"
    Write-Host "      8. Przypisywanie uprawnień/kontenerów OU"
    Write-Host "      9. Masowe dodawanie do grupy (CSV)"
    Write-Host "      10. Eksport listy użytkowników do CSV"
    Write-Host "      0. Wyjście" -ForegroundColor Red
    Write-Host "      ==============================================="
}

function List-Users {
    $ou = Read-Host "Podaj ścieżkę OU (np. OU=StrukturaOrganizacyjna,DC=bolkow,DC=local) lub naciśnij Enter, aby pobrać z U StrukturaOrganizacyjna"
    if ($ou) {
        Get-ADUser -SearchBase $ou -Filter * | Select-Object Name, SamAccountName, Enabled | Format-Table
    } else {
        Get-ADUser -SearchBase "OU=StrukturaOrganizacyjna,DC=bolkow,DC=local" -Filter * | Select-Object Name, SamAccountName, Enabled | Format-Table
        #Get-ADUser -Filter * | Select-Object Name, SamAccountName, Enabled | Format-Table
    }
    Pause
}

function AddOrModify-User {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($user) {
        Write-Host "Użytkownik istnieje. Modyfikacja."
        $newName = Read-Host "Podaj nową nazwę (Enter, aby pominąć)"
        if ($newName) { Set-ADUser -Identity $sam -Name $newName }
        Write-Host "Zmiany zapisane."
    } else {
        Write-Host "Tworzenie nowego użytkownika..."
        $name = Read-Host "Podaj nazwę"
        $pass = Read-Host "Podaj hasło"
        New-ADUser -SamAccountName $sam -Name $name -AccountPassword (ConvertTo-SecureString $pass -AsPlainText -Force) -Enabled $true
        Write-Host "Użytkownik utworzony."
    }
    Pause
}

function Remove-User {
    $sam = Read-Host "Podaj login użytkownika do usunięcia"
    $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($user) {
        $confirm = Read-Host "Czy na pewno chcesz usunąć użytkownika $sam? (T/N)"
        if ($confirm -eq "T") {
            Remove-ADUser -Identity $sam
            Write-Host "Użytkownik usunięty."
        } else {
            Write-Host "Anulowano."
        }
    } else {
        Write-Host "Nie znaleziono użytkownika."
    }
    Pause
}

function Add-UserToGroup {
    $sam = Read-Host "Podaj login użytkownika"
    $group = Read-Host "Podaj nazwę grupy"
    Add-ADGroupMember -Identity $group -Members $sam
    Write-Host "Użytkownik dodany do grupy."
    Pause
}

function Reset-UserPassword {
    $sam = Read-Host "Podaj login użytkownika"
    $pass = Read-Host "Podaj nowe hasło"
    Set-ADAccountPassword -Identity $sam -NewPassword (ConvertTo-SecureString $pass -AsPlainText -Force)
    Write-Host "Hasło zresetowane."
    Pause
}

function Unlock-UserAccount {
    $sam = Read-Host "Podaj login użytkownika"
    Unlock-ADAccount -Identity $sam
    Write-Host "Konto odblokowane."
    Pause
}

function Show-UserLogonHistory {
    $sam = Read-Host "Podaj login użytkownika"
    $user = Get-ADUser -Identity $sam
    $dc = (Get-ADDomainController -Discover).Name
    $events = Get-WinEvent -ComputerName $dc -FilterHashtable @{
        LogName='Security'
        ID=4624
    } | Where-Object { $_.Properties[5].Value -eq $user.SamAccountName }
    $events | Select-Object TimeCreated, Properties | Format-Table
    Pause
}

function Set-UserOU {
    $sam = Read-Host "Podaj login użytkownika"
    $ou = Read-Host "Podaj ścieżkę OU (np. 'OU=Pracownicy,DC=mojadomena,DC=pl')"
    Move-ADObject -Identity (Get-ADUser -Identity $sam).DistinguishedName -TargetPath $ou
    Write-Host "Użytkownik przeniesiony do OU."
    Pause
}

function Bulk-AddToGroup {
    $csvPath = Read-Host "Podaj ścieżkę do pliku CSV z loginami"
    $group = Read-Host "Podaj nazwę grupy"
    $users = Import-Csv $csvPath
    foreach ($u in $users) {
        Add-ADGroupMember -Identity $group -Members $u.SamAccountName
        Write-Host "Dodano $($u.SamAccountName) do grupy $group"
    }
    Pause
}

function Export-UsersToCSV {
    $csvPath = Read-Host "Podaj ścieżkę do pliku docelowego CSV"
    Get-ADUser -Filter * | Select-Object Name, SamAccountName, Enabled | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Eksportowano użytkowników do $csvPath"
    Pause
}

do {
    Show-Menu
    $choice = Read-Host "Wybierz opcję (1-11)"
    switch ($choice) {
        "1" { List-Users }
        "2" { AddOrModify-User }
        "3" { Remove-User }
        "4" { Add-UserToGroup }
        "5" { Reset-UserPassword }
        "6" { Unlock-UserAccount }
        "7" { Show-UserLogonHistory }
        "8" { Set-UserOU }
        "9" { Bulk-AddToGroup }
        "10" { Export-UsersToCSV }
        "0" { exit }
        default { Write-Host "Nieprawidłowy wybór."; Pause }
    }
} while ($true)