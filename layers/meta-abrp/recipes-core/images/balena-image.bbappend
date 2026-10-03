# abrp: rootfs headroom for the preloaded supervisor composition on
# raspberrypi4-64 (the 320 MiB default rootfs machine).
#
# image-balena.bbclass do_image_size_check requires the docker image content
# (supervisor ~219 MiB + preloaded helios ~62 MiB, docker-disk entry.sh) plus
# the /boot volume (~28 MiB) to fit into the spare rootfs free space during a
# HUP. CI 32236161266 raspberrypi4-64: 311296 KiB required vs 274432 KiB
# available.
#
# IMPORTANT sizing mechanics (image_types_balena.bbclass): the rootA/B
# partitions are sized from `du` of the sparse hostapp ext4 (allocated
# blocks), so padding IMAGE_ROOTFS_SIZE does NOT grow the partitions and the
# size check keeps failing with identical numbers (CI 32248014590). The
# explicit knob is BALENA_ROOTB_SIZE: when set, the rootB partition (and its
# ext4, created by truncate+mkfs to the partition size) is sized directly.
#
# IMAGE_ROOTFS_SIZE is still bumped to keep IMAGE_ROOTFS_MAXSIZE (= IMAGE_
# ROOTFS_SIZE, checked by do_image_docker) consistent with ROOTFS_SIZE.
# raspberrypi5 already sets IMAGE_ROOTFS_SIZE = "655360" upstream, passed
# unmodified (CI 32236161266), and needs no override.
IMAGE_ROOTFS_SIZE:raspberrypi4-64 = "${@balena_rootfs_size(d) + 98304}"
BALENA_ROOTB_SIZE:raspberrypi4-64 = "${@balena_rootfs_size(d) + 98304}"
