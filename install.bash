autoreconf --force --install -I m4
./configure --enable-gtk3 --disable-static --enable-memconf --enable-vala --disable-python-library
make -C src && make -C bindings && make -j$(nproc)
