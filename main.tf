resource "azurerm_virtual_network" "virtual_network" {
  for_each                = var.virtual_network_variables
  name                    = each.value.virtual_network_name
  location                = each.value.virtual_network_location
  resource_group_name     = each.value.virtual_network_resource_group_name
  address_space           = each.value.virtual_network_address_space
  dns_servers             = each.value.virtual_network_dns_servers
  flow_timeout_in_minutes = each.value.virtual_network_flow_timeout_in_minutes
  bgp_community           = each.value.virtual_network_bgp_community
  edge_zone               = each.value.virtual_network_edge_zone
  tags                    = merge(each.value.virtual_network_tags, tomap({ Created_Time = formatdate("DD-MM-YYYY hh:mm:ss ZZZ", timestamp()) }))
  lifecycle { ignore_changes = [tags["Created_Time"]] }

  dynamic "ddos_protection_plan" {
    for_each = each.value.virtual_network_ddos_protection_enable != null && each.value.virtual_network_ddos_protection_plan_name != null ? [1] : []
    content {
      id     = each.value.virtual_network_ddos_protection_plan_name
      enable = each.value.virtual_network_ddos_protection_enable
    }
  }

  dynamic "encryption" {
    for_each = each.value.virtual_network_encryption != null ? [1] : []
    content {
      enforcement = each.value.virtual_network_encryption
    }
  }
}
