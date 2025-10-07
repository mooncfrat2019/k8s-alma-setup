#!/bin/bash
set -e

echo "=== Manual Kubernetes Package Download ==="

DOWNLOAD_DIR="./files/packages"
mkdir -p $DOWNLOAD_DIR

K8S_VERSION="1.34.0"
BASE_URL="https://pkgs.k8s.io/core:/stable:/v1.34/deb"

# Список пакетов Kubernetes
PACKAGES=(
    "kubelet_${K8S_VERSION}-1.1_amd64.deb"
    "kubeadm_${K8S_VERSION}-1.1_amd64.deb"
    "kubectl_${K8S_VERSION}-1.1_amd64.deb"
    "kubernetes-cni_1.4.0-0.0~amd64.deb"
)

# Альтернативные URL на случай проблем
ALT_URLS=(
    "https://storage.googleapis.com/k8s-release/release/v${K8S_VERSION}/bin/linux/amd64"
    "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64"
)

download_package() {
    local package=$1
    local main_url="${BASE_URL}/Pool/${package}"

    echo "📦 Downloading: $package"

    # Пробуем основной URL
    if wget -q --timeout=30 "$main_url" -O "$DOWNLOAD_DIR/${package}"; then
        echo "✅ Downloaded from main URL"
        return 0
    fi

    # Пробуем альтернативные URL
    for alt_url in "${ALT_URLS[@]}"; do
        if wget -q --timeout=30 "${alt_url}/${package}" -O "$DOWNLOAD_DIR/${package}"; then
            echo "✅ Downloaded from alternative URL"
            return 0
        fi
    done

    echo "❌ Failed to download: $package"
    return 1
}

# Скачиваем все пакеты
for package in "${PACKAGES[@]}"; do
    download_package "$package"
done

echo ""
echo "🎉 Manual download completed!"
echo "📁 Packages saved to: $DOWNLOAD_DIR"