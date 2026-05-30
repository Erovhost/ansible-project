terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  service_account_key_file = var.service_account_key_file
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone
}

# Сеть
resource "yandex_vpc_network" "network" {
  name = "app-network"
}

# Подсеть
resource "yandex_vpc_subnet" "subnet" {
  name           = "app-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

# Веб-сервер 1
resource "yandex_compute_instance" "web1" {
  name = "web-1"
  zone = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key_path)}"
  }
}

# Веб-сервер 2
resource "yandex_compute_instance" "web2" {
  name = "web-2"
  zone = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key_path)}"
  }
}

# База данных
resource "yandex_mdb_postgresql_cluster" "db" {
  name        = "app-db"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.network.id

  config {
    version = 15
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10
    }
  }

  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.subnet.id
  }
}

resource "yandex_mdb_postgresql_database" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.db.id
  name       = "redmine"
  owner      = "redmine"
}

resource "yandex_mdb_postgresql_user" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.db.id
  name       = "redmine"
  password   = "redminepassword"
}

# Балансировщик нагрузки
resource "yandex_lb_network_load_balancer" "lb" {
  name = "app-lb"

  listener {
    name        = "app-listener"
    port        = 80
    target_port = 80
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.tg.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "yandex_lb_target_group" "tg" {
  name = "app-tg"

  target {
    subnet_id = yandex_vpc_subnet.subnet.id
    address   = yandex_compute_instance.web1.network_interface[0].ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet.id
    address   = yandex_compute_instance.web2.network_interface[0].ip_address
  }
}