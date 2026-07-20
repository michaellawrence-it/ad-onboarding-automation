@echo off
:: Generic, documented example for creating an Active Directory user account.
:: Review and replace every Example value before using this file in an environment.
::
:: Suppress command echoing so the operator sees prompts and results instead of
:: the batch commands used to launch them.
::
:: SETLOCAL prevents environment changes made by this wrapper from leaking back
:: to the caller. The script path is placed in a scoped environment variable so
:: both the elevation step and PowerShell loader can reference it safely.
setlocal
set "GENERIC_AD_BATCH_PATH=%~f0"

:: ---------------- ADMINISTRATOR CHECK ----------------
:: NET SESSION is used as a lightweight privilege test: it returns a nonzero
:: error level when the current process is not elevated. Its output is hidden
:: because only the success or failure result matters here.
::
:: On failure, Start-Process relaunches this same file with the Windows Run as
:: administrator verb. The unelevated copy then exits so only one copy continues.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevating to Administrator...
    powershell -NoProfile -Command "Start-Process -FilePath $env:GENERIC_AD_BATCH_PATH -Verb RunAs"
    exit /b
)

:: ---------------- POWERSHELL PAYLOAD LOADER ----------------
:: The loader reads the PowerShell payload from this same BAT file after a unique
:: marker. This hybrid layout keeps the file self-contained while allowing the
:: PowerShell section to use normal indentation, comments, and line breaks.
::
:: -NoProfile avoids machine-specific profile behavior. -ExecutionPolicy Bypass
:: applies only to this process. -NoExit leaves unexpected errors visible; the
:: payload explicitly exits after a successful run.
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command ^
    "$content = Get-Content -LiteralPath $env:GENERIC_AD_BATCH_PATH -Raw; ^
    $marker = ([char]35).ToString() + ' === POWERSHELL PAYLOAD START ==='; ^
    $start = $content.IndexOf($marker); ^
    if ($start -lt 0) { throw 'PowerShell payload marker was not found.' }; ^
    $payload = $content.Substring($start + $marker.Length); ^
    ([scriptblock]::Create($payload)).Invoke()"
exit /b %errorlevel%

# === POWERSHELL PAYLOAD START ===
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

<#
Startup behavior and configuration:

- ErrorActionPreference converts most cmdlet failures into terminating errors.
  This prevents later steps from running after a failed account or group change.
- Import-Module loads the Microsoft Active Directory cmdlets used below.
- Environment-dependent values are centralized here so reviewers can distinguish
  configuration from workflow and replace placeholders in one location.
- UpnSuffix supplies the sign-in and email domain. UserOuPath selects the directory
  container. BasePhoneNumber standardizes office numbers. LogonScript names the
  optional sign-in script. DefaultGroups lists access granted to every new user.
- RelatedRoleTitle is reused by both the title menu and related-account workflow,
  avoiding two separate strings that could drift out of sync.
#>
$UpnSuffix = 'example.com'
$UserOuPath = 'OU=ExampleUsers,DC=example,DC=local'
$BasePhoneNumber = '+1 (555) 010-0000 ext. '
$LogonScript = 'example-logon.bat'
$DefaultGroups = @(
    'Example Remote Access Group'
    'Example Shared Resources Group'
    'Example Security Policy Group'
)
$RelatedRoleTitle = 'Example Assistant Role'

<#
Confirm-Input collects the same required value twice. The loop returns only when
both entries are nonempty and identical, which catches common onboarding typos
before any directory changes occur. It is reused for names and the temporary
password to keep validation behavior consistent.

Read-Host displays ordinary text, so a production version should use an approved
protected password-entry method if the temporary password must not be visible on
screen.
#>
function Confirm-Input {
    param(
        [Parameter(Mandatory)]
        [string] $Prompt
    )

    while ($true) {
        $FirstEntry = Read-Host $Prompt
        $SecondEntry = Read-Host ('Re-enter ' + $Prompt + ' to confirm')

        if ($FirstEntry -eq $SecondEntry -and $FirstEntry) {
            return $FirstEntry
        }

        Write-Host 'Entries do NOT match.' -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=== Create New AD User Account ==='
Write-Host ''

<#
Collect identity values first because all three are required by account creation.
The shared confirmation function gives each field the same nonempty, matching-input
validation behavior.
#>
$FirstName = Confirm-Input -Prompt 'First Name'
$LastName = Confirm-Input -Prompt 'Last Name'
$Password = Confirm-Input -Prompt 'Temporary Password'

<#
The start-date loop performs two checks: the entries must match, and .NET must be
able to parse the value as a date. Valid input is reformatted as yyyyMMdd plus a
fixed time component for a predictable directory metadata string. The attribute
and exact format are examples and should match the requirements of any system that
will consume the value. Invalid input stays in the loop instead of allowing a
partially populated account to be created.
#>
$DateValid = $false

while (-not $DateValid) {
    $RawDate = Read-Host 'Start Date (e.g. 05/13/2026)'
    $ConfirmedRawDate = Read-Host 'Re-enter Start Date to confirm'

    if ($RawDate -ne $ConfirmedRawDate) {
        Write-Host 'Entries do not match.' -ForegroundColor Red
        continue
    }

    try {
        $ParsedDate = [datetime]::Parse($RawDate)
        $ExtensionAttribute1 = $ParsedDate.ToString('yyyyMMdd') + '120000.0Z'
        $DateValid = $true
    }
    catch {
        Write-Host 'Invalid date. Try formats like 05/13/2026 or 5/13/26.' -ForegroundColor Red
    }
}

<#
The operator supplies only the account prefix. Appending the configured suffix
builds the full User Principal Name, and using that same value for email keeps the
example sign-in name and primary address aligned.
#>
$Username = Read-Host 'Username (login and email prefix)'
$UPN = $Username + '@' + $UpnSuffix
$Email = $UPN

<#
Search SamAccountName before making changes. A duplicate would make New-ADUser fail
later, so stopping here produces a clearer message and avoids collecting the
remaining selections for an account that cannot be created.
#>
if (Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue) {
    Write-Host 'ERROR: User already exists.' -ForegroundColor Red
    Read-Host 'Press ENTER to exit'
    exit
}

<#
Numbered menus standardize common office values and reduce typing differences. The
default branch doubles as the Other path, allowing a valid value that is not in the
example list. The selected text is later written to the AD Office property.
#>
Write-Host ''
Write-Host 'Select Office Location:'
Write-Host '1) Example Office 1'
Write-Host '2) Example Office 2'
Write-Host '3) Remote'
Write-Host '4) Other'
$OfficeChoice = Read-Host 'Choice'

switch ($OfficeChoice) {
    '1' { $Office = 'Example Office 1' }
    '2' { $Office = 'Example Office 2' }
    '3' { $Office = 'Remote' }
    default { $Office = Read-Host 'Enter Office Name' }
}

<#
The department menu follows the same pattern. Its final text serves two purposes:
it populates the AD Department property and identifies a same-named group later in
the script. That design is concise, but it requires department values and group
names to match in the target environment.
#>
Write-Host ''
Write-Host 'Select Department:'
Write-Host '1) Example Department 1'
Write-Host '2) Example Department 2'
Write-Host '3) Example Department 3'
Write-Host '4) Other'
$DepartmentChoice = Read-Host 'Choice'

switch ($DepartmentChoice) {
    '1' { $Department = 'Example Department 1' }
    '2' { $Department = 'Example Department 2' }
    '3' { $Department = 'Example Department 3' }
    default { $Department = Read-Host 'Enter Department' }
}

<#
Job titles are also normalized through a menu. The assistant-role option uses the
central RelatedRoleTitle variable because that selection conditionally opens the
related-account assignment step below. Custom titles remain possible through the
default branch.
#>
Write-Host ''
Write-Host 'Select Job Title:'
Write-Host '1) Example Job Title 1'
Write-Host '2) Example Job Title 2'
Write-Host '3) Example Assistant Role'
Write-Host '4) Other'
$TitleChoice = Read-Host 'Choice'

switch ($TitleChoice) {
    '1' { $Title = 'Example Job Title 1' }
    '2' { $Title = 'Example Job Title 2' }
    '3' { $Title = $RelatedRoleTitle }
    default { $Title = Read-Host 'Enter Job Title' }
}

<#
Manager is a linked AD property and expects the manager account's Distinguished
Name, not just its display text. The menu first chooses a readable placeholder
name; Get-ADUser then resolves that name to a DN for New-ADUser. These placeholders
must be replaced with unique directory names. A production implementation should
also explicitly handle no match or multiple matches before account creation.
#>
Write-Host ''
Write-Host 'Select Manager:'
Write-Host '1) Example Manager 1'
Write-Host '2) Example Manager 2'
Write-Host '3) Example Manager 3'
Write-Host '4) Other'
$ManagerChoice = Read-Host 'Choice'

switch ($ManagerChoice) {
    '1' { $ManagerName = 'Example Manager 1' }
    '2' { $ManagerName = 'Example Manager 2' }
    '3' { $ManagerName = 'Example Manager 3' }
    default { $ManagerName = Read-Host 'Enter Manager Display Name' }
}

$ManagerDN = (
    Get-ADUser -Filter "Name -eq '$ManagerName'" -ErrorAction SilentlyContinue
).DistinguishedName

<#
The team-lead prompt converts a human-readable Yes or No choice into a simple flag.
Only choice 1 means Yes; every other value defaults to No. This conservative default
avoids assigning elevated or exceptional metadata because of a typo.
#>
Write-Host ''
Write-Host 'Is the user a team lead?'
Write-Host '1) Yes'
Write-Host '2) No'
$IsTeamLeadChoice = Read-Host 'Choice'

switch ($IsTeamLeadChoice) {
    '1' { $IsTeamLead = '1' }
    default { $IsTeamLead = '2' }
}

<#
The special-role prompt uses the same conservative flag pattern. Accounts marked
Yes receive an extensionAttribute3 value that can be queried by the relationship
workflow and by other directory automation.
#>
Write-Host ''
Write-Host 'Is the user assigned the example special role?'
Write-Host '1) Yes'
Write-Host '2) No'
$IsSpecialRoleChoice = Read-Host 'Choice'

switch ($IsSpecialRoleChoice) {
    '1' { $IsSpecialRole = '1' }
    default { $IsSpecialRole = '2' }
}

<#
Related-account assignment runs only for the configured assistant title. It:

1. Queries users carrying the example special-role flag and requests email data.
2. Wraps results in an array so Count works consistently for zero, one, or many.
3. Displays numbered choices and accepts a comma-separated selection.
4. Uses TryParse and bounds checks so invalid indexes are ignored safely.
5. Keeps only entries with email addresses, then stores them as one semicolon-
   delimited string for the example relationship attribute.

This demonstrates a many-to-one metadata relationship without embedding real
people or organizational roles in the template.
#>
$RelatedUserEmails = ''

if ($Title -eq $RelatedRoleTitle) {
    $RelatedUsers = @(
        Get-ADUser -Filter "extensionAttribute3 -eq 'isSpecialRole'" -Properties EmailAddress
    )

    if ($RelatedUsers.Count -gt 0) {
        Write-Host ''
        Write-Host 'Assign related user(s) (comma-separated, blank = none):'

        $Index = 0
        foreach ($RelatedUser in $RelatedUsers) {
            $Index++
            Write-Host ('{0}) {1} ({2})' -f $Index, $RelatedUser.Name, $RelatedUser.EmailAddress)
        }

        $Selection = Read-Host 'Choice'
        $PickedEmails = @()

        foreach ($Entry in ($Selection -split ',')) {
            $Number = 0

            if ([int]::TryParse($Entry.Trim(), [ref]$Number)) {
                if (
                    $Number -ge 1 -and
                    $Number -le $RelatedUsers.Count -and
                    $RelatedUsers[$Number - 1].EmailAddress
                ) {
                    $PickedEmails += $RelatedUsers[$Number - 1].EmailAddress
                }
            }
        }

        $RelatedUserEmails = $PickedEmails -join ';'
    }
    else {
        Write-Host 'No users are flagged with the example special role.' -ForegroundColor Yellow
    }
}

<#
The office phone is assembled from one centrally configured base number and an
operator-supplied extension, keeping formatting consistent. Mobile is collected
separately because it is already a complete number and may use a different format.
#>
$Extension = Read-Host 'Phone Extension'
$Phone = $BasePhoneNumber + $Extension
$Mobile = Read-Host 'Mobile Phone'

<#
New-ADUser performs the main directory write. The hashtable groups the collected
values by parameter name and is splatted into the cmdlet, which keeps the call easy
to review and avoids fragile line-continuation characters.

The values fall into these property groups:

- Identity: Name, DisplayName, GivenName, Surname, SamAccountName, and UPN.
- Contact and organization: email, title, office, department, phones, and manager.
- Security and placement: the temporary password, forced password change, enabled
  state, destination OU, and logon script.

The password is converted to SecureString only at the cmdlet boundary because the
confirmation function collected it as text. ChangePasswordAtLogon limits how long
the temporary credential remains usable. The explicit OU prevents the account from
falling into the directory's default user container.
#>
$DisplayName = $FirstName + ' ' + $LastName
$NewUserParameters = @{
    Name                  = $DisplayName
    DisplayName           = $DisplayName
    GivenName             = $FirstName
    Surname               = $LastName
    SamAccountName        = $Username
    UserPrincipalName     = $UPN
    EmailAddress          = $Email
    Title                 = $Title
    Office                = $Office
    Department            = $Department
    OfficePhone           = $Phone
    MobilePhone           = $Mobile
    Manager               = $ManagerDN
    AccountPassword       = ConvertTo-SecureString $Password -AsPlainText -Force
    ChangePasswordAtLogon = $true
    Enabled               = $true
    Path                  = $UserOuPath
    ScriptPath            = $LogonScript
}

New-ADUser @NewUserParameters

<#
Extension attributes hold example metadata that does not have a dedicated standard
property. extensionAttribute1 is always added for the start date; attributes 2, 3,
and 4 are added to the hashtable only when applicable. Building one Replace map and
sending one Set-ADUser call reduces separate directory writes and prevents empty
optional values from being written. This occurs after New-ADUser because the account
must exist before it can be updated by identity.
#>
$ReplaceHash = @{
    extensionAttribute1 = $ExtensionAttribute1
}

if ($IsTeamLead -eq '1') {
    $ReplaceHash['extensionAttribute2'] = 'isTeamLead'
}

if ($IsSpecialRole -eq '1') {
    $ReplaceHash['extensionAttribute3'] = 'isSpecialRole'
}

if ($RelatedUserEmails) {
    $ReplaceHash['extensionAttribute4'] = $RelatedUserEmails
}

Set-ADUser -Identity $Username -DisplayName $DisplayName -Replace $ReplaceHash

<#
Group membership is applied after the user exists. The foreach loop grants every
configured baseline group without repeating Add-ADGroupMember statements. The last
call adds the department-specific group selected earlier. Because errors terminate
the script, a missing or misspelled group prevents a misleading success message.

In production, confirm that these groups grant only the intended least-privilege
access before using the template.
#>
foreach ($Group in $DefaultGroups) {
    Add-ADGroupMember -Identity $Group -Members $Username
}

Add-ADGroupMember -Identity $Department -Members $Username

<#
This message is reached only if account creation, metadata updates, and group
assignments completed without a terminating error. Read-Host gives the operator
time to read the result, and exit closes the elevated PowerShell process cleanly.
#>
Write-Host ''
Write-Host 'User created successfully.' -ForegroundColor Green
Read-Host 'Press ENTER to exit'
exit 0
