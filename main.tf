terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.9.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "c14c9ee6-90d8-42ff-93bc-a92def63864b"
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the VM administrator."
  type        = string
}

variable "ssh_source_address_prefix" {
  description = "Trusted IPv4 address or CIDR allowed to connect to SSH (port 22)."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_source_address_prefix, 0))
    error_message = "Provide a valid IPv4 CIDR, such as 203.0.113.10/32."
  }
}

variable "vm_admin_username" {
  description = "Administrator username for the Linux virtual machine."
  type        = string
  default     = "azureuser"
}

variable "vm_size" {
  description = "Azure virtual machine size."
  type        = string
  default     = "Standard_B1ms"
}

variable "vm_location" {
  description = "Azure region for the virtual machine and its network resources."
  type        = string
  default     = "westus2"
}

# create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-terraform"
  location = "eastus"
}

# create a storage account
resource "azurerm_storage_account" "storage" {
  name                     = "tfstore20261013a7"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# create network security group
resource "azurerm_network_security_group" "nsg" {
  name        = "my-nsg"
  location    =  azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# create a subnet in the existing East US virtual network
resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# create a separate virtual network in the VM's region
resource "azurerm_virtual_network" "vm" {
  name                = "vm-vnet"
  location            = var.vm_location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

# create a subnet for the VM in its region
resource "azurerm_subnet" "vm" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vm.name
  address_prefixes     = ["10.1.1.0/24"]

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vm]
  }
}

# create a network security group for the VM in its region
resource "azurerm_network_security_group" "vm" {
  name                = "vm-nsg"
  location            = var.vm_location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH-From-Trusted-Source"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_source_address_prefix
    destination_address_prefix = "*"
  }
}

# create a public IP address for the VM
resource "azurerm_public_ip" "vm" {
  name                = "vm-public-ip"
  location            = var.vm_location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# create a network interface for the VM
resource "azurerm_network_interface" "vm" {
  name                = "vm-nic"
  location            = var.vm_location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# associate the VM network security group with its network interface
resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# create an Ubuntu Linux virtual machine with SSH key authentication
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "terraform-linux-vm"
  computer_name                   = "terraform-linux-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = var.vm_location
  size                            = var.vm_size
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# display the virtual machine's public IP address after deployment
output "vm_public_ip" {
  description = "Public IP address for the Linux virtual machine."
  value       = azurerm_public_ip.vm.ip_address
}
