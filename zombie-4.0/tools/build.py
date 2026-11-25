#!/usr/bin/env python3
"""Skleja Zombie 4.0 do jednego pliku index.html (działa offline, bez plików zewnętrznych).
three.js (MIT) pochodzi z ../zombie-2.0/vendor i jest opakowany w globalny obiekt THREE."""
import glob, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THREE_PATH = os.path.join(ROOT, '..', 'zombie-2.0', 'vendor', 'three', 'build', 'three.module.min.js')


def three_global():
    src = open(THREE_PATH, encoding='utf-8').read()
    i = src.rfind('export{')
    j = src.rfind('}')
    body, names = src[:i], src[i + 7:j]
    pairs = []
    for item in names.split(','):
        item = item.strip()
        if not item:
            continue
        if ' as ' in item:
            local, public = [x.strip() for x in item.split(' as ')]
        else:
            local = public = item
        pairs.append('%s:%s' % (public, local))
    out = 'var THREE=(function(){' + body + '\nreturn{' + ','.join(pairs) + '};})();'
    assert '</script' not in out
    return out


def game():
    parts = []
    for path in sorted(glob.glob(os.path.join(ROOT, 'src', '*.js'))):
        parts.append('// ---- %s ----\n' % os.path.basename(path) + open(path, encoding='utf-8').read())
    code = "(function(){\n'use strict';\n" + '\n'.join(parts) + '\n})();'
    assert '</script' not in code
    return code


def main():
    shell = open(os.path.join(ROOT, 'src', 'shell.html'), encoding='utf-8').read()
    html = shell.replace('/*__THREE__*/', three_global()).replace('/*__GAME__*/', game())
    out = os.path.join(ROOT, 'index.html')
    open(out, 'w', encoding='utf-8').write(html)
    print('index.html: %.0f KB' % (os.path.getsize(out) / 1024))


if __name__ == '__main__':
    main()
