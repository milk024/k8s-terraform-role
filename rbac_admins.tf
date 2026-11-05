# 개인별 클러스터 관리자 계정.
# 팀 공용 SA(rbac_dev_teams.tf)에 cluster-admin을 붙이면 같은 SA를 쓰는 팀원 전원이
# 관리자가 되고, kubeadm의 kubernetes-admin 인증서는 개별 회수가 안 된다. 그래서 관리자로
# 승격하는 사람은 kube-system에 전용 SA를 만들고 cluster-admin에 바인딩한다.
# 회수: 이 맵에서 항목을 지우고 apply (SA 삭제 → 발급된 토큰 즉시 무효).
# kubeconfig 토큰은 Terraform이 아니라 `kubectl create token <sa> -n kube-system --duration=8760h`로 발급한다
# (토큰이 tfstate에 평문으로 남지 않게 하기 위함).

locals {
  cluster_admins = {
    # 2026-11-05 dev5(rag-system, rag-dev-sa 공유) → 관리자 승격. kubectl로 먼저 생성 후 import.
    dev5 = {
      service_account_name = "dev5-admin"
      issued_to            = "dev5"
    }
  }
}

resource "kubernetes_service_account" "cluster_admin" {
  for_each = local.cluster_admins

  metadata {
    name      = each.value.service_account_name
    namespace = "kube-system"
  }

  # kubeconfig 전용 SA라 Pod에 토큰을 마운트할 일이 없다. 라이브 값(false)과도 일치.
  automount_service_account_token = false
}

resource "kubernetes_cluster_role_binding" "cluster_admin" {
  for_each = local.cluster_admins

  metadata {
    name = each.value.service_account_name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = each.value.service_account_name
    namespace = "kube-system"
  }
}

# kubectl로 먼저 만든 리소스를 state에 편입. import 후에는 지워도 된다.
import {
  to = kubernetes_service_account.cluster_admin["dev5"]
  id = "kube-system/dev5-admin"
}

import {
  to = kubernetes_cluster_role_binding.cluster_admin["dev5"]
  id = "dev5-admin"
}
