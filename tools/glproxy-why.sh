#!/system/bin/sh
# glproxy-why.sh —— 查 glGetString 为什么没进生成结果
R=/data/adb/anland-chrome/root
E="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root"
chroot "$R" /usr/bin/env -i $E /usr/bin/python3 -c "
import sys, re
sys.path.insert(0, '/build/glproxy')
import importlib.util
spec = importlib.util.spec_from_file_location('g', '/build/glproxy/glproxy-gen.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
print('正则:', g.proto_re.pattern[:110])
for h in ('GLES2/gl2.h','GLES3/gl3.h'):
    fs = g.parse_header('/usr/include/'+h)
    names = [f['name'] for f in fs]
    print(h, '解析出', len(fs), '个; 含 glGetString?', 'glGetString' in names)
src = open('/usr/include/GLES2/gl2.h', encoding='utf-8', errors='ignore').read()
i = src.find('glGetString')
print('头文件里的原文:', repr(src[max(0,i-60):i+60]))
print('正则能匹配?', bool(g.proto_re.search(src[max(0,i-80):i+60])))
" 2>&1
