variable "virtual_network_variables" {
  type = map(object({
    virtual_network_name                      = string                 #(Required) The name of the virtual network.
    virtual_network_location                  = string                 #(Required) The location/region where the virtual network is created.
    virtual_network_resource_group_name       = string                 #(Required) The name of the resource group in which to create the virtual network.
    virtual_network_address_space             = list(string)           #(Required) The address space that is used the virtual network.
    virtual_network_dns_servers               = optional(list(string)) #(Optional) List of IP addresses of DNS servers.
    virtual_network_flow_timeout_in_minutes   = optional(number)       #(Optional) The flow timeout in minutes for the virtual network, which is used to enable connection tracking for intra-VM flows. Possible values are between 4 and 30 minutes.
    virtual_network_bgp_community             = optional(string)       #(Optional) The BGP community attribute in format <as-number>:<community-value>.
    virtual_network_edge_zone                 = optional(string)       #(Optional) Specifies the Edge Zone within the Azure Region where this Virtual Network should exist.
    virtual_network_private_endpoint_policies = optional(string)       #(Optional) Reserved for private endpoint network policies configuration.
    virtual_network_ddos_protection_enable    = optional(bool)         #(Optional) Enable/disable DDoS Protection Plan on Virtual Network.
    virtual_network_ddos_protection_plan_name = optional(string)       #(Optional) The resource ID of the DDoS Protection Plan to associate with the Virtual Network.
    virtual_network_encryption                = optional(string)       #(Optional) Specifies if the encrypted Virtual Network allows VMs that does not support encryption. Possible values are AllowUnencrypted and DropUnencrypted.
    virtual_network_network_manager_id        = optional(string)       #(Optional) The ID of the Network Manager to associate with the virtual network.
    virtual_network_network_manager_ips       = optional(list(string)) #(Optional) A list of IP addresses of network manager instances.
    virtual_network_tags                      = optional(map(string))  #(Optional) A mapping of tags which should be assigned to the Virtual Network.
  }))
  description = "Map of Virtual Networks"
  default     = {}
}

variable "target_subscription_id" {
  type        = string
  description = "The target subscription ID where resources will be deployed"
}

