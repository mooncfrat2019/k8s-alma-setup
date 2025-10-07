#!/bin/bash
set -e

echo "=== Preparing Complete Offline Content for Kubernetes ==="
echo "This script will download all packages and images needed for offline installation"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для проверки команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ Error: $1 is not installed${NC}"
        echo "Please install: sudo apt-get install $1"
        exit 1
    fi
}

# Функция для установки недостающих утилит
install_prerequisites() {
    echo "🔧 Installing prerequisites..."
    sudo apt-get update || true
    sudo apt-get install -y wget curl docker.io || true
}

# Проверяем и устанавливаем необходимые команды
echo "🔍 Checking prerequisites..."
for cmd in wget curl docker; do
    if ! command -v $cmd &> /dev/null; then
        echo "⚠️  $cmd not found, attempting to install..."
        install_prerequisites
        break
    fi
done

# Повторная проверка после установки
check_command wget
check_command curl

# Проверяем Docker (не критично, но предупреждаем)
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker not installed. Images won't be downloaded.${NC}"
    echo "You can install Docker later or on another machine."
    DOWNLOAD_IMAGES=false
else
    DOWNLOAD_IMAGES=true
fi

# Создаем директории
mkdir -p ./files/packages
mkdir -p ./files/images

# Загружаем пакеты
echo ""
echo -e "${YELLOW}=== DOWNLOADING PACKAGES ===${NC}"
if ./scripts/download-packages.sh; then
    echo -e "${GREEN}✅ Package download completed${NC}"
else
    echo -e "${RED}❌ Package download had errors, but continuing...${NC}"
fi

# Загружаем образы только если Docker доступен
if [ "$DOWNLOAD_IMAGES" = true ]; then
    echo ""
    echo -e "${YELLOW}=== DOWNLOADING DOCKER IMAGES ===${NC}"
    if ./scripts/download-images.sh; then
        echo -e "${GREEN}✅ Image download completed${NC}"
    else
        echo -e "${RED}❌ Image download had errors${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}=== SKIPPING DOCKER IMAGES (Docker not available) ===${NC}"
fi

# Создаем архив для переноса
echo ""
echo -e "${YELLOW}=== CREATING OFFLINE BUNDLE ===${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUNDLE_NAME="k8s-offline-bundle-${TIMESTAMP}.tar.gz"

# Копируем как основной бандл для автоматического использования
cp "$BUNDLE_NAME" "./files/k8s-offline-bundle.tar.gz" 2>/dev/null || true

# Создаем архив
if tar -czf $BUNDLE_NAME \
    --exclude='*.tar' \
    --exclude='*.deb' \
    ./files/ \
    ./scripts/ \
    ./inventory/ \
    ./group_vars/ \
    ./roles/ \
    ./site.yml 2>/dev/null; then

    # Создаем файл с информацией
    cat > bundle-info.txt << EOF
Kubernetes Offline Bundle
Created: $(date)
Kubernetes Version: 1.34.0
Calico Version: 3.26.0
Contains:
- $(find files/packages -name "*.deb" 2>/dev/null | wc -l) packages
- $(find files/images -name "*.tar" 2>/dev/null | wc -l) docker images

IMPORTANT: This bundle was created with some errors. Please verify contents.

Usage:
1. Extract bundle: tar -xzf $BUNDLE_NAME
2. Prepare servers using Ansible playbook
3. Run: ansible-playbook -i inventory/hosts.yml site.yml

Package List:
$(find files/packages -name "*.deb" 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No packages found")

Image List:
$(find files/images -name "*.tar" 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No images found")
EOF

    echo ""
    echo -e "${GREEN}🎉 Offline preparation completed!${NC}"
    echo "📦 Bundle created: $BUNDLE_NAME"
    echo "📦 Main bundle: files/k8s-offline-bundle.tar.gz"
    echo "📋 Info file: bundle-info.txt"
else
    echo -e "${RED}❌ Failed to create bundle${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}📊 Summary:${NC}"
echo "   Packages: $(find files/packages -name "*.deb" 2>/dev/null | wc -l || echo 0)"
echo "   Images: $(find files/images -name "*.tar" 2>/dev/null | wc -l || echo 0)"
echo "   Total size: $(du -sh $BUNDLE_NAME 2>/dev/null | cut -f1 || echo 'Unknown')"

# Проверяем критически важные пакеты
echo ""
echo -e "${YELLOW}🔍 Critical package check:${NC}"
CRITICAL_PACKAGES=("kubelet" "kubeadm" "kubectl" "containerd")
MISSING_CRITICAL=0

for pkg in "${CRITICAL_PACKAGES[@]}"; do
    if find files/packages -name "*${pkg}*" | grep -q .; then
        echo "✅ $pkg - FOUND"
    else
        echo -e "${RED}❌ $pkg - MISSING${NC}"
        MISSING_CRITICAL=1
    fi
done

if [ $MISSING_CRITICAL -eq 1 ]; then
    echo ""
    echo -e "${RED}🚨 CRITICAL: Some essential packages are missing!${NC}"
    echo "You may need to download them manually or use a different approach."
fi

echo ""
echo -e "${GREEN}🚀 Next steps:${NC}"
echo "1. Copy $BUNDLE_NAME to the isolated environment"
echo "2. Extract: tar -xzf $BUNDLE_NAME"
echo "3. Update inventory/hosts.yml with your IP addresses"
echo "4. Run: ansible-playbook -i inventory/hosts.yml site.yml"