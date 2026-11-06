# Image dasar ArtCraft Suite: Ubuntu Noble + ArtCraft Launcher + 13 aplikasi
# Craft Suite (alternatif Adobe/Office open-source).
# File .deb diunduh saat build oleh scripts/kasm/build_artcraft.sh
# dan ditaruh di subfolder debs/.
# KASM_TAG diisi saat build (mis. 1.17.0).
ARG KASM_TAG=1.17.0
FROM kasmweb/ubuntu-noble-desktop:${KASM_TAG}
USER root
COPY debs/*.deb /tmp/artcraft-debs/
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/artcraft-debs/*.deb && \
    echo "kasm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kasm-user && \
    chmod 440 /etc/sudoers.d/kasm-user && \
    rm -rf /tmp/artcraft-debs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
USER 1000
