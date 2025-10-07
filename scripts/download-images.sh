#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/images"
IMAGE_LIST_FILE="./scripts/image-list.txt"
mkdir -p $DOWNLOAD_DIR

echo "=== Downloading Kubernetes and Calico Docker Images ==="

# Список образов для загрузки (обновлен под Kubernetes 1.34.0)
K8S_IMAGES=(
    "registry.k8s.io/kube-apiserver:v1.34.0"
    "registry.k8s.io/kube-controller-manager:v1.34.0"
    "registry.k8s.io/kube-scheduler:v1.34.0"
    "registry.k8s.io/kube-proxy:v1.34.0"
    "registry.k8s.io/pause:3.9"
    "registry.k8s.io/etcd:3.5.13-0"
    "registry.k8s.io/coredns/coredns:v1.11.3"
)

CALICO_IMAGES=(
    "docker.io/calico/node:v3.26.0"
    "docker.io/calico/cni:v3.26.0"
    "docker.io/calico/kube-controllers:v3.26.0"
    "docker.io/calico/pod2daemon-flexvol:v3.26.0"
    "docker.io/calico/typha:v3.26.0"
)

REGISTRY_IMAGES=(
    "registry:2"
)

# Функция для загрузки и сохранения образа
download_and_save_image() {
    local image=$1
    local filename=$(echo $image | tr '/' '_' | tr ':' '_').tar

    echo "🐳 Downloading image: $image"

    # Пуллим образ
    if ! docker pull $image; then
        echo "❌ Failed to pull: $image"
        return 1
    fi

    # Сохраняем образ в файл
    if docker save $image -o "$DOWNLOAD_DIR/$filename"; then
        echo "💾 Saved: $filename"
        echo "$image -> $filename" >> $IMAGE_LIST_FILE
    else
        echo "❌ Failed to save: $image"
        return 1
    fi
}

# Проверяем, что Docker доступен
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed or not running"
    echo "Please install Docker first:"
    echo "  sudo apt-get update && sudo apt-get install -y docker.io"
    echo "  sudo systemctl start docker && sudo systemctl enable docker"
    exit 1
fi

# Очищаем файл списка
> $IMAGE_LIST_FILE

# Загружаем Kubernetes образы
echo ""
echo "📥 Downloading Kubernetes images..."
for image in "${K8S_IMAGES[@]}"; do
    if ! download_and_save_image "$image"; then
        echo "⚠️  Skipping $image due to error"
    fi
done

# Загружаем Calico образы
echo ""
echo "📥 Downloading Calico images..."
for image in "${CALICO_IMAGES[@]}"; do
    if ! download_and_save_image "$image"; then
        echo "⚠️  Skipping $image due to error"
    fi
done

# Загружаем registry образ
echo ""
echo "📥 Downloading Registry image..."
for image in "${REGISTRY_IMAGES[@]}"; do
    if ! download_and_save_image "$image"; then
        echo "⚠️  Skipping $image due to error"
    fi
done

# Создаем скрипт для загрузки образов в локальный registry
echo ""
echo "📝 Creating registry push script..."
cat > "$DOWNLOAD_DIR/push-to-registry.sh" << 'EOF'
#!/bin/bash
set -e

REGISTRY="${1:-localhost:5000}"
IMAGES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 Pushing images to registry: $REGISTRY"

push_image() {
    local image_file=$1
    local original_image=$(basename "$image_file" .tar | sed 's/_/:/g' | sed 's/_/\//g')
    local registry_image="$REGISTRY/$(echo $original_image | sed 's|.*/||')"

    echo "📤 Pushing: $original_image -> $registry_image"

    docker load -i "$image_file"
    docker tag "$original_image" "$registry_image"
    docker push "$registry_image"

    # Cleanup
    docker rmi "$original_image" "$registry_image" 2>/dev/null || true
    echo "✅ Pushed: $registry_image"
}

for image_file in "$IMAGES_DIR"/*.tar; do
    if [[ -f "$image_file" ]]; then
        push_image "$image_file"
    fi
done

echo ""
echo "🎉 All images pushed to registry: $REGISTRY"
EOF

chmod +x "$DOWNLOAD_DIR/push-to-registry.sh"

echo ""
echo "🎉 Image download completed!"
echo "📁 Images saved to: $DOWNLOAD_DIR"
echo "📊 Total images downloaded: $(ls -1 $DOWNLOAD_DIR/*.tar 2>/dev/null | wc -l || echo 0)"
echo ""
echo "To load images to local registry, run:"
echo "  cd $DOWNLOAD_DIR && ./push-to-registry.sh your-registry:5000"