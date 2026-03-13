variable "rule_name"{}
variable "description"{}
variable "event_pattern"{}
variable "target_id" {}
variable "target_arn" {}
variable "tags" {
  type    = map(string)
  default = {}
}