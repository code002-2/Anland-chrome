#!/system/bin/sh
echo "HOOK-OK"
echo "daemon=$(pidof waylandbridge)"
echo "chrome=$(pgrep chrome | wc -l)  relay=$(pgrep libawlrelay | wc -l)"
echo "sf=$(pidof surfaceflinger)"
