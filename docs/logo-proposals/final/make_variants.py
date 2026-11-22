#!/usr/bin/env python3
"""Generate the Alt Right icon variants from one geometry.

Geometry measured from the PNG the operator supplied (icon-1024.png):
  tile      rounded rect 100,100 824x824, r=186  (macOS icon grid)
  A         apex (403,304), base (243,726)-(563,726)
  A eyes    (365,591) r20, (445,591) r20
  R         triangle (599,303) (803,514) (599,726)
  R leg     (599,640) (685,726) (599,726)
  R eyes    (659,451) r17.5, (701,491) r17.5

Every variant below reuses those numbers verbatim; only the background changes.
Run:  python3 make_variants.py     (writes ../variants/*.svg)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "variants")
os.makedirs(OUT, exist_ok=True)

EYE = "#0A0E22"

# name, angle-ish gradient stops, optional overlay
VARIANTS = [
    # --- blues -------------------------------------------------------------
    ("01-azure", [
        (0.00, "#8FB6FF", 1),
        (0.48, "#3E78FA", 1),
        (1.00, "#1838B4", 1),
    ], "softlight"),

    ("02-cobalt", [
        (0.00, "#3A6AFF", 1),
        (0.55, "#2246D6", 1),
        (1.00, "#0D2172", 1),
    ], None),

    ("03-glacier", [
        (0.00, "#A9C7FF", 1),
        (0.45, "#6D97FF", 1),
        (1.00, "#3A63E8", 1),
    ], "softlight"),

    ("04-indigo", [
        (0.00, "#8A96FF", 1),
        (0.50, "#4C57EC", 1),
        (1.00, "#1F199B", 1),
    ], None),

    ("05-midnight", [
        (0.00, "#3364E8", 1),
        (0.52, "#132569", 1),
        (1.00, "#04071C", 1),
    ], None),

    # --- alternates --------------------------------------------------------
    ("06-teal", [
        (0.00, "#5AE6CD", 1),
        (0.50, "#17B0A6", 1),
        (1.00, "#056B6D", 1),
    ], None),

    ("07-ember", [
        (0.00, "#FFC57E", 1),
        (0.50, "#FF8A47", 1),
        (1.00, "#D53E1C", 1),
    ], None),

    ("08-night", [
        (0.00, "#1B2456", 1),
        (0.55, "#0C1130", 1),
        (1.00, "#06081B", 1),
    ], "stars"),
]

STARS = """
  <g fill="#ffffff">
    <circle cx="793" cy="250" r="5" opacity="0.55"/>
    <circle cx="214" cy="792" r="4" opacity="0.4"/>
    <circle cx="884" cy="452" r="3" opacity="0.35"/>
    <circle cx="170" cy="330" r="2.6" opacity="0.3"/>
    <circle cx="700" cy="828" r="3" opacity="0.35"/>
  </g>"""

MARK = """
  <!-- A -->
  <path d="M 403 304 L 563 726 L 243 726 Z" fill="#ffffff"/>
  <circle cx="365" cy="591" r="20" fill="{eye}"/>
  <circle cx="445" cy="591" r="20" fill="{eye}"/>

  <!-- R, with its leg -->
  <path d="M 599 303 L 803 514 L 599 726 Z" fill="#ffffff"/>
  <path d="M 599 640 L 685 726 L 599 726 Z" fill="#ffffff"/>
  <circle cx="659" cy="451" r="17.5" fill="{eye}"/>
  <circle cx="701" cy="491" r="17.5" fill="{eye}"/>
"""

TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0.1" y1="0" x2="0.9" y2="1">
{stops}
    </linearGradient>
{extra_defs}  </defs>

  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#bg)"/>
{overlay}
{mark}</svg>
"""

SOFTLIGHT = """    <radialGradient id="glow" cx="0.28" cy="0.08" r="0.75">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.30"/>
      <stop offset="0.65" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
"""

for name, stops, overlay in VARIANTS:
    stop_xml = "\n".join(
        f'      <stop offset="{o:.2f}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops
    )
    extra = ""
    over = ""
    if overlay == "softlight":
        extra = SOFTLIGHT
        over = '  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#glow)"/>\n'
    elif overlay == "stars":
        over = STARS + "\n"

    svg = TEMPLATE.format(
        stops=stop_xml,
        extra_defs=extra,
        overlay=over,
        mark=MARK.format(eye=EYE),
    )
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(svg)
    print("wrote", name)
