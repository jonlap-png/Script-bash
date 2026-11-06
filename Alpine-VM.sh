qemu-system-i386 \
-name Alpine-VM \
-machine pc,accel=tcg \
-m 2048 \
-smp 2 \
-drive file=alpine-disk.qcow2,format=qcow2,if=ide \
-cdrom alpine-standard-3.13.5-x86.iso \
-boot order=d \
-nic user,model=e1000