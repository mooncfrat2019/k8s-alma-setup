ansible-playbook -i ./inventory/hosts.yml site.yml
ansible-playbook -i inventory/hosts.yml site.yml --tags common
ansible-playbook -i inventory/hosts.yml site.yml --tags docker-registry
ansible-playbook -i inventory/hosts.yml site.yml --tags repository
#ansible-playbook -i inventory/hosts.yml site.yml --tags containerd
ansible-playbook -i inventory/hosts.yml site.yml --tags kubernetes
ansible-playbook -i inventory/hosts.yml site.yml --tags haproxy
ansible-playbook -i inventory/hosts.yml site.yml --tags init
ansible-playbook -i inventory/hosts.yml site.yml --tags post-install

ansible-playbook -i inventory/hosts.yml site.yml -e '{
  "super_user": "altlinux",
  "host_1": "89.208.208.109",
  "host_2": "89.208.228.250",
  "host_3": "89.208.228.216",
  "in_ip_1": "10.0.3.97",
  "in_ip_2": "10.0.3.248",
  "in_ip_3": "10.0.3.105",
  "host_registry": "89.208.208.139",
  "skip_bundle_transfer": true,
  "need_restart": false,
  "need_k8s_prepare": false
}' --tags etcd

