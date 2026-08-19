# abrp: rootfs headroom for the preloaded supervisor composition on
# raspberrypi4-64 (the 320 MiB default rootfs machine).
#
# image-balena.bbclass do_image_size_check requires the docker image content
# (supervisor ~219 MiB + preloaded helios ~62 MiB, docker-disk entry.sh) plus
# the /boot volume (~28 MiB) to fit into the spare rootfs free space during a
# HUP. With the default rootfs (image_types_balena.bbclass
# balena_rootfs_size: (700 MiB - boot - state) / 2 = 327680 KiB) this failed:
#   docker image (282624 KiB) + /boot volume (28672 KiB) = 311296 KiB
#   exceeds available space 274432 KiB                    (CI 32236161266)
#
# Bump IMAGE_ROOTFS_SIZE itself (NOT IMAGE_ROOTFS_EXTRA_SPACE: balena-image.bb
# sets IMAGE_ROOTFS_MAXSIZE = IMAGE_ROOTFS_SIZE without the extra space, so
# do_image_docker rejects the grown rootfs — CI 32241360449). raspberrypi5
# already sets IMAGE_ROOTFS_SIZE = "655360" upstream and passed unmodified.
IMAGE_ROOTFS_SIZE:raspberrypi4-64 = "${@balena_rootfs_size(d) + 98304}"
