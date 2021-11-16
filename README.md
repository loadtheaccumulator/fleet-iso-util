# fleet-iso-util

WIP dev commands:
podman build -t localhost/fleetutils:dev .

podman run -it --rm -v /home/jhollowa/dev/edgestuff/fleetkick/isodir:/isodir:Z localhost/fleetutils:dev \
    ./fleetkick.sh \
    -k /isodir/kickstart-stage-dev.ks \
    -i /isodir/holloway-autoreg.iso \
    -o /isodir/injected/holloway_autoreg_dev3.iso \
    -w /tmp -r /isodir/fleet_env.bash \
    -p /isodir/fleet_kspost.txt \
    -s /isodir/fleet_authkeys.txt

sudo mv /home/jhollowa/dev/edgestuff/fleetkick/isodir/injected/holloway_autoreg_dev3.iso /var/lib/libvirt/images/

sudo ./virtdo.sh 13 /var/lib/libvirt/images/holloway_autoreg_dev3.iso
