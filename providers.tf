# 로컬 개발 시엔 기본 kubeconfig(~/.kube/config)를 그대로 쓴다.
# admin_manager/k8s_manager와 동일하게, in-cluster에서 이 코드를 실행할 계획은
# 없음 — Terraform은 사람이(또는 CI 파이프라인이) 클러스터 밖에서 apply하는 도구.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
