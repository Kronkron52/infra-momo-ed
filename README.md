# Репозиторий инфраструктуры <!-- omit in toc -->

В данном репозитории хранится инфраструктурная часть проекта "Пельменная".

[Momo Store](https://gitlab.praktikum-services.ru/std-021-009/ed-momo-store)

# Оглавление <!-- omit in toc -->

- [Cтруктура репозитория](#cтруктура-репозитория)
- [Подготовка инфраструктуры](#подготовка-инфраструктуры)
- [Создание кластера в Yandex Cloud](#cоздание-кластера-в-Yandex-Cloud)
- [Кластер и хранилище](#кластер-и-хранилище)
- [Подготовка кластера](#подготовка-кластера)
- [Установка ArgoCD](#установка-argocd)
- [Правила версионирования](#правила-версионирования)
- [Правила внесения изменений в репозиторий](#правила-внесения-изменений-в-репозиторий)


# Cтруктура репозитория

```
.
├── config-kubectl           - kubeconfig для подключения к кластеру
├── k8s                      - Компоненты инфраструктуры
│   ├── argocd               - Декларативный GitOps-инструмент непрерывной доставки
|   ├── helm                 - Чарты и манифесты для momo-store
│   ├── acme-issuer.yaml     - Для получения сертификата в Let's Encrypt
│   └── service-account.yaml - Сервисный аккаунт с которого будем работать
├── terraform                - Манифесты IaC (также папка с картинками, которые загружаются в S3 при развертывании)
└── README.md
```

# Подготовка инфраструктуры

## Кластер и хранилище

Подключаемся к Yandex Cloud
1. Создадим сервистный аккаунт
https://cloud.yandex.ru/ru/docs/iam/quickstart-sa#create-sa

2. Создадим авторизованный ключ для сервисного аккаунта и запишем его файл:

```bash
yc iam key create \
  --service-account-id <идентификатор_сервисного_аккаунта> \
  --folder-name <имя_каталога_с_сервисным_аккаунтом> \
  --output key.json
```
Где:

  - service-account-id — идентификатор сервисного аккаунта.
  - folder-name — имя каталога, в котором создан сервисный аккаунт.
  - output — имя файла с авторизованным ключом.


Пример результата:

```bash
id: aje8nn871qo4a8bbopvb
service_account_id: ajehr0to1g8bh0la8c8r
created_at: "2022-09-14T09:11:43.479156798Z"
key_algorithm: RSA_2048
```

3. Создаем профиль CLI для выполнения операций от имени сервисного аккаунта. Укажите имя профиля:

```bash
yc config profile create my-robot-profile
```

Результат:

```bash
Profile 'my-robot-profile' created and activated
```

Где:
  - service-account-key — файл с авторизованным ключом сервисного аккаунта.
  - cloud-id — идентификатор облака.
  - folder-id — идентификатор каталога.

4. Добавим для профиля CLI cloud и folder
yc config set cloud-id xxxxxx
yc config set folder-id xxxxxx
yc config set service-account-key key.json

5. Добавьте аутентификационные данные в переменные окружения:

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
```

Где:

  - YC_TOKEN — IAM-токен.
  - YC_CLOUD_ID — идентификатор облака.
  - YC_FOLDER_ID — идентификатор каталога.


## Создание кластера в Yandex Cloud

Создавать K8s кластер будем при помощи Terraform. Terraform позволяет быстро создать облачную инфраструктуру в Yandex Cloud и управлять ею с помощью файлов конфигураций. 

Предварительно создадим ACCESS_KEY_ID и SECRET_ACCESS_KEY для подключения backend terraform к S3 хранилищу для сохранения состония работы terraform

```bash
export AWS_ACCESS_KEY_ID="<идентификатор_ключа>"
export AWS_SECRET_ACCESS_KEY="<секретный_ключ>"
```

## После чего развернем кластер

```bash
cd terraform
terraform apply
```

## Настройка доступа подключения к K8s

## Получаем ID кластера. 

## Командой yc managed-kubernetes cluster list в поле ID

```bash
yc managed-kubernetes cluster list
yc managed-kubernetes cluster get-credentials --id Идентификатор_кластера --external
```

## Проверка доступности кластера

```bash
kubectl cluster-info
```

## Делаем бэкап текущего ./kube/config

```bash
cp ~/.kube/config ~/.kube/config.bak
```

## Создаем манифест service-account.yaml

```bash
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
---
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: admin-user-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: "admin-user"
```

## И применяем его

```bash
kubectl apply -f service-account.yaml
```

## Подготовим токен объекта ServiceAccount

```bash
SA_TOKEN=$(kubectl -n kube-system get secret $(kubectl -n kube-system get secret | grep admin-user-token | awk '{print $1}') -o json | jq -r .data.token | base64 --d)
```

## Получите IP-адрес кластера
```bash
MASTER_ENDPOINT=$(yc managed-kubernetes cluster get --id $CLUSTER_ID \
  --format json | \
  jq -r .master.endpoints.external_v4_endpoint)
```
## Дополним файл конфигурации
```bash
kubectl config set-cluster sa-test2 \
  --certificate-authority-data=$var_crt_k8s \
  --server=$MASTER_ENDPOINT \
  --kubeconfig=config
```
## Добавим информацию о токене для admin-user в файл конфигурации
```bash
kubectl config set-credentials admin-user \
  --token=$SA_TOKEN \
  --kubeconfig=config
```

## Добавим информацию о контексте в файл конфигурации
```bash
kubectl config set-context default \
  --cluster=sa-test2 \
  --user=admin-user \
  --kubeconfig=config
```
## Сделайем замену параметров как в приведенном ниже конфиге.

certificate-authority замените на certificate-authority-data

current-context: "" замените на current-context: "default"
```bash
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM1ekNDQWMrZ*******************************
    server: https://51.250.92.135
  name: sa-test2
contexts:
- context:
    cluster: sa-test2
    user: admin-user
  name: default
current-context: "default"
kind: Config
preferences: {}
users:
- name: admin-user
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI6InU1ZjdMd1VpRTVsZmFNMVloWVJYRH**********************************************
```
Далее этот config может быть помещён на машине с установленным kubectl в папку .kube и уже можно работать с kubernetes кластером без использования yc. 

## Устанавливаем NGINX Ingress Controller и менеджер пакетов Kubernetes Helm.
Для установки Helm-чарта с Ingress-контроллером NGINX выполните команду:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && \
helm repo update && \
helm install ingress-nginx ingress-nginx/ingress-nginx
```
## Настройте DNS-запись для Ingress-контроллера
Узнайте IP-адрес Ingress-контроллера (значение в колонке EXTERNAL-IP):
После установки ingress-nginx-Controller, необходимо получить публичный IP адрес Ingress контроллера и создать A запись в DNS.

```bash
kubectl get svc | grep ingress
```
## Результат:

```bash
NAME                                      TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)                      AGE
ingress-nginx-controller                  LoadBalancer   10.96.255.56    158.160.122.131   80:30223/TCP,443:32637/TCP   3d7h
```

## Устанавливаем менеджер сертификатов:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.1/cert-manager.yaml
```

## Также нужно создайть манифест acme-issuer.yaml

```bash
kubectl apply -f acme-issuer.yaml
```
В поле mail вводим валидный адрес электронной почты. 

## Создадим публичную DNS запись для доступа к магазину из интернета

Для этого воспользуемся бесплатным ресурсом https://freedns.afraid.org
Регистрация на нем бесплатная, создаем DNS запись, основываясь инструкцией на сайте.
Указываем IP-адрес из предыдущего пункта и сохраним этот субдомен в качестве переменной MOMO_URL в Gitlab в настройках CI/CD


## Установка ArgoCD

Доступ к ArgoCD можно получить сделав kubectl port-forward svc/argocd-server -n argocd 8080:443, сервис не выставлен наружу для большей безопасности, можно задеплоить ingress в папке argocd, тогда доступ появится
```bash
cd kubernetes-system/argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -n argocd -f ingress.yml
kubectl apply -n argocd -f app.yaml ## реализация методологии GitOps, argo смотрит на k8s/helm 
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' #наружу
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "ClusterIP"}}'    #локально
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

# Правила версионирования

Версия приложения формируется из переменной `VERSION` в пайплайне - `1.0.${CI_PIPELINE_ID}`

Контейнеры фронтенда и бэкенда собираются и публикуются в отдельных пайплайнах, при сборке каждый образ получает тег с номером версии приложения. После тестирования образа на успешный запуск и отработку запросов (Postman), образ тегируется как latest.

Образы публикуются в GitLab Container Registry.

# Правила внесения изменений в репозиторий

Все изменения должны производиться в отдельном бранче с последующим MR.

## Мониторинг, логирование и дашборд
В будущем