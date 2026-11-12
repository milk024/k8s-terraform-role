# [보류 — 미적용 초안] 2026-11-12 사용자 결정: 네임스페이스 확장 예정이라 ArgoCD 권한 축소 보류 (k8s_manager ADR-0014·0051).
# 이 파일을 main 에 병합하거나 apply 하기 전에 argocd-values.yaml(createClusterRoles·namespaces)도 함께 바꿔야 한다.
# ArgoCD 권한 — 클러스터 전체 → 배포 대상 네임스페이스 3곳으로 축소 (2026-11-12)
#
# argo-cd 차트 기본값은 application-controller 에 클러스터 전체 '*' 권한(사실상 cluster-admin),
# argocd-server 에 클러스터 전체 get/patch/delete 를 준다. ArgoCD 가 배포하는 곳은
# infra / rag-system / vkey-system 뿐이므로:
#   - 차트 값 createClusterRoles=false  → 두 ClusterRole/ClusterRoleBinding 제거
#   - in-cluster 클러스터 Secret 에 namespaces=infra,rag-system,vkey-system (clusterResources 없음)
#     → ArgoCD 는 이 3곳의 네임스페이스 리소스만 보고 만든다. 클러스터 범위 리소스는 다루지 않음
#   - 여기서 3곳에만 Role 을 준다 (차트 값: wsu/k8s-manager k8s/argocd-values.yaml)
# argocd 네임스페이스 자체의 권한(Application CR 읽기 등)은 차트가 만드는 Role 이 그대로 담당.
#
# 네임스페이스 추가: argocd_namespaces 에 추가 + argocd-values.yaml 의 namespaces 에도 추가.

locals {
  argocd_namespaces = toset(["infra", "rag-system", "vkey-system"])
}

# application-controller: 대상 네임스페이스 안에서는 전부 (sync/prune/selfHeal).
# 실제 배포 가능 종류는 AppProject 가 다시 제한한다 (rag/vkey 는 Role·RoleBinding 등 금지).
resource "kubernetes_role" "argocd_controller" {
  for_each = local.argocd_namespaces

  metadata {
    name      = "argocd-application-controller"
    namespace = each.value
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "argocd_controller" {
  for_each = local.argocd_namespaces

  metadata {
    name      = "argocd-application-controller"
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_controller[each.value].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-application-controller"
    namespace = "argocd"
  }
}

# argocd-server (UI/CLI): 화면에서 실제 매니페스트 보기, 리소스 삭제, app patch, 로그·이벤트.
# 차트 기본 ClusterRole 과 같은 내용을 네임스페이스 범위로. Secret 은 조회도 뺀다
# (UI 에서 Secret 값이 보이지 않게 — ArgoCD 도 기본적으로 값은 가리지만 권한 자체를 안 줌).
resource "kubernetes_role" "argocd_server" {
  for_each = local.argocd_namespaces

  metadata {
    name      = "argocd-server"
    namespace = each.value
  }

  rule {
    api_groups = ["", "apps", "gateway.networking.k8s.io", "networking.k8s.io", "batch", "policy", "autoscaling"]
    resources  = ["pods", "services", "configmaps", "persistentvolumeclaims", "serviceaccounts", "deployments", "replicasets", "statefulsets", "daemonsets", "httproutes", "networkpolicies", "jobs", "cronjobs", "poddisruptionbudgets", "horizontalpodautoscalers"]
    verbs      = ["get", "patch", "delete"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "argocd_server" {
  for_each = local.argocd_namespaces

  metadata {
    name      = "argocd-server"
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_server[each.value].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = "argocd"
  }
}

# k8s-manager 의 클러스터 전체 조회 권한. 예전엔 deploy-infra 차트(ArgoCD)가 만들었지만
# ArgoCD 에서 클러스터 범위 권한을 뺐으므로 RBAC 원장인 여기로 옮긴다.
# (ADR-002: k8s_manager 는 모든 namespace 의 Pod 사용률을 모니터링 → 조회만 클러스터 전체)
resource "kubernetes_cluster_role" "k8s_manager_read" {
  metadata {
    name = "k8s-manager-read"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "k8s_manager_read" {
  metadata {
    name = "k8s-manager-read"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.k8s_manager_read.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "k8s-manager"
    namespace = "infra"
  }
}

# ArgoCD(helm 템플릿)가 만든 기존 리소스를 state 에 편입 (재생성 없이). import 후에는 지워도 된다.
import {
  to = kubernetes_cluster_role.k8s_manager_read
  id = "k8s-manager-read"
}

import {
  to = kubernetes_cluster_role_binding.k8s_manager_read
  id = "k8s-manager-read"
}
