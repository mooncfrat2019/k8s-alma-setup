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
        exit 1
    fi
}

# Проверяем необходимые команды
echo "🔍 Checking prerequisites..."
check_command docker
check_command apt-get
check_command curl

# Создаем директории
mkdir -p ./files/packages
mkdir -p ./files/images

# Загружаем пакеты
echo ""
echo -e "${YELLOW}=== DOWNLOADING PACKAGES ===${NC}"
if ! ./scripts/download-packages.sh; then
    echo -e "${RED}❌ Package download failed${NC}"
    exit 1
fi

# Загружаем образы
echo ""
echo -e "${YELLOW}=== DOWNLOADING DOCKER IMAGES ===${NC}"
if ! ./scripts/download-images.sh; then
    echo -e "${RED}❌ Image download failed${NC}"
    exit 1
fi

# Создаем архив для переноса
echo ""
echo -e "${YELLOW}=== CREATING OFFLINE BUNDLE ===${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUNDLE_NAME="k8s-offline-bundle-${TIMESTAMP}.tar.gz"

tar -czf $BUNDLE_NAME \
    --exclude='*.tar' \
    --exclude='*.deb' \
    ./files/ \
    ./scripts/ \
    ./inventory/ \
    ./group_vars/ \
    ./roles/ \
    ./site.yml

# Создаем файл с информацией
cat > bundle-info.txt << EOF
Kubernetes Offline Bundle
Created: $(date)
Kubernetes Version: 1.34.0
Calico Version: 3.26.0
Contains:
- $(ls -1 files/packages/*.deb 2>/dev/null | wc -l) packages
- $(ls -1 files/images/*.tar 2>/dev/null | wc -l) docker images

Usage:
1. Extract bundle: tar -xzf $BUNDLE_NAME
2. Prepare servers using Ansible playbook
3. Run: ansible-playbook -i inventory/hosts.yml site.yml

Package List:
$(ls -1 files/packages/*.deb 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No packages")

Image List:
$(ls -1 files/images/*.tar 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No images")
EOF

echo ""
echo -e "${GREEN}🎉 Offline preparation completed!${NC}"
echo "📦 Bundle created: $BUNDLE_NAME"
echo "📋 Info file: bundle-info.txt"
echo ""
echo -e "${YELLOW}📊 Summary:${NC}"
echo "   Packages: $(ls -1 files/packages/*.deb 2>/dev/null | wc -l || echo 0)"
echo "   Images: $(ls -1 files/images/*.tar 2>/dev/null | wc -l || echo 0)"
echo "   Total size: $(du -sh $BUNDLE_NAME | cut -f1)"
echo ""
echo -e "${GREEN}🚀 Next steps:${NC}"
echo "1. Copy $BUNDLE_NAME to the isolated environment"
echo "2. Extract: tar -xzf $BUNDLE_NAME"
echo "3. Update inventory/hosts.yml with your IP addresses"
echo "4. Run: ansible-playbook -i inventory/hosts.yml site.yml"