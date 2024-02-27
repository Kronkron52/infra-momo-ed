# Провайдер это инструмент, который превращает наши terraform файлы (.tf кстати) в инструкции для конкретного облачного сервиса. 
#Для инициализации провайдера может понадобится VPN.

provider "yandex" {
  service_account_key_file = pathexpand(var.service_account_key_file)
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone
}
