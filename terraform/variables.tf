variable "service_account_key_file" {
  description = "Service account key file"
  type        = string
  default     = "devops.json"
}
variable "cloud_id" {
  type        = string
  description = "virtual cloud id"
  nullable    = false
  default     = "b1g55luo57i7k6mc406s"
}

variable "folder_id" {
  type        = string
  description = "id of the folder in cloud"
  nullable    = false
  default     = "b1gkqbt3dm2069u86hsj"
}

variable "zone" {
  type        = string
  description = "geo zone id"
  nullable    = false
  default     = "ru-central1-a"
}
