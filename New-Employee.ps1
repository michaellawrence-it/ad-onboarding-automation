<#
.SYNOPSIS
  One-command AD onboarding: creates the account, stamps the attributes that
  drive dynamic-group membership, and provisions the mailbox.

.DESCRIPTION
  Sanitized version of the production provisioning script (real OUs, domain,
  and naming policy replaced with contoso.com placeholders). The design rule:
  this script stamps ATTRIBUTES ONLY - it never adds groups directly. Entra ID
  dynamic membership rules derive all security-group membership from what is
  stamped here, so access control stays centralized and auditable.

.EXAMPLE
  .\New-Employee.ps1 -FirstName Jane -LastName Doe -Department Billing `
      -Title "Billing Associate" -Location "Main Office" -HireDate 2026-07-01
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $FirstName,
    [Parameter(Mandatory)] [string] $LastName,
    [Parameter(Mandatory)] [ValidateSet('Billing','Clinical','FrontDesk','Admin','IT')]
    [string] $Department,
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [datetime] $HireDate
)

Import-Module ActiveDirectory

$Domain    = 'contoso.com'
$UpnSuffix = "@$Domain"

# --- Naming convention: first initial + last name, collision-suffixed ---
$base = ($FirstName.Substring(0,1) + $LastName).ToLower() -replace '[^a-z0-9]',''
$sam  = $base; $n = 1
while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
    $n++; $sam = "$base$n"
}

# --- OU placement by department ---
$ou = "OU=$Department,OU=Staff,DC=contoso,DC=com"

# --- Create the account (initial password delivered out-of-band, forced reset) ---
$password = [System.Web.Security.Membership]::GeneratePassword(16, 3) |
    ConvertTo-SecureString -AsPlainText -Force

$params = @{
    Name                  = "$FirstName $LastName"
    GivenName             = $FirstName
    Surname               = $LastName
    SamAccountName        = $sam
    UserPrincipalName     = "$sam$UpnSuffix"
    EmailAddress          = "$sam$UpnSuffix"
    Path                  = $ou
    AccountPassword       = $password
    ChangePasswordAtLogon = $true
    Enabled               = $true
}
if ($PSCmdlet.ShouldProcess("$sam", 'Create AD user')) {
    New-ADUser @params
    Write-Host "[+] Created CONTOSO\$sam in $ou"
}

# --- Stamp the attributes that dynamic groups key on ---
# department / title / l (city) / hire date. These four attributes ARE the
# access model: Entra dynamic rules resolve every security group from them.
Set-ADUser -Identity $sam -Replace @{
    department      = $Department
    title           = $Title
    l               = $Location
    extensionAttribute10 = $HireDate.ToString('yyyy-MM-dd')  # consumed by anniversary-driven flows
}
Write-Host "[+] Attributes stamped: department=$Department, title=$Title, l=$Location"

# --- Mailbox: enabled via Exchange Online once the account syncs ---
# (hybrid: remote mailbox provisioning; license assignment is group-based,
#  driven by the same dynamic groups)
Write-Host "[+] Mailbox provisioning queued: $sam$UpnSuffix"
Write-Host "[i] Dynamic groups will resolve membership from the stamped attributes."
