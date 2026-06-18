variable "name" {}
variable "description" {}
variable "multi_region" {}
variable "deletion_window_in_days" {}
variable "enable_key_rotation" {}
variable "tags" {
  type    = map(string)
  default = {}
}
