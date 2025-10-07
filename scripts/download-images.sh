#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="./scripts/package-list.txt"

# Создаем директорию
mkdir -p "$DOWNLOAD_DIR"

# Выбираем версию Kubernetes
K8S_VERSION="1.32.3"
echo "=== Downloading Kubernetes $K8S_VERSION and Dependency Packages for Ubuntu 22.04 ==="

# Определяем версию Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_VERSION=$VERSION_CODENAME
    UBUNTU_VERSION_ID=$VERSION_ID
else
    UBUNTU_VERSION=$(lsb_release -cs)
    UBUNTU_VERSION_ID=$(lsb_release -rs)
fi
echo "📋 Ubuntu version: $UBUNTU_VERSION ($UBUNTU_VERSION_ID)"
echo "📋 Kubernetes version: $K8S_VERSION"

K8S_MAJOR_MINOR=$(echo $K8S_VERSION | cut -d. -f1-2)

# Полный список всех необходимых пакетов
ALL_PACKAGES=(
    # System utilities
    "curl"
    "wget"
    "gnupg"
    "gnupg2"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "bridge-utils"
    "ntp"
    "ntpdate"

    # Container runtime
    "containerd"
    "containerd.io"

    # Docker
    "docker.io"

    # Kubernetes
    "kubelet"
    "kubeadm"
    "kubectl"
    "kubernetes-cni"

    # Networking
    "haproxy"
    "nginx"
)

# Функция для добавления репозиториев
add_repositories() {
    echo "🔧 Adding required repositories..."

    # Docker repository
    if ! grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
        echo "📥 Adding Docker repository..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_VERSION stable" | sudo tee /etc/apt/sources.list.d/docker.list
    fi

    # Kubernetes repository
    if ! grep -q "pkgs.k8s.io" /etc/apt/sources.list.d/kubernetes.list 2>/dev/null; then
        echo "📥 Adding Kubernetes repository for version $K8S_VERSION..."
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi

    # Обновляем списки пакетов
    echo "🔄 Updating package lists..."
    sudo apt-get update
}

# Метод 1: Простое скачивание пакетов БЕЗ временных директорий
download_packages_simple() {
    echo "📦 Method 1: Simple package download..."

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "📥 Downloading: $pkg"

            # Скачиваем пакет напрямую в целевую директорию
            if apt-get download "$pkg" -o Dir::Cache::archives="$DOWNLOAD_DIR" 2>/dev/null; then
                echo "✅ Downloaded: $pkg"
            else
                echo "⚠️  Failed to download: $pkg"
            fi
        fi
    done
}

# Метод 2: Прямое скачивание Kubernetes пакетов
download_kubernetes_direct() {
    echo "📦 Method 2: Direct Kubernetes package download..."

    K8S_PACKAGES=(
        "kubelet"
        "kubeadm"
        "kubectl"
    )

    for pkg in "${K8S_PACKAGES[@]}"; do
        filename="${pkg}_${K8S_VERSION}-1.1_amd64.deb"
        url="https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/amd64/${filename}"

        echo "📥 Downloading: $pkg"
        if wget -q --timeout=30 --tries=3 "$url" -O "$DOWNLOAD_DIR/$filename"; then
            echo "✅ Downloaded: $pkg"
        else
            echo "❌ Failed: $pkg"
        fi
    done

    # CNI plugins
    CNI_VERSION="1.4.0"
    CNI_PACKAGE="kubernetes-cni_${CNI_VERSION}-0.0~amd64.deb"
    CNI_URL="https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/amd64/${CNI_PACKAGE}"

    echo "📥 Downloading: kubernetes-cni"
    if wget -q --timeout=30 "$CNI_URL" -O "$DOWNLOAD_DIR/$CNI_PACKAGE"; then
        echo "✅ Downloaded: kubernetes-cni"
    else
        echo "⚠️  Failed to download CNI plugins"
    fi
}

# Метод 3: Скачивание основных системных пакетов
download_core_packages() {
    echo "📦 Method 3: Downloading core system packages..."

    # Основные пакеты с прямыми ссылками
    declare -A CORE_PACKAGES=(
        ["curl"]="http://archive.ubuntu.com/ubuntu/pool/main/c/curl/curl_7.81.0-1ubuntu1.15_amd64.deb"
        ["wget"]="http://archive.ubuntu.com/ubuntu/pool/main/w/wget/wget_1.21.2-2ubuntu1_amd64.deb"
        ["gnupg2"]="http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gnupg2_2.2.27-3ubuntu2.1_amd64.deb"
        ["software-properties-common"]="http://archive.ubuntu.com/ubuntu/pool/main/s/software-properties/software-properties-common_0.99.22.7_amd64.deb"
        ["apt-transport-https"]="http://archive.ubuntu.com/ubuntu/pool/main/a/apt/apt-transport-https_2.4.9_amd64.deb"
        ["ca-certificates"]="http://archive.ubuntu.com/ubuntu/pool/main/c/ca-certificates/ca-certificates_20211016ubuntu0.22.04.1_all.deb"
        ["bridge-utils"]="http://archive.ubuntu.com/ubuntu/pool/main/b/bridge-utils/bridge-utils_1.7-1ubuntu1_amd64.deb"
        ["containerd"]="http://archive.ubuntu.com/ubuntu/pool/universe/c/containerd/containerd_1.6.12-0ubuntu1_amd64.deb"
        ["docker.io"]="http://archive.ubuntu.com/ubuntu/pool/universe/d/docker.io/docker.io_20.10.21-0ubuntu1_amd64.deb"
        ["haproxy"]="http://archive.ubuntu.com/ubuntu/pool/main/h/haproxy/haproxy_2.4.13-1ubuntu1_amd64.deb"
        ["nginx"]="http://archive.ubuntu.com/ubuntu/pool/main/n/nginx/nginx_1.18.0-6ubuntu14.4_amd64.deb"
    )

    for pkg in "${!CORE_PACKAGES[@]}"; do
        url="${CORE_PACKAGES[$pkg]}"
        filename=$(basename "$url")

        # Проверяем, не скачан ли уже пакет
        if ! ls "$DOWNLOAD_DIR"/*"$pkg"* > /dev/null 2>&1; then
            echo "📥 Downloading: $pkg"
            if wget -q --timeout=30 --tries=3 "$url" -O "$DOWNLOAD_DIR/$filename"; then
                echo "✅ Downloaded: $pkg"
            else
                echo "❌ Failed: $pkg"
            fi
        fi
    done
}

# Метод 4: Альтернативный метод скачивания
download_packages_alternative() {
    echo "📦 Method 4: Alternative download method..."

    # Переходим в целевую директорию и скачиваем там
    cd "$DOWNLOAD_DIR"

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "📥 Downloading: $pkg"
            if apt-get download "$pkg" 2>/dev/null; then
                echo "✅ Downloaded: $pkg"
            else
                echo "⚠️  Failed to download: $pkg"
            fi
        fi
    done

    # Возвращаемся назад
    cd - > /dev/null
}

# Основной процесс
echo "🔄 Setting up for Kubernetes $K8S_VERSION on Ubuntu 22.04..."

sudo apt-get update
add_repositories

# Пробуем методы по порядку
download_packages_simple
download_kubernetes_direct
download_core_packages
download_packages_alternative

# Создаем индекс репозитория
echo "🏗️ Creating local repository..."
cd "$DOWNLOAD_DIR"
if ls *.deb > /dev/null 2>&1; then
    dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
    echo "✅ Repository index created"
else
    echo "❌ No packages to index"
fi

# Генерируем список пакетов
ls -la *.deb > "$PACKAGE_LIST_FILE" 2>/dev/null || echo "No packages downloaded" > "$PACKAGE_LIST_FILE"

# Проверяем результаты
echo ""
echo "📊 Download Summary:"
PACKAGE_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l || echo 0)
echo "📁 Packages downloaded: $PACKAGE_COUNT"
echo "📋 Package list: $PACKAGE_LIST_FILE"

# Проверяем критические пакеты
echo ""
echo "🔍 Critical package check:"
CRITICAL_PACKAGES=("kubelet" "kubeadm" "kubectl" "containerd" "docker.io")
MISSING_COUNT=0

for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if ls *"$pkg"* > /dev/null 2>&1; then
        echo "✅ $pkg - FOUND"
    else
        echo "❌ $pkg - MISSING"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ $MISSING_COUNT -eq 0 ]; then
    echo ""
    echo "🎉 All critical packages downloaded successfully!"
    echo "🚀 Ready for offline installation!"
else
    echo ""
    echo "⚠️  Missing $MISSING_COUNT critical packages"
    echo "Some packages may need to be downloaded manually"
fi