#!/bin/bash
set -e

echo "=== Verifying Offline Content ==="

CHECK_PASSED=true

# Проверяем пакеты
echo "📦 Checking packages..."
if [ $(ls -1 files/packages/*.deb 2>/dev/null | wc -l) -gt 0 ]; then
    echo "✅ Packages: $(ls -1 files/packages/*.deb | wc -l) found"
else
    echo "❌ No packages found"
    CHECK_PASSED=false
fi

# Проверяем образы
echo "🐳 Checking Docker images..."
if [ $(ls -1 files/images/*.tar 2>/dev/null | wc -l) -gt 0 ]; then
    echo "✅ Images: $(ls -1 files/images/*.tar | wc -l) found"

    # Проверяем целостность tar файлов
    for image in files/images/*.tar; do
        if tar -tf "$image" > /dev/null 2>&1; then
            echo "   ✅ $(basename $image) - OK"
        else
            echo "   ❌ $(basename $image) - CORRUPTED"
            CHECK_PASSED=false
        fi
    done
else
    echo "❌ No Docker images found"
    CHECK_PASSED=false
fi

# Проверяем необходимые пакеты
REQUIRED_PACKAGES=("kubelet" "kubeadm" "kubectl" "containerd")
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ls files/packages/*.deb 2>/dev/null | grep -q "$pkg"; then
        echo "✅ $pkg package - FOUND"
    else
        echo "❌ $pkg package - MISSING"
        CHECK_PASSED=false
    fi
done

# Итог
echo ""
if [ "$CHECK_PASSED" = true ]; then
    echo "🎉 All checks passed! Offline content is ready."
else
    echo "❌ Some checks failed. Please re-run download scripts."
    exit 1
fi