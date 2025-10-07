#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/images"
IMAGE_LIST_FILE="./scripts/image-list.txt"
mkdir -p $DOWNLOAD_DIR
mkdir -p "$(dirname "$IMAGE_LIST_FILE")"

echo "=== Downloading Kubernetes and Calico Docker Images ==="

# Версии совместимые с Kubernetes 1.32.3
K8S_VERSION="1.32.3"
CALICO_VERSION="3.27.2"  # Совместим с k8s 1.32

# Kubernetes images
K8S_IMAGES=(
    "registry.k8s.io/kube-apiserver:v${K8S_VERSION}"
    "registry.k8s.io/kube-controller-manager:v${K8S_VERSION}"
    "registry.k8s.io/kube-scheduler:v${K8S_VERSION}"
    "registry.k8s.io/kube-proxy:v${K8S_VERSION}"
    "registry.k8s.io/pause:3.9"
    "registry.k8s.io/etcd:3.5.10-0"
    "registry.k8s.io/coredns/coredns:v1.10.1"
)

# Calico images
CALICO_IMAGES=(
    "docker.io/calico/node:v${CALICO_VERSION}"
    "docker.io/calico/cni:v${CALICO_VERSION}"
    "docker.io/calico/kube-controllers:v${CALICO_VERSION}"
    "docker.io/calico/pod2daemon-flexvol:v${CALICO_VERSION}"
    "docker.io/calico/typha:v${CALICO_VERSION}"
)

# Registry image
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
        return 0
    else
        echo "❌ Failed to save: $image"
        return 1
    fi
}

# Функция для проверки доступности Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is not installed"
        echo "Please install Docker first:"
        echo "  sudo apt-get update && sudo apt-get install -y docker.io"
        return 1
    fi

    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running"
        echo "Please start Docker: sudo systemctl start docker"
        echo "And add your user to docker group: sudo usermod -aG docker $USER"
        return 1
    fi

    return 0
}

# Функция для загрузки группы образов
download_image_group() {
    local group_name=$1
    shift
    local images=("$@")

    echo ""
    echo "📥 Downloading $group_name images..."

    local success_count=0
    local total_count=${#images[@]}

    for image in "${images[@]}"; do
        if download_and_save_image "$image"; then
            success_count=$((success_count + 1))
        else
            echo "⚠️  Skipping $image due to error"
        fi
    done

    echo "✅ $group_name: $success_count/$total_count images downloaded"
    return $success_count
}

# Основной процесс
echo "🔍 Checking Docker availability..."
if ! check_docker; then
    exit 1
fi

# Очищаем файл списка
> $IMAGE_LIST_FILE

# Загружаем образы по группам
download_image_group "Kubernetes" "${K8S_IMAGES[@]}"
download_image_group "Calico" "${CALICO_IMAGES[@]}"
download_image_group "Registry" "${REGISTRY_IMAGES[@]}"

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
    local original_image=$(basename "$image_file" .tar | sed 's/_/:/' | sed 's/_/\//g')
    local registry_image="$REGISTRY/$(echo $original_image | sed 's|.*/||')"

    echo "📤 Pushing: $original_image -> $registry_image"

    # Загружаем образ
    docker load -i "$image_file"

    # Тегируем и пушим
    docker tag "$original_image" "$registry_image"
    docker push "$registry_image"

    # Очищаем
    docker rmi "$original_image" "$registry_image" 2>/dev/null || true
    echo "✅ Pushed: $registry_image"
}

# Пушим все образы
for image_file in "$IMAGES_DIR"/*.tar; do
    if [[ -f "$image_file" ]]; then
        push_image "$image_file"
    fi
done

echo ""
echo "🎉 All images pushed to registry: $REGISTRY"
echo ""
echo "To use these images in Kubernetes, update your manifests:"
echo "  image: $REGISTRY/kube-apiserver:v1.32.3"
echo "  image: $REGISTRY/calico-node:v3.27.2"
EOF

chmod +x "$DOWNLOAD_DIR/push-to-registry.sh"

# Создаем файл с информацией об образах
echo ""
echo "📝 Creating image information file..."
cat > "$DOWNLOAD_DIR/images-info.txt" << EOF
Kubernetes Images for Version: $K8S_VERSION
Calico Version: $CALICO_VERSION
Download Date: $(date)

Images downloaded:
$(ls -1 "$DOWNLOAD_DIR"/*.tar 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No images")

Total images: $(ls -1 "$DOWNLOAD_DIR"/*.tar 2>/dev/null | wc -l || echo 0)

Usage:
1. Load images to Docker: docker load -i <image_file.tar>
2. Push to local registry: cd $DOWNLOAD_DIR && ./push-to-registry.sh your-registry:5000
3. Use in Kubernetes with image: your-registry:5000/image-name:tag

Image mapping:
$(cat $IMAGE_LIST_FILE 2>/dev/null || echo "No image mapping available")
EOF

# Финальный отчет
echo ""
echo "🎉 Image download completed!"
echo "📁 Images saved to: $DOWNLOAD_DIR"

IMAGE_COUNT=$(ls -1 $DOWNLOAD_DIR/*.tar 2>/dev/null | wc -l || echo 0)
echo "📊 Total images downloaded: $IMAGE_COUNT"

if [ $IMAGE_COUNT -gt 0 ]; then
    echo ""
    echo "📋 Image list:"
    ls -la $DOWNLOAD_DIR/*.tar 2>/dev/null | awk '{print $9}' | xargs -n1 basename 2>/dev/null || echo "No images found"

    echo ""
    echo "🚀 Next steps:"
    echo "1. Copy the images directory to your offline environment"
    echo "2. Load images: docker load -i <image_file.tar>"
    echo "3. Or push to local registry: ./push-to-registry.sh your-registry:5000"
    echo ""
    echo "📄 For more info see: $DOWNLOAD_DIR/images-info.txt"

    exit 0
else
    echo "❌ No images were downloaded!"
    exit 1
fi