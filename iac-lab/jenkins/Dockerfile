# Jenkins with every tool the pipeline needs: Docker CLI, Terraform, Ansible, Python tests.
FROM jenkins/jenkins:lts-jdk17

USER root

ARG TERRAFORM_VERSION=1.9.8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ansible curl unzip openssh-client \
      python3 python3-pytest python3-flask \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI only; it talks to the Docker engine on your laptop through the mounted socket
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker

# Terraform (picks the right build for Intel/AMD or Apple Silicon)
RUN ARCH="$(dpkg --print-architecture)" \
 && curl -fsSL -o /tmp/terraform.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" \
 && unzip /tmp/terraform.zip -d /usr/local/bin \
 && rm /tmp/terraform.zip

# Pipeline plugins, installed at build time so there is nothing to click
RUN jenkins-plugin-cli --plugins \
      workflow-aggregator git credentials-binding pipeline-stage-view timestamper
