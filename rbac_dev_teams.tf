# 실제 라이브 클러스터 상태를 그대로 코드화 (2026-09-18 kubectl로 확인한 값 기준).
# rag-system/vkey-system 둘 다 "팀 공용 ServiceAccount 하나를 여러 명이 공유"하는
# 의도된 설계다(개인별 SA 아님 — 책임은 팀 단위로 짐, 세션 논의로 확정됨).
#
# 목적: 엑셀 대장과 실제 클러스터 상태가 어긋나는 사고(권한 범위가 문서와 다르게
# 적용되어 있던 것)가 재발하지 않도록, 이 파일이 "무엇이 실제로 적용되어 있는지"의
# 유일한 소스가 되게 한다. 엑셀은 이후 이 코드에서 뽑아낸 요약본 역할만 한다.

locals {
  dev_teams = {
    rag = {
      namespace            = "rag-system"
      service_account_name = "rag-dev-sa"
      role_name            = "rag-dev-role"
      role_binding_name    = "rag-dev-binding"
    }
    vkey = {
      namespace            = "vkey-system"
      service_account_name = "vkey-dev-sa"
      role_name            = "vkey-dev-role"
      role_binding_name    = "vkey-dev-binding"
    }
  }

  # rag/vkey 둘 다 완전히 동일한 규칙을 쓰고 있음(kubectl로 확인됨).
  dev_role_rules = [
    {
      api_groups = [""]
      resources = [
        "pods", "pods/log", "pods/exec", "pods/portforward",
        "services", "configmaps", "secrets", "persistentvolumeclaims",
      ]
      verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
    },
    {
      api_groups = ["apps"]
      resources  = ["deployments", "replicasets", "statefulsets"]
      verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
    },
    {
      api_groups = ["gateway.networking.k8s.io"]
      resources  = ["httproutes"]
      verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
    },
  ]
}

resource "kubernetes_service_account" "dev" {
  for_each = local.dev_teams

  metadata {
    name      = each.value.service_account_name
    namespace = each.value.namespace
  }

  # 실제 라이브 값(false)에 맞춤 — provider 기본값(true)과 달라서 명시 필요.
  automount_service_account_token = false
}

resource "kubernetes_role" "dev" {
  for_each = local.dev_teams

  metadata {
    name      = each.value.role_name
    namespace = each.value.namespace
  }

  dynamic "rule" {
    for_each = local.dev_role_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = rule.value.verbs
    }
  }
}

resource "kubernetes_role_binding" "dev" {
  for_each = local.dev_teams

  metadata {
    name      = each.value.role_binding_name
    namespace = each.value.namespace
  }

  subject {
    kind      = "ServiceAccount"
    name      = each.value.service_account_name
    namespace = each.value.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = each.value.role_name
  }
}
