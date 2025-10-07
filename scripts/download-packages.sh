#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="./scripts/package-list.txt"
mkdir -p $DOWNLOAD_DIR

echo "=== Downloading Kubernetes and Dependency Packages ==="

# Список пакетов для загрузки
PACKAGES=(
    # System dependencies
    "curl"
    "wget"
    "gnupg2"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "bridge-utils"
    "ntp"
    "ntpdate"

    # Container runtime
    "containerd.io"

    # HAProxy
    "haproxy"

    # Web server for local repo
    "nginx"

    # Docker for registry
    "docker.io"
    "docker-compose"
)

# Функция для загрузки пакета и его зависимостей
download_package_with_deps() {
    local package=$1
    echo "📦 Downloading package: $package"

    # Создаем временную директорию для зависимостей
    local temp_dir=$(mktemp -d)
    cd $temp_dir

    # Пытаемся скачать пакет и зависимости
    if apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests \
        --no-conflicts --no-breaks --no-replaces --no-enhances \
        $package 2>/dev/null | grep "^\w" | sort -u) 2>/dev/null; then

        # Копируем скачанные пакеты в целевую директорию
        cp *.deb $DOWNLOAD_DIR/ 2>/dev/null || true
        echo "✅ Downloaded: $package"
    else
        echo "⚠️  Skipping $package due to download error"
        # Пробуем скачать только основной пакет
        if apt-get download $package 2>/dev/null; then
            cp *.deb $DOWNLOAD_DIR/ 2>/dev/null || true
            echo "✅ Downloaded (main only): $package"
        fi
    fi

    # Очищаем временную директорию
    cd -
    rm -rf $temp_dir
}

# Функция для скачивания Kubernetes пакетов через официальный репозиторий Google
download_kubernetes_packages() {
    echo "📥 Setting up Kubernetes repository and downloading packages..."

    # Добавляем репозиторий Kubernetes
    echo "🔧 Adding Kubernetes repository..."

    # Скачиваем GPG ключ
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

    # Добавляем репозиторий
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    # Обновляем список пакетов
    sudo apt-get update

    # Скачиваем Kubernetes пакеты
    K8S_PACKAGES=("kubelet" "kubeadm" "kubectl" "kubernetes-cni")

    for pkg in "${K8S_PACKAGES[@]}"; do
        echo "📦 Downloading: $pkg"
        download_package_with_deps "$pkg"
    done
}

# Функция для скачивания пакетов без зависимостей (fallback)
download_packages_direct() {
    echo "🔄 Trying direct package download..."

    # Обновляем список пакетов
    sudo apt-get update

    # Скачиваем каждый пакет отдельно
    ALL_PACKAGES=(
        "curl" "wget" "gnupg2" "software-properties-common" "apt-transport-https"
        "ca-certificates" "bridge-utils" "ntp" "ntpdate" "containerd" "haproxy"
        "nginx" "docker.io" "docker-compose" "kubelet" "kubeadm" "kubectl" "kubernetes-cni"
    )

    for package in "${ALL_PACKAGES[@]}"; do
        echo "📦 Attempting to download: $package"
        if apt-get download "$package" 2>/dev/null; then
            cp *.deb $DOWNLOAD_DIR/ 2>/dev/null || true
            echo "✅ Downloaded: $package"
        else
            echo "⚠️  Failed to download: $package"
        fi
    done
}

# Основной процесс загрузки
echo "🔄 Updating package lists..."
sudo apt-get update || true

# Пробуем скачать Kubernetes пакеты через официальный репозиторий
if download_kubernetes_packages; then
    echo "✅ Kubernetes packages downloaded via official repo"
else
    echo "❌ Failed to download Kubernetes via official repo, trying fallback..."
    download_packages_direct
fi

# Загружаем остальные системные пакеты
for package in "${PACKAGES[@]}"; do
    # Пропускаем если уже скачали с Kubernetes
    if [[ " kubelet kubeadm kubectl kubernetes-cni " != *" $package "* ]]; then
        download_package_with_deps "$package"
    fi
done

# Проверяем что скачали containerd
if ! ls $DOWNLOAD_DIR/*containerd* > /dev/null 2>&1; then
    echo "⚠️  containerd not found, trying to download separately..."
    download_package_with_deps "containerd"
fi

# Создаем файл со списком всех пакетов
echo "📝 Generating package list..."
ls -la $DOWNLOAD_DIR/*.deb 2>/dev/null > $PACKAGE_LIST_FILE || {
    echo "No packages downloaded" > $PACKAGE_LIST_FILE
    echo "❌ No packages were downloaded!"
    exit 1
}

# Создаем индекс для локального репозитория
echo "🏗️ Creating local repository index..."
cd $DOWNLOAD_DIR
if ls *.deb > /dev/null 2>&1; then
    dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz || echo "⚠️  Could not create Packages.gz"
    echo "✅ Repository index created"
else
    echo "❌ No packages to index"
    exit 1
fi
cd -

echo ""
echo "🎉 Package download completed!"
echo "📁 Packages saved to: $DOWNLOAD_DIR"
echo "📊 Total packages downloaded: $(ls -1 $DOWNLOAD_DIR/*.deb 2>/dev/null | wc -l || echo 0)"

# Проверяем критические пакеты
echo ""
echo "🔍 Critical package check:"
CRITICAL_PACKAGES=("kubelet" "kubeadm" "kubectl" "containerd")
MISSING_COUNT=0

for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if ls $DOWNLOAD_DIR/*${pkg}* > /dev/null 2>&1; then
        echo "✅ $pkg - FOUND"
    else
        echo "❌ $pkg - MISSING"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ $MISSING_COUNT -gt 0 ]; then
    echo ""
    echo "❌ Missing $MISSING_COUNT critical packages!"
    echo "Please check your internet connection and repository configuration."
    exit 1
else
    echo ""
    echo "✅ All critical packages downloaded successfully!"
fi