#VIRTUAL NETWORK OUTPUT VALUE
output "virtual_network_output" {
  value = { for k, v in azurerm_virtual_network.virtual_network : k => {
    id   = v.id
    name = v.name
    guid = v.guid
    }
  }
  description = "virtual network output values"
}
