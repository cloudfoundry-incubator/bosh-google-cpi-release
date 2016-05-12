#!/usr/bin/env bash

set -e

source bosh-cpi-src/ci/tasks/utils.sh
source /etc/profile.d/chruby-with-ruby-2.1.2.sh

check_param google_project
check_param google_region
check_param google_zone
check_param google_json_key_data
check_param google_network
check_param google_subnetwork
check_param google_subnetwork_range
check_param google_subnetwork_gw
check_param google_firewall_internal
check_param google_firewall_external
check_param google_address_director
check_param google_address_bats_ubuntu
check_param base_os
check_param stemcell_name
check_param bat_vcap_password

deployment_dir="${PWD}/deployment"
bat_manifest_filename="${deployment_dir}/${base_os}-bats-manifest.yml"
bat_config_filename="${deployment_dir}/${base_os}-bats-config.yml"
private_key=${deployment_dir}/private_key.pem
google_json_key=${deployment_dir}/google_key.json

export BAT_STEMCELL="${deployment_dir}/stemcell.tgz"
export BAT_DEPLOYMENT_SPEC="${bat_config_filename}"
export BAT_VCAP_PASSWORD="${bat_vcap_password}"
export BAT_INFRASTRUCTURE=google
export BAT_NETWORKING=dynamic
export BAT_VCAP_PRIVATE_KEY=${private_key}

echo "Creating google json key..."
echo "${google_json_key_data}" > ${google_json_key}
mkdir -p $HOME/.config/gcloud/
cp ${google_json_key} $HOME/.config/gcloud/application_default_credentials.json

echo "Configuring google account..."
gcloud auth activate-service-account --key-file $HOME/.config/gcloud/application_default_credentials.json
gcloud config set project ${google_project}
gcloud config set compute/region ${google_region}
gcloud config set compute/zone ${google_zone}

echo "Looking for director IP..."
director_ip=$(gcloud compute addresses describe ${google_address_director} --format json | jq -r '.address')
export BAT_DIRECTOR=${director_ip}
export BAT_DNS_HOST=${director_ip}

echo "Looking for bats IP..."
bats_ip=$(gcloud compute addresses describe ${google_address_bats_ubuntu} --format json | jq -r '.address')

echo "Creating private key..."
eval $(ssh-agent)
ssh-add ${private_key}

echo "Using BOSH CLI version..."
bosh version

echo "Targeting BOSH director..."
bosh -n target ${BAT_DIRECTOR}

echo "Creating ${bat_manifest_filename}..."
cat > ${bat_manifest_filename} <<EOF
---
name: <%= properties.name || "bat" %>
director_uuid: <%= properties.uuid %>

releases:
  - name: bat
    version: <%= properties.release || "latest" %>

compilation:
  workers: <%= properties.compilation_workers || 2 %>
  network: default
  reuse_compilation_vms: true
  cloud_properties:
    machine_type: <%= properties.machine_type || "n1-standard-2" %>
    root_disk_size_gb: <%= properties.root_disk_size_gb || 20 %>
    root_disk_type: <%= properties.root_disk_type || "pd-standard" %>
    <% if properties.zone %>
    zone: <%= properties.zone %>
    <% end %>

update:
  canaries: <%= properties.canaries || 1 %>
  canary_watch_time: 3000-90000
  update_watch_time: 3000-90000
  max_in_flight: <%= properties.max_in_flight || 1 %>

networks:
  - name: <%= network.name %>
    type: <%= network.type %>
    subnets:
      <% properties.network.subnets.each do |subnet| %>
      - range: <%= subnet.range %>
        gateway: <%= subnet.gateway %>
        cloud_properties:
          network_name: <%= subnet.cloud_properties.network_name %>
          subnetwork_name: <%= subnet.cloud_properties.subnetwork_name %>
          tags: <%= subnet.cloud_properties.tags || [] %>
      <% end %>
  - name: static
    type: vip

resource_pools:
  - name: common
    network: default
    stemcell:
      name: <%= properties.stemcell.name %>
      version: "<%= properties.stemcell.version %>"
    cloud_properties:
      machine_type: <%= properties.machine_type || "n1-standard-2" %>
      root_disk_size_gb: <%= properties.root_disk_size_gb || 20 %>
      root_disk_type: <%= properties.root_disk_type || "pd-standard" %>
      <% if properties.zone %>
      zone: <%= properties.zone %>
      <% end %>
    <% if properties.password %>
    env:
      bosh:
        password: <%= properties.password %>
    <% end %>

jobs:
  - name: <%= properties.job || "batlight" %>
    templates: <% (properties.templates || ["batlight"]).each do |template| %>
    - name: <%= template %>
    <% end %>
    instances: <%= properties.instances %>
    resource_pool: common
    <% if properties.persistent_disk %>
    persistent_disk: <%= properties.persistent_disk %>
    <% end %>
    networks:
    <% properties.job_networks.each_with_index do |network, i| %>
      - name: <%= network.name %>
        <% if i == 0 %>
        default: [dns, gateway]
        <% end %>
    <% end %>
    <% if properties.use_vip %>
      - name: static
        static_ips:
          - <%= properties.vip %>
    <% end %>

properties:
  batlight:
    <% if properties.batlight.fail %>
    fail: <%= properties.batlight.fail %>
    <% end %>
    <% if properties.batlight.missing %>
    missing: <%= properties.batlight.missing %>
    <% end %>
    <% if properties.batlight.drain_type %>
    drain_type: <%= properties.batlight.drain_type %>
    <% end %>
EOF

echo "Creating ${bat_config_filename}..."
cat > ${bat_config_filename} <<EOF
---
cpi: google
manifest_template_path: ${bat_manifest_filename}
properties:
  uuid: $(bosh status --uuid)
  stemcell:
    name: ${stemcell_name}
    version: latest
  instances: 1
  vip: ${bats_ip}
  network:
    name: default
    type: manual
    subnets:
    - range: ${google_subnetwork_range}
      gateway: ${google_subnetwork_gw}
      cloud_properties:
        network_name: ${google_network}
        subnetwork_name: ${google_subnetwork}
        tags:
          - ${google_firewall_internal}
          - ${google_firewall_external}
EOF

pushd bats
  echo "Installing gems..."
  ./write_gemfile
  bundle install

  echo "Running BOSH Acceptance Tests..."
  bundle exec rspec spec
popd
