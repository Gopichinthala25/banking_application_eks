variable "repository_name" {
  description = "Name of the single ECR repository that holds every service image."
  type        = string
}

variable "max_image_count" {
  description = "How many recent images to retain (lifecycle policy)."
  type        = number
  default     = 40
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
