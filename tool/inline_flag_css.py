# -*- coding: utf-8 -*-
"""Inlines `<style>` class rules into the flag SVGs that use them.

    python tool/inline_flag_css.py

flutter_svg does not implement CSS: a `<style>` block declaring `.F{fill:#fedd00}`
and a path carrying `class="F"` renders with NO fill, which paints black.
Andorra's yellow band and Mexico's, Egypt's and six others' details all came
out black on device while every flag with inline `fill=` beside them was
perfect.

The nine affected files are rewritten so each element carries the properties
its classes gave it. Nothing is restyled: the declarations are the file's own,
just moved from the stylesheet onto the elements. An element's existing
attribute always wins, because in SVG a presentation attribute is what a class
rule overrides — so writing the class value on top of one would change the
picture.
"""
import io
import os
import re

DIR = 'assets/pack_art/flags'

# `.A{fill:#fff;stroke:red}` -> {'A': {'fill': '#fff', 'stroke': 'red'}}
RULE = re.compile(r'\.([A-Za-z_][\w-]*)\s*\{([^}]*)\}')
STYLE_BLOCK = re.compile(r'<style[^>]*>(.*?)</style\s*>', re.S | re.I)
CLASS_ATTR = re.compile(r'\sclass="([^"]*)"')


def rules_of(svg):
    out = {}
    for block in STYLE_BLOCK.findall(svg):
        for name, body in RULE.findall(block):
            props = {}
            for decl in body.split(';'):
                if ':' not in decl:
                    continue
                k, v = decl.split(':', 1)
                props[k.strip()] = v.strip()
            # Later rules win, as the cascade would have them.
            out.setdefault(name, {}).update(props)
    return out


def inline(svg):
    rules = rules_of(svg)
    if not rules:
        return svg, 0

    applied = [0]

    def fix_element(m):
        tag = m.group(0)
        cm = CLASS_ATTR.search(tag)
        if not cm:
            return tag
        props = {}
        for name in cm.group(1).split():
            props.update(rules.get(name, {}))
        if not props:
            return tag
        additions = ''
        for k, v in props.items():
            # An attribute already on the element wins: a class rule loses to
            # a presentation attribute only in CSS's own ordering, and these
            # files rely on that.
            if re.search(r'\s%s="' % re.escape(k), tag):
                continue
            additions += ' %s="%s"' % (k, v)
        if not additions:
            return tag
        applied[0] += 1
        # Insert just before the tag's close, self-closing or not.
        return tag[:-2] + additions + tag[-2:] if tag.endswith('/>') else tag[:-1] + additions + tag[-1]

    # Every element that carries a class.
    svg = re.sub(r'<[a-zA-Z][^>]*\sclass="[^"]*"[^>]*>', fix_element, svg)
    # The stylesheet has done its job.
    svg = STYLE_BLOCK.sub('', svg)
    svg = CLASS_ATTR.sub('', svg)
    return svg, applied[0]


def main():
    total = 0
    for name in sorted(os.listdir(DIR)):
        if not name.endswith('.svg'):
            continue
        path = os.path.join(DIR, name)
        raw = io.open(path, encoding='utf-8', errors='ignore').read()
        if '<style' not in raw:
            continue
        out, n = inline(raw)
        io.open(path, 'w', encoding='utf-8', newline='\n').write(out)
        print('%-6s %4d elements given their class properties' % (name[:-4], n))
        total += 1
    print('%d flags rewritten' % total)


if __name__ == '__main__':
    main()
