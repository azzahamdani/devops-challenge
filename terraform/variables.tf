variable "control_plane_private_ips" {
  description = "Static private IPs for the control plane EC2 instances"
  type        = list(string)
  default     = ["10.0.0.10", "10.0.16.10", "10.0.32.10"] # Adjust based on your subnet ranges
}