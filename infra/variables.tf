variable "database_location" {
  description = "directory where sqlite sb is located"
  default     = "/data"
  type        = string
}

variable "database_filename" {
  description = "file name of the sqlite db"
  default     = "instances.db"
  type        = string
}

