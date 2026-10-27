#!/bin/sh
#
# First-boot delta for hi3516cv6xx_waybeam_generic. Runs once from
# S30customizer, before S94unixqlen / S95waybeam start anything.
#
# Two things differ from the waybeam package's own default, and neither can be
# done with the tools the SigmaStar build uses: this image ships no json_cli
# (it is a star6e target in the waybeam tree) and no majestic `cli`. So the
# config is edited in place, once, before the daemon has ever read it.
#
# 1. Self-update has to point at this target's asset. The name must be exactly
#    <device>-nor.tgz: CI renames the compound device name
#    (hi3516cv6xx_waybeam_generic has more than one underscore) to that before
#    publishing, and S99upgrade follows BUILD_PLATFORM out of /etc/os-release.
#
# 2. The stream goes to wifibroadcast, not to a unicast UDP address. wfb_tx
#    (started by S98wifibroadcast) binds the abstract unix datagram socket
#    rtp_local, so waybeam writes there with outgoing.server unix://rtp_local.
#    The shipped default is udp://192.168.1.10:5600, an example address that
#    would silently throw the stream at nothing on an air unit.
#
# allowUnixEncoderStall stays false (the package default): with no receiver
# yet at boot, waybeam must drop rather than stall the encoder. Everything else
# -- fps 30, 1920x1080, cbr 6000 -- is left at the shipped config; an FPV build
# tunes those over the HTTP API (/api/v1/config), which is also the only thing
# that should rewrite this file once the daemon is running.

fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/hi3516cv6xx_waybeam_generic-nor.tgz'

if [ -f /etc/waybeam.json ]; then
	sed -i 's#"server": *"[^"]*"#"server": "unix://rtp_local"#' /etc/waybeam.json
fi

# 3. Telemetry goes through mavfwd, not msposd. The shipped /etc/wfb.yaml names
#    msposd as the router, but msposd has no Hi3516CV6xx flavour (it renders OSD
#    through the SoC region/overlay layer, and its package knows only the
#    sigmastar and V4-hisi families), so this image does not select it -- see
#    general/package/wifibroadcast-ng/Config.in in this device. mavfwd is a
#    plain serial<->UDP forwarder and is what telemetry actually needs. The
#    serial port is left at the package default (ttyS2) on purpose, and it is
#    wrong for this SoC: cv6xx has PL011 UARTs named ttyAMA0/1/2, and only
#    ttyAMA0 (the console, CN2) is wired on the carrier boards seen so far --
#    CN1 is the Ethernet harness (TX-/TX+/RX-/RX- are the 100BASE-TX pairs,
#    plus 12V/GND/Reset/LED), and ttyAMA1/ttyAMA2 exist in the kernel but are
#    not brought out on any labelled connector.  Telemetry therefore needs
#    either spare pads found on the board or the console UART taken over (drop
#    getty from /etc/inittab, dmesg -n 1, .telemetry.serial ttyAMA0), and both
#    are waiting on hardware: an RTL8812 adapter and a flight controller are
#    not attached yet.  Left as ttyS2 rather than guessed, so nobody reads a
#    made-up port as a working one.
if [ -f /etc/wfb.yaml ]; then
	wifibroadcast cli -s .telemetry.router mavfwd
fi

# 4. Mark the first-boot seeding in /usr/bin/wifibroadcast as already done.
#    That block (video_settings) rewrites the encoder through majestic's `cli`
#    -- fps 60, bitrate 8000, codec h265, records.split, .fpv.*, the sensor
#    profile under /etc/sensors -- and then SIGHUPs majestic and appends
#    `alink_drone &` to /etc/rc.local. None of those binaries exist on a waybeam
#    image, so on the next boot the line it appended would just fail. The parts
#    of that block that do apply here (adapter detection, txpower, wlan_adapter
#    in /etc/wfb.yaml, monitor mode, channel) are not in it: they live in
#    load_modules/load_interface, which run on every boot regardless.
#    The encoder keeps the waybeam config's own settings either way.
touch /etc/system.ok

exit 0
