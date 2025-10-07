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
    "containerd"

    # Kubernetes
    "kubelet"
    "kubeadm"
    "kubectl"
    "kubernetes-cni"

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

    # Загружаем пакет и все зависимости
    apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests \
        --no-conflicts --no-breaks --no-replaces --no-enhances \
        $package | grep "^\w" | sort -u)

    # Копируем скачанные пакеты в целевую директорию
    cp *.deb $DOWNLOAD_DIR/ 2>/dev/null || true

    # Очищаем временную директорию
    cd -
    rm -rf $temp_dir

    echo "✅ Downloaded: $package"
}

# Обновляем список пакетов
echo "🔄 Updating package lists..."
sudo apt-get update

# Загружаем все пакеты
for package in "${PACKAGES[@]}"; do
    download_package_with_deps $package
done

# Создаем файл со списком всех пакетов
echo "📝 Generating package list..."
ls -la $DOWNLOAD_DIR/*.deb > $PACKAGE_LIST_FILE 2>/dev/null || true

# Создаем индекс для локального репозитория
echo "🏗️ Creating local repository index..."
cd $DOWNLOAD_DIR
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
cd -

echo ""
echo "🎉 Package download completed!"
echo "📁 Packages saved to: $DOWNLOAD_DIR"
echo "📊 Total packages downloaded: $(ls -1 $DOWNLOAD_DIR/*.deb 2>/dev/null | wc -l || echo 0)"
echo ""
echo "To set up local repository, run:"
echo "  sudo dpkg -i $DOWNLOAD_DIR/*.deb"