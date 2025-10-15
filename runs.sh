ansible-playbook -i ./inventory/hosts.yml site.yml
ansible-playbook -i inventory/hosts.yml site.yml --tags common
ansible-playbook -i inventory/hosts.yml site.yml --tags docker-registry
ansible-playbook -i inventory/hosts.yml site.yml --tags etcd
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
  "pod_network_cidr": "10.244.0.0/16",
  "skip_bundle_transfer": true,
  "need_restart": false,
  "need_k8s_prepare": false
}' --tags kubernetes


ansible-playbook -i inventory/hosts.yml site.yml -e '{
  "super_user": "altlinux",
  "host_1": "89.208.223.4",
  "host_2": "89.208.229.134",
  "host_3": "212.111.86.144",
  "in_ip_1": "10.0.3.155",
  "in_ip_2": "10.0.3.104",
  "in_ip_3": "10.0.3.64",
  "host_registry": "217.16.23.176",
  "pod_network_cidr": "10.244.0.0/16",
  "cni_plugin": "cilium",
  "skip_bundle_transfer": false,
  "need_restart": true,
  "need_k8s_prepare": true
}' --tags transfer


ansible-playbook -i inventory/hosts.yml site.yml -e '{
  "super_user": "altlinux",
  "host_1": "37.139.43.48",
  "host_2": "217.16.22.229",
  "host_3": "89.208.221.86",
  "in_ip_1": "10.0.3.241",
  "in_ip_2": "10.0.3.97",
  "in_ip_3": "10.0.3.105",
  "host_registry": "89.208.222.175",
  "pod_network_cidr": "10.244.0.0/16",
  "cni_plugin": "cilium",
  "skip_bundle_transfer": false,
  "need_restart": true,
  "need_k8s_prepare": true
}' --tags transfer