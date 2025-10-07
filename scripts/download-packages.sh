#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="./scripts/package-list.txt"
mkdir -p $DOWNLOAD_DIR

echo "=== Downloading Kubernetes and Dependency Packages ==="

# Определяем версию Ubuntu
UBUNTU_VERSION=$(lsb_release -cs)
echo "📋 Ubuntu version: $UBUNTU_VERSION"

# Базовые URL для пакетов
UBUNTU_URL="http://archive.ubuntu.com/ubuntu"
SECURITY_URL="http://security.ubuntu.com/ubuntu"
DOCKER_URL="https://download.docker.com/linux/ubuntu"
K8S_URL="https://packages.cloud.google.com/apt"

# Функция для скачивания пакета с основных зеркал
download_package_direct() {
    local package=$1
    local version=$2
    echo "📦 Downloading: $package"

    # Пробуем разные источники
    local sources=(
        "$UBUNTU_URL/pool/main/${package:0:1}/$package/${package}_${version}_amd64.deb"
        "$SECURITY_URL/pool/main/${package:0:1}/$package/${package}_${version}_amd64.deb"
        "$UBUNTU_URL/pool/universe/${package:0:1}/$package/${package}_${version}_amd64.deb"
    )

    for source in "${sources[@]}"; do
        if wget -q --timeout=30 --tries=2 "$source" -O "$DOWNLOAD_DIR/${package}_${version}_amd64.deb"; then
            echo "✅ Downloaded: $package"
            return 0
        fi
    done

    echo "❌ Failed to download: $package"
    return 1
}

# Функция для поиска версии пакета
find_package_version() {
    local package=$1
    apt-cache show "$package" 2>/dev/null | grep Version | head -1 | awk '{print $2}' || echo ""
}

# Скачиваем системные пакеты
download_system_packages() {
    echo "📥 Downloading system packages..."

    # Системные пакеты
    SYSTEM_PACKAGES=(
        "curl" "wget" "gnupg2" "software-properties-common" "apt-transport-https"
        "ca-certificates" "bridge-utils" "ntp" "ntpdate"
    )

    for pkg in "${SYSTEM_PACKAGES[@]}"; do
        version=$(find_package_version "$pkg")
        if [ -n "$version" ]; then
            download_package_direct "$pkg" "$version" || true
        else
            echo "⚠️  Cannot find version for: $pkg"
        fi
    done
}

# Скачиваем Docker пакеты
download_docker_packages() {
    echo "📥 Downloading Docker packages..."

    # Добавляем репозиторий Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_URL $UBUNTU_VERSION stable" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get update

    DOCKER_PACKAGES=("docker-ce" "docker-ce-cli" "containerd.io" "docker-buildx-plugin" "docker-compose-plugin")

    for pkg in "${DOCKER_PACKAGES[@]}"; do
        version=$(find_package_version "$pkg")
        if [ -n "$version" ]; then
            # Скачиваем с Docker репозитория
            wget -q "$DOCKER_URL/dists/$UBUNTU_VERSION/pool/stable/amd64/${pkg}_${version}_amd64.deb" -O "$DOWNLOAD_DIR/${pkg}_${version}_amd64.deb" && \
            echo "✅ Downloaded: $pkg" || echo "❌ Failed: $pkg"
        fi
    done
}

# Скачиваем Kubernetes пакеты
download_kubernetes_packages() {
    echo "📥 Downloading Kubernetes packages..."

    # Добавляем репозиторий Kubernetes
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update

    K8S_PACKAGES=("kubelet" "kubeadm" "kubectl" "kubernetes-cni")

    for pkg in "${K8S_PACKAGES[@]}"; do
        version=$(apt-cache madison "$pkg" 2>/dev/null | head -1 | awk '{print $3}')
        if [ -n "$version" ]; then
            # Скачиваем с Google репозитория
            wget -q "https://packages.cloud.google.com/apt/pool/${pkg}_${version}_amd64.deb" -O "$DOWNLOAD_DIR/${pkg}_${version}_amd64.deb" && \
            echo "✅ Downloaded: $pkg" || echo "❌ Failed: $pkg"
        else
            echo "⚠️  Cannot find version for: $pkg"
        fi
    done
}

# Скачиваем дополнительные пакеты
download_extra_packages() {
    echo "📥 Downloading extra packages..."

    EXTRA_PACKAGES=("haproxy" "nginx")

    for pkg in "${EXTRA_PACKAGES[@]}"; do
        version=$(find_package_version "$pkg")
        if [ -n "$version" ]; then
            download_package_direct "$pkg" "$version" || true
        fi
    done
}

# Основной процесс
echo "🔄 Updating package lists..."
sudo apt-get update

# Скачиваем пакеты
download_system_packages
download_docker_packages
download_kubernetes_packages
download_extra_packages

# Альтернативный метод - используем apt-offline
install_apt_offline() {
    echo "🔄 Trying apt-offline method..."
    sudo apt-get install -y apt-offline

    # Генерируем сигнатуру для пакетов
    PACKAGE_LIST=("curl" "wget" "gnupg2" "software-properties-common" "apt-transport-https"
                 "ca-certificates" "bridge-utils" "ntp" "ntpdate" "docker.io" "docker-compose"
                 "haproxy" "nginx" "kubelet" "kubeadm" "kubectl" "kubernetes-cni")

    apt-offline set offline.sig --install-packages "${PACKAGE_LIST[@]}" || true
    echo "📋 Signature generated: offline.sig"
}

# Если скачали мало пакетов, пробуем apt-offline
if [ $(ls -1 "$DOWNLOAD_DIR"/*.deb 2>/dev/null | wc -l) -lt 10 ]; then
    echo "⚠️  Too few packages downloaded, trying alternative method..."
    install_apt_offline
fi

# Создаем файл со списком всех пакетов
echo "📝 Generating package list..."
ls -la $DOWNLOAD_DIR/*.deb 2>/dev/null > $PACKAGE_LIST_FILE || {
    echo "No packages downloaded" > $PACKAGE_LIST_FILE
    echo "❌ No packages were downloaded!"
}

# Создаем индекс для локального репозитория
if [ $(ls -1 "$DOWNLOAD_DIR"/*.deb 2>/dev/null | wc -l) -gt 0 ]; then
    echo "🏗️ Creating local repository index..."
    cd $DOWNLOAD_DIR
    dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz || echo "⚠️  Could not create Packages.gz"
    cd -
    echo "✅ Repository index created"
else
    echo "❌ No packages to index"
fi

echo ""
echo "🎉 Package download completed!"
echo "📁 Packages saved to: $DOWNLOAD_DIR"
echo "📊 Total packages downloaded: $(ls -1 $DOWNLOAD_DIR/*.deb 2>/dev/null | wc -l || echo 0)"