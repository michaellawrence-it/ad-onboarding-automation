# ad-onboarding-automation

Active Directory user provisioning for a 100+ employee HIPAA-regulated healthcare organization: one self-contained, self-elevating tool that turns a new-hire intake into a correctly-attributed, correctly-grouped, least-privilege account with no console clicking.

## Problem
Every new hire meant a manual checklist: create the AD account, set a dozen properties, add security groups, hope nothing got fat-fingered. Manual entry produced inconsistent attributes, and in an environment where **access is derived from those attributes**, one typo meant wrong access on day one. The org grew from 65 to 120 employees with no added IT staff; manual provisioning didn't scale.

## The tool: [`Create-ADUser.bat`](Create-ADUser.bat)
A single file that is both the launcher and the payload: a batch wrapper that **checks for elevation, relaunches itself as Administrator if needed**, then extracts and runs the PowerShell payload embedded after a marker in the same file. One artifact to deploy, double-click to run, no "open an elevated prompt first" instructions for whoever runs onboarding.

```
Double-click
     |
     v
BAT wrapper: elevation check (net session) -> self-relaunch via RunAs
     |
     v
PowerShell payload (embedded in the same file)
  1. Double-entry confirmation: names, temp password, start date
     (every value typed twice; mismatches loop, never proceed)
  2. Duplicate SamAccountName pre-check before anything is written
  3. Menu-driven selection: office, department, title, manager
     (normalized values, no free-text drift)
  4. New-ADUser via one splatted parameter hashtable:
     identity + contact + OU placement + logon script + forced
     password change at first logon
  5. One Set-ADUser -Replace call stamps extension attributes:
     . extensionAttribute1 = start date (yyyyMMdd) - the hook that
       downstream anniversary automation keys on
     . role flags, and a many-to-one related-account mapping
       (bounds-checked picker, semicolon-joined into one attribute)
  6. Group assignment: baseline groups + the department group
     (department name doubles as its group name - one source of truth)
```

**Fail-fast by design:** `$ErrorActionPreference = 'Stop'` means a failed write terminates the run. A missing group or bad OU can never scroll past and still print "User created successfully."

## Why the attribute stamping matters
The attributes this tool writes are not decoration; they are the org's access API. Department, title, and office feed [Entra ID dynamic membership rules](https://github.com/michaellawrence-it/entra-dynamic-groups) that resolve security-group membership automatically, and the start-date attribute drives anniversary-triggered HR workflows ([powerapps-employee-evaluations](https://github.com/michaellawrence-it/powerapps-employee-evaluations)). Clean input here means every downstream system agrees about who this person is.

## Result
- Provisioning errors from manual entry: **eliminated** (double-entry + menus + duplicate pre-check)
- Onboarding time: a checklist of console clicks became **one guided run**
- Access control: consistent and auditable, membership is a function of stamped attributes
- Scaled 65→120 headcount with **zero added IT staff**

## Stack
PowerShell · ActiveDirectory module · batch/PowerShell hybrid packaging · Entra ID (dynamic membership rules)

> Fully sanitized: `example.com`, example OUs, generic group and role names. The structure and logic are the production tool.
