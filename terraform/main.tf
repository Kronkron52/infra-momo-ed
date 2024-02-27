locals {
  k8s_version = "1.27"
  sa_name     = "ed-account"
}

// создаем кластер
resource "yandex_kubernetes_cluster" "k8s-zonal" {
  name       = "edcluster"
  network_id = yandex_vpc_network.ednet.id
  master {
    version = local.k8s_version
    zonal {
      zone      = yandex_vpc_subnet.edsubnet.zone
      subnet_id = yandex_vpc_subnet.edsubnet.id
    }
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.k8s-public-services.id]
  }
  service_account_id      = yandex_iam_service_account.ed-account.id
  node_service_account_id = yandex_iam_service_account.ed-account.id
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller
  ]
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

// создаем сеть
resource "yandex_vpc_network" "ednet" {
  name = "ednet"
}

// создаем подсеть
resource "yandex_vpc_subnet" "edsubnet" {
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = var.zone
  network_id     = yandex_vpc_network.ednet.id
}

// создаем сервис-аккаунт
resource "yandex_iam_service_account" "ed-account" {
  name        = local.sa_name
  description = "K8S zonal service account"
}

// назначаем роли сервис-аккаунту
resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  # Сервисному аккаунту назначается роль "k8s.clusters.agent".
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.ed-account.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  # Сервисному аккаунту назначается роль "vpc.publicAdmin".
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.ed-account.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  # Сервисному аккаунту назначается роль "container-registry.images.puller".
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.ed-account.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "editor" {
  # Сервисному аккаунту назначается роль "editor".
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.ed-account.id}"
}

// создаем kms-key
resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}

resource "yandex_resourcemanager_folder_iam_binding" "storage-admin" {
  # Сервисному аккаунту назначается роль "storage.admin".
  folder_id = var.folder_id
  role      = "storage.admin"
  members   = ["serviceAccount:${yandex_iam_service_account.ed-account.id}"]
}

// создаем security group
resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета. Примените правила только для групп узлов."
  network_id  = yandex_vpc_network.ednet.id
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера Managed Service for Kubernetes и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера Managed Service for Kubernetes и сервисов."
    v4_cidr_blocks = concat(yandex_vpc_subnet.edsubnet.v4_cidr_blocks)
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 6443 из указанной сети."
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }
  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 443 из указанной сети."
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Yandex Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

// создаем группу узлов
resource "yandex_kubernetes_node_group" "node_group_worker" {
  cluster_id = yandex_kubernetes_cluster.k8s-zonal.id
  name       = "worker"
  version    = local.k8s_version
  instance_template {
    platform_id = "standard-v1"
    name        = "worker-{instance.short_id}"
    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.edsubnet.id]
      security_group_ids = [yandex_vpc_security_group.k8s-public-services.id]
    }
    resources {
      memory = 4
      cores  = 2
    }
    boot_disk {
      type = "network-hdd"
      size = 32
    }
    scheduling_policy {
      preemptible = false
    }
  }
  scale_policy {
    auto_scale {
      min     = 1
      max     = 3
      initial = 3
    }
  }
  allocation_policy {
    location {
      zone = var.zone
    }
  }
}

// создаем статический ключ сервис-аккаунта для хранилища S3
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.ed-account.id
  description        = "static access key for object storage"
}

// создаем бакет в хранилище S3 для картинок
resource "yandex_storage_bucket" "edbucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "momo-store-pictures-bucket-ed"
  acl        = "public-read"
}


resource "yandex_storage_object" "image" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  count      = 14
  bucket     = yandex_storage_bucket.edbucket.bucket
  key        = "${count.index + 1}.jpg"
  source     = "images/${count.index + 1}.jpg"
}
