variable "classroom_name" {
  description = "Name of the classroom"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}

variable "location" {
  description = "The Azure location to deploy to"
  type        = string
  default     = "westeurope"
}

variable "student_count" {
  description = "Number of students in the classroom"
  type        = number
  default     = 1
} 
