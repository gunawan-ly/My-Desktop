# Image dasar: Ubuntu Noble desktop + OBS Studio (dari PPA resmi agar
# menyertakan Browser Source) + sudo untuk kasm-user.
# KASM_TAG diisi saat build (mis. 1.17.0).
ARG KASM_TAG=1.17.0
FROM kasmweb/ubuntu-noble-desktop:${KASM_TAG}
USER root
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:obsproject/obs-studio && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends obs-studio && \
    echo "kasm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kasm-user && \
    chmod 440 /etc/sudoers.d/kasm-user && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
USER 1000
