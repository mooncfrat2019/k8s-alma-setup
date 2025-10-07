#!/bin/bash
set -e

echo "=== Creating Kubernetes Offline Bundle ==="

# Configuration
BUNDLE_NAME="k8s-offline-bundle.tar.gz"
FILES_DIR="./files"
SCRIPTS_DIR="./scripts"

# Check if we have content to bundle
if [ ! -d "$FILES_DIR/packages" ] || [ ! -d "$FILES_DIR/images" ]; then
    echo "❌ No offline content found. Please run download scripts first."
    echo "   Run: ./scripts/prepare-offline-content.sh"
    exit 1
fi

# Create the bundle
echo "📦 Creating bundle: $BUNDLE_NAME"
tar -czf "$FILES_DIR/$BUNDLE_NAME" \
    --exclude='*.tar' \
    --exclude='*.deb' \
    --exclude='k8s-offline-bundle-*.tar.gz' \
    ./files/ \
    ./scripts/ \
    ./inventory/ \
    ./group_vars/ \
    ./roles/ \
    ./site.yml \
    ./ansible.cfg 2>/dev/null || true

# Create bundle info
BUNDLE_SIZE=$(du -h "$FILES_DIR/$BUNDLE_NAME" | cut -f1)
PACKAGE_COUNT=$(find "$FILES_DIR/packages" -name "*.deb" 2>/dev/null | wc -l || echo 0)
IMAGE_COUNT=$(find "$FILES_DIR/images" -name "*.tar" 2>/dev/null | wc -l || echo 0)

cat > "$FILES_DIR/bundle-info.txt" << EOF
Kubernetes Offline Bundle
Created: $(date)
Kubernetes Version: 1.34.0
Calico Version: 3.26.0
Bundle: $BUNDLE_NAME
Size: $BUNDLE_SIZE
Contents:
- $PACKAGE_COUNT packages
- $IMAGE_COUNT Docker images
- Complete Ansible playbook

Usage:
1. Place this file in the 'files' directory of your Ansible project
2. Run the playbook with transfer role

Transfer Commands:
# SCP to remote server
scp files/$BUNDLE_NAME user@server:/tmp/

# Or use Ansible transfer role automatically
ansible-playbook -i inventory/hosts.yml site.yml -t transfer
EOF

echo "🎉 Bundle created: $FILES_DIR/$BUNDLE_NAME"
echo "📋 Info: $FILES_DIR/bundle-info.txt"
echo ""
echo "📊 Contents:"
echo "   - $PACKAGE_COUNT packages"
echo "   - $IMAGE_COUNT Docker images"
echo "   - Complete Ansible playbook"
echo ""
echo "🚀 To deploy:"
echo "   1. Ensure bundle is in files/k8s-offline-bundle.tar.gz"
echo "   2. Run: ansible-playbook -i inventory/hosts.yml site.yml"