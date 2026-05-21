terraform {
  required_version = "1.15.3"

  # cloud {
    
  #   organization = "..."

  #   workspaces {
  #     name = "..."
  #   }
  # }

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.8.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

  }
}

provider "azuread" {
  alias = "ddv"
}

provider "azuread" {
  alias = "rtl"
}

data "azuread_client_config" "ddv" {
  provider = azuread.ddv
}

data "azuread_client_config" "rtl" {
  provider = azuread.rtl
}

resource "random_id" "suffix" {
  byte_length = 4
}

variable "batch_count" {
  type    = number
  default = 10
}

locals {
  prefix = "azad-repro-${random_id.suffix.hex}"

  batches = toset([
    for i in range(var.batch_count) : format("%02d", i)
  ])

  personas = toset([
    "developers",
    "maintainers",
    "pim"
  ])

  eligible_personas = toset([
    "developers",
    "maintainers"
  ])

  group_matrix = {
    for item in flatten([
      for batch in local.batches : [
        for persona in local.personas : {
          key     = "${batch}-${persona}"
          batch   = batch
          persona = persona
        }
      ]
    ]) : item.key => item
  }

  eligibility_matrix = {
    for item in flatten([
      for batch in local.batches : [
        for persona in local.eligible_personas : {
          key     = "${batch}-${persona}"
          batch   = batch
          persona = persona
        }
      ]
    ]) : item.key => item
  }
}

# Parent groups: 10 per provider alias

resource "azuread_group" "ddv_parent" {
  provider = azuread.ddv
  for_each = local.batches

  display_name     = "${local.prefix}-ddv-${each.key}-parent"
  security_enabled = true

  owners = [
    data.azuread_client_config.ddv.object_id
  ]
}

resource "azuread_group" "rtl_parent" {
  provider = azuread.rtl
  for_each = local.batches

  display_name     = "${local.prefix}-rtl-${each.key}-parent"
  security_enabled = true

  owners = [
    data.azuread_client_config.rtl.object_id
  ]
}


# Persona groups: 10 batches x 3 personas x 2 aliases = 60 groups


resource "azuread_group" "ddv" {
  provider = azuread.ddv
  for_each = local.group_matrix

  display_name     = "${local.prefix}-ddv-${each.value.batch}-${each.value.persona}"
  security_enabled = true

  owners = [
    data.azuread_client_config.ddv.object_id
  ]
}

resource "azuread_group" "rtl" {
  provider = azuread.rtl
  for_each = local.group_matrix

  display_name     = "${local.prefix}-rtl-${each.value.batch}-${each.value.persona}"
  security_enabled = true

  owners = [
    data.azuread_client_config.rtl.object_id
  ]
}

# Nested group memberships: 60 memberships

resource "azuread_group_member" "ddv_nested" {
  provider = azuread.ddv
  for_each = local.group_matrix

  group_object_id  = azuread_group.ddv_parent[each.value.batch].object_id
  member_object_id = azuread_group.ddv[each.key].object_id
}

resource "azuread_group_member" "rtl_nested" {
  provider = azuread.rtl
  for_each = local.group_matrix

  group_object_id  = azuread_group.rtl_parent[each.value.batch].object_id
  member_object_id = azuread_group.rtl[each.key].object_id
}

# App role UUIDs

resource "random_uuid" "ddv_app_role_access" {
  for_each = local.batches
}

resource "random_uuid" "ddv_app_role_extra" {
  for_each = local.batches
}

resource "random_uuid" "rtl_app_role_access" {
  for_each = local.batches
}

resource "random_uuid" "rtl_app_role_extra" {
  for_each = local.batches
}

# Target applications and service principals
resource "azuread_application" "ddv_target" {
  provider = azuread.ddv
  for_each = local.batches

  display_name = "${local.prefix}-ddv-${each.key}-target-app"

  owners = [
    data.azuread_client_config.ddv.object_id
  ]

  app_role {
    allowed_member_types = ["User"]
    description          = "Access role for provider inconsistency repro"
    display_name         = "Access"
    enabled              = true
    id                   = random_uuid.ddv_app_role_access[each.key].result
    value                = "Repro.Access"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Extra role for provider inconsistency repro"
    display_name         = "Extra"
    enabled              = true
    id                   = random_uuid.ddv_app_role_extra[each.key].result
    value                = "Repro.Extra"
  }
}

resource "azuread_service_principal" "ddv_target" {
  provider = azuread.ddv
  for_each = local.batches

  client_id = azuread_application.ddv_target[each.key].client_id

  owners = [
    data.azuread_client_config.ddv.object_id
  ]
}

resource "azuread_application" "rtl_target" {
  provider = azuread.rtl
  for_each = local.batches

  display_name = "${local.prefix}-rtl-${each.key}-target-app"

  owners = [
    data.azuread_client_config.rtl.object_id
  ]

  app_role {
    allowed_member_types = ["User"]
    description          = "Access role for provider inconsistency repro"
    display_name         = "Access"
    enabled              = true
    id                   = random_uuid.rtl_app_role_access[each.key].result
    value                = "Repro.Access"
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "Extra role for provider inconsistency repro"
    display_name         = "Extra"
    enabled              = true
    id                   = random_uuid.rtl_app_role_extra[each.key].result
    value                = "Repro.Extra"
  }
}

resource "azuread_service_principal" "rtl_target" {
  provider = azuread.rtl
  for_each = local.batches

  client_id = azuread_application.rtl_target[each.key].client_id

  owners = [
    data.azuread_client_config.rtl.object_id
  ]
}

# App role assignments
resource "azuread_app_role_assignment" "ddv_access" {
  provider = azuread.ddv
  for_each = local.group_matrix

  principal_object_id = azuread_group.ddv[each.key].object_id
  app_role_id         = azuread_application.ddv_target[each.value.batch].app_role_ids["Repro.Access"]
  resource_object_id  = azuread_service_principal.ddv_target[each.value.batch].object_id
}

resource "azuread_app_role_assignment" "rtl_access" {
  provider = azuread.rtl
  for_each = local.group_matrix

  principal_object_id = azuread_group.rtl[each.key].object_id
  app_role_id         = azuread_application.rtl_target[each.value.batch].app_role_ids["Repro.Access"]
  resource_object_id  = azuread_service_principal.rtl_target[each.value.batch].object_id
}

resource "azuread_app_role_assignment" "ddv_pim_extra" {
  provider = azuread.ddv
  for_each = local.batches

  principal_object_id = azuread_group.ddv["${each.key}-pim"].object_id
  app_role_id         = azuread_application.ddv_target[each.key].app_role_ids["Repro.Extra"]
  resource_object_id  = azuread_service_principal.ddv_target[each.key].object_id
}

resource "azuread_app_role_assignment" "rtl_pim_extra" {
  provider = azuread.rtl
  for_each = local.batches

  principal_object_id = azuread_group.rtl["${each.key}-pim"].object_id
  app_role_id         = azuread_application.rtl_target[each.key].app_role_ids["Repro.Extra"]
  resource_object_id  = azuread_service_principal.rtl_target[each.key].object_id
}


# PIM group role management policies
resource "azuread_group_role_management_policy" "ddv_pim_member" {
  provider = azuread.ddv
  for_each = local.batches

  group_id = azuread_group.ddv["${each.key}-pim"].object_id
  role_id  = "member"

  eligible_assignment_rules {
    expiration_required = false
  }

  activation_rules {
    maximum_duration      = "PT8H"
    require_approval      = true
    require_justification = true

    approval_stage {
      primary_approver {
        object_id = azuread_group.ddv["${each.key}-maintainers"].object_id
        type      = "groupMembers"
      }
    }
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "azuread_group_role_management_policy" "rtl_pim_member" {
  provider = azuread.rtl
  for_each = local.batches

  group_id = azuread_group.rtl["${each.key}-pim"].object_id
  role_id  = "member"

  eligible_assignment_rules {
    expiration_required = false
  }

  activation_rules {
    maximum_duration      = "PT8H"
    require_approval      = true
    require_justification = true

    approval_stage {
      primary_approver {
        object_id = azuread_group.rtl["${each.key}-maintainers"].object_id
        type      = "groupMembers"
      }
    }
  }

  lifecycle {
    create_before_destroy = false
  }
}



resource "azuread_privileged_access_group_eligibility_schedule" "ddv" {
  provider = azuread.ddv
  for_each = local.eligibility_matrix

  group_id             = azuread_group.ddv["${each.value.batch}-pim"].object_id
  principal_id         = azuread_group.ddv[each.key].object_id
  assignment_type      = "member"
  permanent_assignment = true
  justification        = "Terraform AzureAD provider inconsistency reproduction"

  lifecycle {
    create_before_destroy = false
  }

  # depends_on = [
  #   azuread_group_role_management_policy.ddv_pim_member
  # ]
}

resource "azuread_privileged_access_group_eligibility_schedule" "rtl" {
  provider = azuread.rtl
  for_each = local.eligibility_matrix

  group_id             = azuread_group.rtl["${each.value.batch}-pim"].object_id
  principal_id         = azuread_group.rtl[each.key].object_id
  assignment_type      = "member"
  permanent_assignment = true
  justification        = "Terraform AzureAD provider inconsistency reproduction"

  lifecycle {
    create_before_destroy = false
  }

  # depends_on = [
  #   azuread_group_role_management_policy.rtl_pim_member
  # ]
}

output "prefix" {
  value = local.prefix
}

output "batch_count" {
  value = var.batch_count
}