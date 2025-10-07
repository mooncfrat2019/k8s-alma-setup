#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/packages"
PACKAGE_LIST_FILE="./scripts/package-list.txt"
mkdir -p $DOWNLOAD_DIR

# Выбираем версию Kubernetes (можно изменить на 1.33.0 если нужно)
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
    "systemd"
    "dbus"
    "libseccomp2"
    "conntrack"
    "socat"
    "ebtables"
    "ethtool"
    "ipset"
    "iptables"
    "ipvsadm"

    # Container runtime
    "containerd"
    "containerd.io"
    "runc"
    "cri-tools"

    # Docker
    "docker.io"
    "docker-ce"
    "docker-ce-cli"
    "docker-buildx-plugin"
    "docker-compose-plugin"

    # Kubernetes
    "kubelet"
    "kubeadm"
    "kubectl"
    "kubernetes-cni"

    # Networking
    "haproxy"
    "nginx"
    "keepalived"

    # Additional dependencies
    "tar"
    "gzip"
    "xz-utils"
    "git"
    "build-essential"
    "libssl-dev"
    "libffi-dev"
    "python3"
    "python3-pip"
    "jq"
)

# Функция для добавления репозиториев для Ubuntu 22.04 и Kubernetes 1.32/1.33
add_repositories() {
    echo "🔧 Adding required repositories for Ubuntu 22.04 and Kubernetes $K8S_VERSION..."

    # Docker repository
    if ! grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
        echo "📥 Adding Docker repository..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_VERSION stable" | sudo tee /etc/apt/sources.list.d/docker.list
    fi

    # Kubernetes repository - ПРАВИЛЬНЫЙ ДЛЯ KUBERNETES 1.32/1.33
    if ! grep -q "pkgs.k8s.io" /etc/apt/sources.list.d/kubernetes.list 2>/dev/null; then
        echo "📥 Adding Kubernetes repository for version $K8S_VERSION..."

        # Для Kubernetes 1.32/1.33 используем правильный репозиторий
        K8S_MAJOR_MINOR=$(echo $K8S_VERSION | cut -d. -f1-2)
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

        # Это правильный репозиторий для Kubernetes 1.32/1.33 на Ubuntu 22.04
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_MAJOR_MINOR/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi

    # Обновляем списки пакетов
    echo "🔄 Updating package lists..."
    sudo apt-get update
}

# Метод 1: Используем apt-get download с зависимостями
download_with_apt_get() {
    echo "📦 Method 1: Using apt-get download..."

    local packages_to_download=()

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            packages_to_download+=("$pkg")
        fi
    done

    if [ ${#packages_to_download[@]} -eq 0 ]; then
        echo "⚠️  No packages found in repositories"
        return 1
    fi

    # Скачиваем пакеты и их зависимости
    for pkg in "${packages_to_download[@]}"; do
        echo "📥 Downloading: $pkg"

        # Создаем временную директорию
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"

        # Получаем зависимости
        DEPS=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null | grep "^\w" | sort -u)

        # Скачиваем основной пакет и зависимости
        if apt-get download $pkg $DEPS 2>/dev/null; then
            # Копируем скачанные пакеты
            for deb_file in *.deb; do
                if [ -f "$deb_file" ]; then
                    cp "$deb_file" "$DOWNLOAD_DIR/"
                    echo "✅ Downloaded: $deb_file"
                fi
            done
        else
            echo "⚠️  Failed to download: $pkg"
        fi

        # Очистка
        cd -
        rm -rf "$TEMP_DIR"
    done
}

# Метод 2: Прямое скачивание Kubernetes пакетов для версии 1.32/1.33
download_kubernetes_packages_direct() {
    echo "📦 Method 2: Direct download of Kubernetes $K8S_VERSION packages..."

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
            # Пробуем альтернативный URL
            alt_url="https://storage.googleapis.com/k8s-release/release/v$K8S_VERSION/bin/linux/amd64/$filename"
            if wget -q --timeout=30 --tries=2 "$alt_url" -O "$DOWNLOAD_DIR/$filename"; then
                echo "✅ Downloaded from alternative: $pkg"
            else
                echo "❌ Failed all attempts: $pkg"
            fi
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

# Метод 3: Скачивание системных пакетов для Ubuntu 22.04
download_system_packages() {
    echo "📦 Method 3: Downloading system packages for Ubuntu 22.04..."

    # Пакеты для Ubuntu 22.04 (Jammy) с правильными версиями
    declare -A PACKAGE_URLS=(
        # System packages
        ["curl"]="http://archive.ubuntu.com/ubuntu/pool/main/c/curl/curl_7.81.0-1ubuntu1.15_amd64.deb"
        ["wget"]="http://archive.ubuntu.com/ubuntu/pool/main/w/wget/wget_1.21.2-2ubuntu1_amd64.deb"
        ["gnupg2"]="http://archive.ubuntu.com/ubuntu/pool/main/g/gnupg2/gnupg2_2.2.27-3ubuntu2.1_amd64.deb"
        ["software-properties-common"]="http://archive.ubuntu.com/ubuntu/pool/main/s/software-properties/software-properties-common_0.99.22.7_amd64.deb"
        ["apt-transport-https"]="http://archive.ubuntu.com/ubuntu/pool/main/a/apt/apt-transport-https_2.4.9_amd64.deb"
        ["ca-certificates"]="http://archive.ubuntu.com/ubuntu/pool/main/c/ca-certificates/ca-certificates_20211016ubuntu0.22.04.1_all.deb"
        ["bridge-utils"]="http://archive.ubuntu.com/ubuntu/pool/main/b/bridge-utils/bridge-utils_1.7-1ubuntu1_amd64.deb"
        ["ntp"]="http://archive.ubuntu.com/ubuntu/pool/main/n/ntp/ntp_1.4.2.8+dfsg-1ubuntu3.2_amd64.deb"

        # Container runtime
        ["containerd"]="http://archive.ubuntu.com/ubuntu/pool/universe/c/containerd/containerd_1.6.12-0ubuntu1_amd64.deb"
        ["docker.io"]="http://archive.ubuntu.com/ubuntu/pool/universe/d/docker.io/docker.io_20.10.21-0ubuntu1_amd64.deb"

        # Networking
        ["haproxy"]="http://archive.ubuntu.com/ubuntu/pool/main/h/haproxy/haproxy_2.4.13-1ubuntu1_amd64.deb"
        ["nginx"]="http://archive.ubuntu.com/ubuntu/pool/main/n/nginx/nginx_1.18.0-6ubuntu14.4_amd64.deb"
    )

    for pkg in "${!PACKAGE_URLS[@]}"; do
        url="${PACKAGE_URLS[$pkg]}"
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

# Метод 4: Используем aptitude для скачивания с зависимостями
download_with_aptitude() {
    echo "📦 Method 4: Using aptitude..."

    if ! command -v aptitude &> /dev/null; then
        sudo apt-get install -y aptitude
    fi

    # Скачиваем пакеты в временную директорию
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    for pkg in "${ALL_PACKAGES[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            echo "📥 Downloading with dependencies: $pkg"
            if aptitude download "$pkg" 2>/dev/null; then
                for deb_file in *.deb; do
                    if [ -f "$deb_file" ]; then
                        cp "$deb_file" "$DOWNLOAD_DIR/"
                        echo "✅ Downloaded: $deb_file"
                    fi
                done
            fi
        fi
    done

    cd -
    rm -rf "$TEMP_DIR"
}

# Основной процесс
echo "🔄 Setting up for Kubernetes $K8S_VERSION on Ubuntu 22.04..."
K8S_MAJOR_MINOR=$(echo $K8S_VERSION | cut -d. -f1-2)

sudo apt-get update
add_repositories

# Пробуем все методы по порядку
download_with_apt_get
download_kubernetes_packages_direct
download_system_packages
download_with_aptitude

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
echo "📁 Packages downloaded: $(ls -1 *.deb 2>/dev/null | wc -l || echo 0)"
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