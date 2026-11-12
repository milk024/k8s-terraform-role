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

  # 2026-11-12: 배포가 ArgoCD(wsu/deploy-rag, wsu/deploy-vkey)로 넘어가면서 배포 목적 쓰기 권한을 회수.
  #   - 앱 배포·설정 변경은 deploy 저장소 PR 로만 한다. 직접 고쳐도 ArgoCD selfHeal 이 되돌린다.
  #   - Secret·postgres·pgadmin·라우트 변경은 인프라 담당(cluster-admin)이 한다.
  # 남긴 것: 조회, 로그, exec/port-forward(디버깅·DB 접속), Pod 삭제(재시작).
  dev_role_rules = [
    {
      api_groups = [""]
      resources  = ["pods"]
      verbs      = ["get", "list", "watch", "delete"]
    },
    {
      api_groups = [""]
      resources  = ["pods/log"]
      verbs      = ["get", "list", "watch"]
    },
    {
      api_groups = [""]
      resources  = ["pods/exec", "pods/portforward"]
      verbs      = ["get", "create"]
    },
    {
      api_groups = [""]
      resources  = ["services", "configmaps", "persistentvolumeclaims", "events"]
      verbs      = ["get", "list", "watch"]
    },
    {
      api_groups = ["apps"]
      resources  = ["deployments", "replicasets", "statefulsets"]
      verbs      = ["get", "list", "watch"]
    },
    {
      api_groups = ["gateway.networking.k8s.io"]
      resources  = ["httproutes"]
      verbs      = ["get", "list", "watch"]
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
