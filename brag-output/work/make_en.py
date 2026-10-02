"""Derive the English cut from the Arabic composition: same timeline, footage,
soundtrack and motion; English copy, left-to-right layout, Inter headlines.

Rebuild: cp composition/index.html composition-en/index.html && python work/make_en.py
(it rewrites the Arabic anchors in place, so it must start from the Arabic file)."""
import pathlib
import re

p = pathlib.Path(__file__).resolve().parent.parent / "composition-en" / "index.html"
s = p.read_text(encoding="utf-8")

SEL = ('<i class="sel"></i><i class="hd tl"></i><i class="hd tr"></i><i class="hd bl"></i>'
       '<i class="hd br"></i><span class="dimw"><span class="dim"></span></span>')
OV = "data-layout-allow-overlap "


def block(start, end, new):
    """Replace from the line containing `start` through the line containing `end`."""
    global s
    i = s.index(start)
    i = s.rindex("\n", 0, i) + 1
    j = s.index(end, i)
    j = s.index("\n", j)
    s = s[:i] + new + s[j:]


block('<div class="headline on-dark" id="h1">', 'src="assets/emoji/antenna.png"', f'''          <div class="headline on-dark" id="h1">
            <div class="l1"><span {OV}class="w">Travel…</span></div>
            <div class="l2"><span class="w">stay</span> <span class="w kw lat" id="kw1">connected{SEL}<img class="emo" src="assets/emoji/antenna.png" alt="" /></span></div>''')

block('<div class="subline" id="sub2">', '<div class="subline" id="sub2">',
      '          <div class="subline" id="sub2"><span class="w">The</span> <span class="w">travel</span> <span class="w lat">eSIM</span></div>')

block('<div class="headline on-dark" id="h3">', '<div class="l2"><span class="w">اختار</span>', f'''          <div class="headline on-dark" id="h3">
            <div class="l1"><span {OV}class="w kw lat" id="kw3"><span class="roll" id="roll" data-layout-allow-overflow><span class="dg"><span class="strip" data-n="12"></span></span><span class="dg"><span class="strip" data-n="20"></span></span><span class="dg"><span class="strip" data-n="30"></span></span><span class="ch">+</span></span>{SEL}<img class="emo" src="assets/emoji/globe.png" alt="" /></span></div>
            <div class="l2"><span class="w">destinations.</span> <span class="w">Pick</span> <span class="w">one.</span></div>''')

block('<div class="headline on-light" id="h4">', 'src="assets/emoji/euro.png"', f'''          <div class="headline on-light" id="h4">
            <div class="l1"><span {OV}class="w">Türkiye?</span></div>
            <div class="l2"><span class="w">A</span> <span class="w">pack</span> <span class="w">for</span> <span class="w kw lat" id="kw4">€5{SEL}<img class="emo" src="assets/emoji/euro.png" alt="" /></span></div>''')

block('<div class="headline on-dark" id="h5">', 'src="assets/emoji/airplane.png"', f'''          <div class="headline on-dark" id="h5">
            <div class="l1"><span {OV}class="w">Umrah</span> <span {OV}class="w">+</span> <span {OV}class="w">Istanbul?</span></div>
            <div class="l2"><span class="w kw emo-side" id="kw5">One pack.{SEL}<img class="emo" src="assets/emoji/airplane.png" alt="" /></span></div>''')

block('<div class="headline on-light" id="h6">', '<div class="l2"><span class="w">وخلاص!</span>', f'''          <div class="headline on-light" id="h6">
            <div class="l1"><span {OV}class="w">Scan</span> <span {OV}class="w">the</span> <span {OV}class="w kw lat dim-up" id="kw6">QR{SEL}<img class="emo" src="assets/emoji/phone.png" alt="" /></span><span {OV}class="w">…</span></div>
            <div class="l2"><span class="w">Done.</span></div>''')

block('<div class="punchline" id="h7">', '<div class="punchline" id="h7">', f'''          <div class="punchline" id="h7">
            <div><span {OV}class="w">Your</span> <span {OV}class="w kw dim-up" id="kw7">path{SEL}<img class="emo" src="assets/emoji/compass.png" alt="" /></span></div>
            <div><span class="w">to</span> <span class="w">the</span> <span class="w">world</span></div>
          </div>''')

reps = [
    ('<html lang="ar"', '<html lang="en"'),
    ('<div class="sub">تابعني باش تشوف واش راني نبني</div>', '<div class="sub">Follow for what I build next</div>'),
    ('<span>راك <span class="lat">connecté</span></span>', '<span class="lat">connected</span>'),
    ('<title>Sabily — brag</title>', '<title>Sabily — brag (EN)</title>'),
    ('wordsAt(qa("#h4 .l2 > .w"), [8.52, 8.64, 8.78]);', 'wordsAt(qa("#h4 .l2 > .w"), [8.52, 8.62, 8.72, 8.84]);'),
    ('wordsAt(qa("#h5 .l1 .w"), [11.12, 11.24, 11.32, 11.44]);', 'wordsAt(qa("#h5 .l1 .w"), [11.12, 11.24, 11.36]);'),
    ('wordsAt(qa("#h5 .l2 > .w"), [11.7, 11.84]);', 'wordsAt(qa("#h5 .l2 > .w"), [11.7]);'),
    ('wordsAt(qa("#h7 > .w"), [17.34, 17.46, 17.58]);', 'wordsAt(qa("#h7 .w"), [17.3, 17.4, 17.54, 17.62, 17.7]);'),
    # English footage (cut_segments.sh en) is left-to-right: taps land where
    # the English layout puts the Türkiye card and the Buy button, and pages
    # push in from the right like Android's LTR navigation.
    ('style="left: 298px; top: 763px"', 'style="left: 344px; top: 824px"'),
    ('style="left: 322px; top: 987px"', 'style="left: 322px; top: 978px"'),
    ('// RTL forward navigation: the new page slides in from the left, opaque,\n        // over the old one sliding right under a scrim',
     '// LTR forward navigation: the new page slides in from the right, opaque,\n        // over the old one sliding left under a scrim'),
    ('tl.fromTo(b, { xPercent: -100 }, { xPercent: 0,', 'tl.fromTo(b, { xPercent: 100 }, { xPercent: 0,'),
    ('tl.fromTo(a, { xPercent: 0 }, { xPercent: 28,', 'tl.fromTo(a, { xPercent: 0 }, { xPercent: -28,'),
    ('.vw.b { box-shadow: 26px 0 60px', '.vw.b { box-shadow: -26px 0 60px'),
    ('<h3>شريحتك جاهزة</h3>', '<h3>Your eSIM is ready</h3>'),
    ('<p>تُفعَّل تلقائيًا بمجرد اتصالها بشبكة محلية.</p>', '<p>Activates automatically the moment it connects to a local network.</p>'),
    ('    </style>', '''      /* ── English cut: left-to-right, Inter throughout ─────────── */
      .headline, .subline, .punchline { direction: ltr; font-family: "Inter", sans-serif; letter-spacing: -0.035em; }
      .lat { font-size: 1em; }
      .headline .l1 { font-size: 112px; }
      .headline .l2 { font-size: 84px; }
      #h1 .l1 { font-size: 150px; }
      #h1 .l2 { font-size: 96px; }
      #kw1 .emo { right: -104px; }
      #h3 .l1 { font-size: 170px; }
      #h3 .l2 { font-size: 76px; margin-top: 50px; }
      #h5 .l1 { font-size: 90px; }
      #h5 .l2 { font-size: 118px; }
      .subline { font-size: 72px; }
      .punchline { top: 850px; font-size: 92px; line-height: 1.12; }
      .urlw { top: 1112px; }
      .card, #pill { direction: ltr; }
      .card .sub { font-family: "Inter", sans-serif; font-weight: 700; font-size: 38px; }
      #plabel { font-family: "Inter", sans-serif; }
      #plabel .inner { padding-right: 0; padding-left: 18px; }
      .sheet { direction: ltr; }
      .sheet h3, .sheet p { font-family: "Inter", sans-serif; letter-spacing: -0.02em; }
    </style>'''),
]
for a, b in reps:
    assert a in s, a[:70]
    s = s.replace(a, b)
assert "سافر" not in s and "تابعني" not in s and "شريحتك" not in s
p.write_text(s, encoding="utf-8", newline="\n")
print("ok")
