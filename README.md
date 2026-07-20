# ad-onboarding-automation

PowerShell-driven Active Directory user provisioning for a 100+ employee HIPAA-regulated healthcare organization.

## Problem
Every new hire meant a manual checklist: create the AD account, set attributes, add security groups, create the mailbox, hope nothing got fat-fingered. Manual entry produced inconsistent attributes — and in an environment where **security-group membership is derived from those attributes**, one typo meant wrong access on day one. The org grew from 65 to 120 employees with no added IT staff; manual provisioning didn't scale.

## Approach
One script owns the whole flow. HR-supplied details go in; a correctly-attributed, correctly-grouped, least-privilege account comes out.

```
HR intake (name, dept, title, location, hire date)
        │
        ▼
New-Employee.ps1
  ├─ Generates username + mailbox per naming convention
  ├─ Creates the AD account in the right OU
  ├─ Stamps department / title / location / hireDate attributes
  └─ Entra ID dynamic-group rules take it from there:
     attributes → security groups → SharePoint/app access
```

The key design choice: the script **doesn't assign groups directly**. It stamps attributes, and [attribute-driven dynamic groups](https://github.com/michaellawrence-it/entra-dynamic-groups) resolve membership. Access logic lives in one reviewable place instead of scattered ad-hoc grants.

## Sample run (fake data)
```powershell
PS> .\New-Employee.ps1 -FirstName Jane -LastName Doe -Department Billing `
      -Title "Billing Associate" -Location "Main Office" -HireDate 2026-07-01

[+] Created CONTOSO\jdoe in OU=Billing,OU=Staff,DC=contoso,DC=com
[+] Attributes stamped: department=Billing, title=Billing Associate, l=Main Office
[+] Mailbox provisioned: jdoe@contoso.com
[i] Dynamic groups will resolve: SG-Billing, SG-MainOffice, SG-AllStaff
```

## Result
- Provisioning errors from manual entry: **eliminated**
- Onboarding time: a checklist of console clicks → **one command**
- Access control: consistent and auditable — membership is a function of HR attributes
- Scaled 65→120 headcount with **zero added IT staff**

## Stack
PowerShell · ActiveDirectory module · Entra ID (dynamic membership rules) · Exchange Online

> All names, domains, and OUs in this repo are sanitized (`contoso.com`, `jdoe`). No production data.
