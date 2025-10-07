ansible-playbook -i ./inventory/hosts.yml site.yml
ansible-playbook -i inventory/hosts.yml site.yml --tags common
ansible-playbook -i inventory/hosts.yml site.yml --tags docker-registry
ansible-playbook -i inventory/hosts.yml site.yml --tags repository
ansible-playbook -i inventory/hosts.yml site.yml --tags containerd
ansible-playbook -i inventory/hosts.yml site.yml --tags kubernetes
ansible-playbook -i inventory/hosts.yml site.yml --tags haproxy
ansible-playbook -i inventory/hosts.yml site.yml --tags init
ansible-playbook -i inventory/hosts.yml site.yml --tags post-install