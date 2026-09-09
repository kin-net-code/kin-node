FROM docker.io/library/ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates \
      git \
      python3 \
      python3-apt \
      python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/kin-node
COPY requirements-test.txt ./

RUN python3 -m venv /opt/kin-node-test \
    && /opt/kin-node-test/bin/pip install \
      --disable-pip-version-check \
      --no-cache-dir \
      --requirement requirements-test.txt

COPY . ./

ENV KIN_ANSIBLE_PLAYBOOK=/opt/kin-node-test/bin/ansible-playbook

CMD ["./tests/container-live.sh"]
