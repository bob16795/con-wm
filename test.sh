zig build || exit

Xephyr -ac -br -noreset -resizeable :5 &
DISPLAY=:5 gdb --args ./zig-out/bin/conman
killall Xephyr
