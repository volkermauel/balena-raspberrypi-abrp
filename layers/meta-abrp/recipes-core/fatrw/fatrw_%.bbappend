# abrp: upstream recipe fetches via git@github.com SSH (requires an SSH key even
# for public repos); we build key-less -> switch to https
SRC_URI:remove = "git://git@github.com/balena-os/fatrw.git;protocol=ssh;nobranch=1"
SRC_URI:prepend = "git://github.com/balena-os/fatrw.git;protocol=https;nobranch=1 "
