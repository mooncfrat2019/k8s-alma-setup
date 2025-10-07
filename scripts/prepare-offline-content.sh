#!/bin/bash
set -e

echo "=== Preparing Complete Offline Content for Kubernetes $K8S_VERSION ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
K8S_VERSION="1.32.3"
DOWNLOAD_DIR="./files"
PACKAGES_DIR="$DOWNLOAD_DIR/packages"
IMAGES_DIR="$DOWNLOAD_DIR/images"

# Создаем директории
mkdir -p $PACKAGES_DIR
mkdir -p $IMAGES_DIR

# Функция для проверки команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ Error: $1 is not installed${NC}"
        return 1
    fi
    return 0
}

# Функция для установки Docker
install_docker() {
    echo "🔧 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    echo "⚠️  Please log out and log back in for group changes to take effect, or run: newgrp docker"
}

# Основной процесс
echo "🔍 Checking prerequisites..."

# Проверяем базовые утилиты
for cmd in wget curl; do
    if ! check_command "$cmd"; then
        echo "📥 Installing $cmd..."
        sudo apt-get update && sudo apt-get install -y $cmd
    fi
done

# Проверяем Docker
if ! check_command "docker"; then
    echo -e "${YELLOW}⚠️  Docker not found. Installing...${NC}"
    install_docker
    echo -e "${YELLOW}⚠️  Please run this script again after Docker installation${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker daemon not running. Starting...${NC}"
    sudo systemctl start docker
fi

# Загружаем пакеты
echo ""
echo -e "${YELLOW}=== DOWNLOADING PACKAGES ===${NC}"
if ./scripts/download-packages.sh; then
    echo -e "${GREEN}✅ Package download completed${NC}"
else
    echo -e "${RED}❌ Package download had errors${NC}"
    echo "Continuing with image download..."
fi

# Загружаем образы
echo ""
echo -e "${YELLOW}=== DOWNLOADING DOCKER IMAGES ===${NC}"
if ./scripts/download-images.sh; then
    echo -e "${GREEN}✅ Image download completed${NC}"
else
    echo -e "${RED}❌ Image download had errors${NC}"
fi

# Создаем архив для переноса
echo ""
echo -e "${YELLOW}=== CREATING OFFLINE BUNDLE ===${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUNDLE_NAME="k8s-offline-bundle-${TIMESTAMP}.tar.gz"

# Создаем архив
tar -czf $BUNDLE_NAME \
    --exclude='*.tar' \
    --exclude='*.deb' \
    ./files/ \
    ./scripts/ \
    ./inventory/ \
    ./group_vars/ \
    ./roles/ \
    ./site.yml \
    ./ansible.cfg 2>/dev/null || true

# Копируем как основной бандл
cp "$BUNDLE_NAME" "./files/k8s-offline-bundle.tar.gz" 2>/dev/null || true

# Создаем файл с информацией
cat > "bundle-info.txt" << EOF
Kubernetes Offline Bundle
Created: $(date)
Kubernetes Version: $K8S_VERSION
Calico Version: 3.27.2
Bundle: $BUNDLE_NAME

Contents:
- $(find $PACKAGES_DIR -name "*.deb" 2>/dev/null | wc -l) packages
- $(find $IMAGES_DIR -name "*.tar" 2>/dev/null | wc -l) Docker images
- Complete Ansible playbook

Usage:
1. Extract: tar -xzf $BUNDLE_NAME
2. Update inventory/hosts.yml with your server IPs
3. Run: ansible-playbook -i inventory/hosts.yml site.yml

Critical Packages Check:
$(for pkg in kubelet kubeadm kubectl containerd docker.io; do
    if find $PACKAGES_DIR -name "*${pkg}*" | grep -q .; then
        echo "✅ $pkg"
    else
        echo "❌ $pkg"
    fi
done)

Images Check:
$(for img in kube-apiserver calico-node; do
    if find $IMAGES_DIR -name "*${img}*" | grep -q .; then
        echo "✅ $img"
    else
        echo "❌ $img"
    fi
done)
EOF

echo ""
echo -e "${GREEN}🎉 Offline preparation completed!${NC}"
echo "📦 Bundle created: $BUNDLE_NAME"
echo "📦 Main bundle: files/k8s-offline-bundle.tar.gz"
echo "📋 Info file: bundle-info.txt"

# Финальная проверка
echo ""
echo -e "${YELLOW}📊 Final Summary:${NC}"
echo "   Packages: $(find $PACKAGES_DIR -name "*.deb" 2>/dev/null | wc -l || echo 0)"
echo "   Images: $(find $IMAGES_DIR -name "*.tar" 2>/dev/null | wc -l || echo 0)"
echo "   Total size: $(du -sh $BUNDLE_NAME 2>/dev/null | cut -f1 || echo 'Unknown')"

echo ""
echo -e "${GREEN}🚀 Next steps:${NC}"
echo "1. Copy $BUNDLE_NAME to the isolated environment"
echo "2. Extract: tar -xzf $BUNDLE_NAME"
echo "3. Update inventory/hosts.yml with your IP addresses"
echo "4. Run: ansible-playbook -i inventory/hosts.yml site.yml"