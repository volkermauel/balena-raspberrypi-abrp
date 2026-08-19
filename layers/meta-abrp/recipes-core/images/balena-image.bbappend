# abrp: rootfs headroom for the preloaded supervisor composition.
#
# image-balena.bbclass do_image_size_check requires the docker image content
# (supervisor ~219 MiB + preloaded helios ~62 MiB, docker-disk entry.sh) plus
# the /boot volume (~28 MiB) to fit into the spare rootfs free space during a
# HUP. The default rootfs (image_types_balena.bbclass balena_rootfs_size:
# (700 MiB - boot - state) / 2 = 320 MiB per partition) no longer provides
# enough free space once helios and the ~46 MiB docker-compose binary (rootfs
# content) are added. CI run 32236161266 raspberrypi4-64 failed with:
#   docker image (282624 KiB) + /boot volume (28672 KiB) = 311296 KiB
#   exceeds available space 274432 KiB
# 96 MiB extra restores ~60 MiB of headroom over the current requirement.
# raspberrypi5 already sets IMAGE_ROOTFS_SIZE = "655360" and is unaffected
# in practice, but the extra space applies harmlessly there too.
IMAGE_ROOTFS_EXTRA_SPACE = "98304"
