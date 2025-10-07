#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="./scripts/package-list.txt"
mkdir -p $DOWNLOAD_DIR

echo "=== Downloading Kubernetes and Dependency Packages ==="

# Список пакетов для загрузки (только из стабильных репозиториев)
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

    # Kubernetes (будем скачивать вручную с официального сайта)
    # "kubelet"
    # "kubeadm"
    # "kubectl"
    # "kubernetes-cni"

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

    # Пытаемся скачать пакет и зависимости, игнорируем ошибки
    if apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests \
        --no-conflicts --no-breaks --no-replaces --no-enhances \
        $package 2>/dev/null | grep "^\w" | sort -u) 2>/dev/null; then

        # Копируем скачанные пакеты в целевую директорию
        cp *.deb $DOWNLOAD_DIR/ 2>/dev/null || true
        echo "✅ Downloaded: $package"
    else
        echo "⚠️  Skipping $package due to download error"
    fi

    # Очищаем временную директорию
    cd -
    rm -rf $temp_dir
}

# Функция для скачивания Kubernetes пакетов вручную
download_kubernetes_packages() {
    echo "📥 Downloading Kubernetes packages manually..."

    K8S_VERSION="1.34.0"
    K8S_DEB_URL="https://pkgs.k8s.io/core:/stable:/v1.34/deb"

    K8S_PACKAGES=(
        "kubelet_${K8S_VERSION}-1.1_amd64.deb"
        "kubeadm_${K8S_VERSION}-1.1_amd64.deb"
        "kubectl_${K8S_VERSION}-1.1_amd64.deb"
    )

    for pkg in "${K8S_PACKAGES[@]}"; do
        echo "📦 Downloading: $pkg"
        if wget -q "${K8S_DEB_URL}/Pool/${pkg}" -O "$DOWNLOAD_DIR/${pkg}"; then
            echo "✅ Downloaded: $pkg"
        else
            echo "❌ Failed to download: $pkg"
            # Попробуем альтернативный URL
            ALT_URL="https://storage.googleapis.com/k8s-release/release/v${K8S_VERSION}/bin/linux/amd64/${pkg}"
            if wget -q "$ALT_URL" -O "$DOWNLOAD_DIR/${pkg}"; then
                echo "✅ Downloaded from alternative URL: $pkg"
            else
                echo "❌ Failed to download from alternative URL: $pkg"
            fi
        fi
    done

    # Скачиваем CNI плагины
    CNI_VERSION="1.4.0"
    CNI_PACKAGE="kubernetes-cni_${CNI_VERSION}-0.0~amd64.deb"
    echo "📦 Downloading: $CNI_PACKAGE"
    wget -q "https://pkgs.k8s.io/core:/stable:/v1.34/deb/Pool/${CNI_PACKAGE}" -O "$DOWNLOAD_DIR/${CNI_PACKAGE}" || \
    wget -q "https://storage.googleapis.com/k8s-release/network-plugins/${CNI_PACKAGE}" -O "$DOWNLOAD_DIR/${CNI_PACKAGE}" || \
    echo "⚠️  Failed to download CNI plugins"
}

# Обновляем список пакетов (игнорируем ошибки репозиториев)
echo "🔄 Updating package lists (ignoring repository errors)..."
apt-get update || true

# Загружаем системные пакеты
for package in "${PACKAGES[@]}"; do
    download_package_with_deps $package
done

# Загружаем Kubernetes пакеты
download_kubernetes_packages

# Создаем файл со списком всех пакетов
echo "📝 Generating package list..."
ls -la $DOWNLOAD_DIR/*.deb > $PACKAGE_LIST_FILE 2>/dev/null || true

# Создаем индекс для локального репозитория
echo "🏗️ Creating local repository index..."
cd $DOWNLOAD_DIR
dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz || echo "⚠️  Could not create Packages.gz"
cd -

echo ""
echo "🎉 Package download completed!"
echo "📁 Packages saved to: $DOWNLOAD_DIR"
echo "📊 Total packages downloaded: $(ls -1 $DOWNLOAD_DIR/*.deb 2>/dev/null | wc -l || echo 0)"
echo ""
echo "To set up local repository, run:"
echo "  sudo dpkg -i $DOWNLOAD_DIR/*.deb"