# AzureAD Provider PIM Reproduction

This repository contains a Terraform reproduction configuration for testing intermittent AzureAD provider behavior around:

- `azuread_group_member`
- `azuread_app_role_assignment`
- `azuread_group_role_management_policy`
- `azuread_privileged_access_group_eligibility_schedule`

The configuration creates multiple batches of Entra ID groups, app role assignments, PIM group role management policies, and PIM eligibility schedules.

## Requirements

- Terraform
- AzureAD provider credentials with the required Microsoft Graph permissions
- A Microsoft Entra tenant where PIM for Groups is available

## Authentication

The AzureAD provider can be authenticated using environment variables such as:

```zsh
export ARM_CLIENT_ID="<client-id>"
export ARM_CLIENT_SECRET="<client-secret>"
export ARM_TENANT_ID="<tenant-id>"