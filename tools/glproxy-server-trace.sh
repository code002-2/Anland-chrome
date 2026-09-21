RT=/data/local/tmp/awl
pkill glproxy-server 2>/dev/null
sleep 1
rm -f $RT/glproxy.sock
GLP_TRACE=1 setsid /data/local/tmp/glproxy/glproxy-server $RT/glproxy.sock > /data/local/tmp/glproxy.log 2>&1 < /dev/null &
sleep 2
echo "server pid=$(pidof glproxy-server) trace=on"