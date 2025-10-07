#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="$DOWNLOAD_DIR/package-list.txt"

# Создаем необходимые директории
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

# Критически важные пакеты
CRITICAL_PACKAGES=("kubelet" "kubeadm" "kubectl" "containerd" "docker.io" "kubernetes-cni")

# Все пакеты
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

# Функция проверки скачанных пакетов
check_downloaded_packages() {
    local missing_packages=()

    for pkg in "${CRITICAL_PACKAGES[@]}"; do
        if ! ls "$DOWNLOAD_DIR"/*"$pkg"* > /dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    echo "${missing_packages[@]}"
}

# Метод 1: Основной метод через apt-get download
download_with_apt_get() {
    echo "📦 Method 1: Using apt-get download (primary method)..."

    local downloaded_count=0

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "📥 Downloading: $pkg"

            # Скачиваем пакет напрямую в целевую директорию
            if apt-get download "$pkg" -o Dir::Cache::archives="$DOWNLOAD_DIR" 2>/dev/null; then
                echo "✅ Downloaded: $pkg"
                downloaded_count=$((downloaded_count + 1))
            else
                echo "⚠️  Failed to download: $pkg"
            fi
        else
            echo "⚠️  Package not found in repository: $pkg"
        fi
    done

    echo "📊 Apt-get method: $downloaded_count packages downloaded"
    # Не возвращаем код выхода, чтобы скрипт не прерывался
}

# Метод 2: Альтернативный метод - скачиваем в целевой директории
download_in_target_dir() {
    echo "📦 Method 2: Downloading in target directory (alternative method)..."

    local original_dir=$(pwd)
    cd "$DOWNLOAD_DIR"

    local downloaded_count=0

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "📥 Downloading: $pkg"
            if apt-get download "$pkg" 2>/dev/null; then
                echo "✅ Downloaded: $pkg"
                downloaded_count=$((downloaded_count + 1))
            fi
        fi
    done

    cd "$original_dir"
    echo "📊 Target directory method: $downloaded_count packages downloaded"
}

# Метод 3: Прямое скачивание Kubernetes пакетов
download_kubernetes_direct() {
    echo "📦 Method 3: Direct download of Kubernetes packages..."

    local downloaded_count=0

    K8S_PACKAGES=(
        "kubelet"
        "kubeadm"
        "kubectl"
    )

    for pkg in "${K8S_PACKAGES[@]}"; do
        filename="${pkg}_${K8S_VERSION}-1.1_amd64.deb"
        url="https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/amd64/${filename}"

        # Проверяем, не скачан ли уже пакет
        if ! ls "$DOWNLOAD_DIR"/*"$pkg"* > /dev/null 2>&1; then
            echo "📥 Downloading: $pkg"
            if wget -q --timeout=30 --tries=3 "$url" -O "$DOWNLOAD_DIR/$filename"; then
                echo "✅ Downloaded: $pkg"
                downloaded_count=$((downloaded_count + 1))
            else
                echo "❌ Failed: $pkg"
            fi
        fi
    done

    # CNI plugins
    CNI_VERSION="1.4.0"
    CNI_PACKAGE="kubernetes-cni_${CNI_VERSION}-0.0~amd64.deb"
    CNI_URL="https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/amd64/${CNI_PACKAGE}"

    if ! ls "$DOWNLOAD_DIR"/*"kubernetes-cni"* > /dev/null 2>&1; then
        echo "📥 Downloading: kubernetes-cni"
        if wget -q --timeout=30 "$CNI_URL" -O "$DOWNLOAD_DIR/$CNI_PACKAGE"; then
            echo "✅ Downloaded: kubernetes-cni"
            downloaded_count=$((downloaded_count + 1))
        else
            echo "⚠️  Failed to download CNI plugins"
        fi
    fi

    echo "📊 Direct Kubernetes method: $downloaded_count packages downloaded"
}

# Метод 4: Скачивание основных системных пакетов по прямым ссылкам
download_core_packages_direct() {
    echo "📦 Method 4: Direct download of core system packages..."

    local downloaded_count=0

    # Основные пакеты с прямыми ссылками
    declare -A CORE_PACKAGES=(
        ["containerd"]="http://archive.ubuntu.com/ubuntu/pool/universe/c/containerd/containerd_1.6.12-0ubuntu1_amd64.deb"
        ["docker.io"]="http://archive.ubuntu.com/ubuntu/pool/universe/d/docker.io/docker.io_20.10.21-0ubuntu1_amd64.deb"
        ["haproxy"]="http://archive.ubuntu.com/ubuntu/pool/main/h/haproxy/haproxy_2.4.13-1ubuntu1_amd64.deb"
    )

    for pkg in "${!CORE_PACKAGES[@]}"; do
        # Скачиваем только если пакет еще не скачан и он критически важен
        if ! ls "$DOWNLOAD_DIR"/*"$pkg"* > /dev/null 2>&1; then
            url="${CORE_PACKAGES[$pkg]}"
            filename=$(basename "$url")

            echo "📥 Downloading: $pkg"
            if wget -q --timeout=30 --tries=3 "$url" -O "$DOWNLOAD_DIR/$filename"; then
                echo "✅ Downloaded: $pkg"
                downloaded_count=$((downloaded_count + 1))
            else
                echo "❌ Failed: $pkg"
            fi
        fi
    done

    echo "📊 Direct core packages method: $downloaded_count packages downloaded"
}

# Основной процесс
echo "🔄 Setting up for Kubernetes $K8S_VERSION on Ubuntu 22.04..."

sudo apt-get update
add_repositories

# Шаг 1: Пробуем основной метод
echo ""
echo "🚀 Step 1: Trying primary download method..."
download_with_apt_get

# Проверяем что скачалось
missing_packages=$(check_downloaded_packages)
if [ -z "$missing_packages" ]; then
    echo "🎉 Primary method successful! All critical packages downloaded."
else
    echo "⚠️  Primary method incomplete. Missing: $missing_packages"

    # Шаг 2: Пробуем альтернативный метод apt-get
    echo ""
    echo "🚀 Step 2: Trying alternative apt-get method..."
    download_in_target_dir

    # Проверяем снова
    missing_packages=$(check_downloaded_packages)
    if [ -z "$missing_packages" ]; then
        echo "🎉 Alternative method successful! All critical packages downloaded."
    else
        echo "⚠️  Still missing: $missing_packages"

        # Шаг 3: Пробуем прямые ссылки для Kubernetes
        echo ""
        echo "🚀 Step 3: Trying direct Kubernetes download..."
        download_kubernetes_direct

        # Проверяем снова
        missing_packages=$(check_downloaded_packages)
        if [ -z "$missing_packages" ]; then
            echo "🎉 Kubernetes packages downloaded successfully!"
        else
            echo "⚠️  Still missing: $missing_packages"

            # Шаг 4: Пробуем прямые ссылки для системных пакетов
            echo ""
            echo "🚀 Step 4: Trying direct system packages download..."
            download_core_packages_direct
        fi
    fi
fi

# Создаем индекс репозитория
echo ""
echo "🏗️ Creating local repository..."
cd "$DOWNLOAD_DIR"
if ls *.deb > /dev/null 2>&1; then
    dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz
    echo "✅ Repository index created"

    # Создаем список пакетов
    ls -la *.deb > "$PACKAGE_LIST_FILE" 2>/dev/null || echo "No package list generated" > "$PACKAGE_LIST_FILE"
else
    echo "❌ No packages to index"
    echo "No packages downloaded" > "$PACKAGE_LIST_FILE"
fi

# Финальная проверка и отчет
echo ""
echo "🔍 Final package check:"
final_missing=$(check_downloaded_packages)
PACKAGE_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l || echo 0)

if [ -z "$final_missing" ]; then
    echo "🎉 SUCCESS: All critical packages downloaded!"
    echo "📊 Total packages: $PACKAGE_COUNT"
else
    echo "❌ MISSING: $final_missing"
    echo "📊 Total packages downloaded: $PACKAGE_COUNT"

    if [ $PACKAGE_COUNT -gt 0 ]; then
        echo "⚠️  But we have $PACKAGE_COUNT packages, continuing..."
    else
        echo "❌ No packages were downloaded!"
        exit 1
    fi
fi

echo ""
echo "🚀 Package download process completed!"
exit 0