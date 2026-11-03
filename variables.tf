variable "kubeconfig_path" {
  description = "kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "사용할 kubeconfig context (비워두면 current-context 사용)"
  type        = string
  default     = null
}
