#!/usr/bin/env python3
"""Builds assets/world_geo.json from the world-atlas countries TopoJSON.

The map widget draws pre-projected geometry: every coordinate is passed
through the same Web Mercator projection the design prototype uses
(d3.geoMercator().scale(W / 2pi).translate(W/2, H/2) with W=402, H=640),
so camera math and pin positions stay identical between the prototype and
the app. Runs on the Python standard library only.

Usage: python3 scripts/build-world-geo.py [countries-110m.json]
Downloads the TopoJSON from jsDelivr when no local file is given.
"""

import json
import math
import sys
import urllib.request
from pathlib import Path

REF_W = 402.0
REF_H = 640.0
SCALE = REF_W / (2 * math.pi)
URL = "https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-110m.json"
# Web Mercator diverges at the poles; d3 clips at +/-85.0511 degrees.
MAX_LAT = 85.0511


def project(lon, lat):
    lat = max(-MAX_LAT, min(MAX_LAT, lat))
    x = REF_W / 2 + SCALE * math.radians(lon)
    y = REF_H / 2 - SCALE * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))
    return x, y


def decode_arcs(topo):
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    arcs = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append(project(x * sx + tx, y * sy + ty))
        arcs.append(pts)
    return arcs


# The camera zooms at most 34x over the reference plane, so detail below
# ~0.03 reference px (about one screen px at max zoom) is invisible.
DECIMATE = 0.03
MIN_RING_SPAN = 0.1


def decimate(pts):
    if len(pts) <= 2:
        return pts
    out = [pts[0]]
    for p in pts[1:-1]:
        q = out[-1]
        if abs(p[0] - q[0]) + abs(p[1] - q[1]) >= DECIMATE:
            out.append(p)
    out.append(pts[-1])
    return out


def ring_points(arc_indexes, arcs):
    pts = []
    for idx in arc_indexes:
        seg = arcs[idx] if idx >= 0 else list(reversed(arcs[~idx]))
        # Consecutive arcs share their join point; drop the duplicate.
        pts.extend(seg if not pts else seg[1:])
    return pts


# Rings that cross the antimeridian (Russia, Fiji, Antarctica) jump from one
# edge of the plane to the other, which paints as a line across the whole
# world. Unwrapping makes each ring continuous; the renderer never wraps the
# camera, so shifted copies cover whichever edge the ring spills past.
def unwrap(pts):
    out = [pts[0]]
    off = 0.0
    for x, y in pts[1:]:
        x += off
        prev = out[-1][0]
        if x - prev > REF_W / 2:
            off -= REF_W
            x -= REF_W
        elif prev - x > REF_W / 2:
            off += REF_W
            x += REF_W
        out.append((x, y))
    return out


# Polar rings (Antarctica) close along the bottom of the reference plane,
# deeper than the camera can ever pan, so the closure edge never shows.
POLAR_Y = REF_H


def span(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def flatten(pts):
    out = []
    for x, y in pts:
        out.append(round(x, 2))
        out.append(round(y, 2))
    return out


def main():
    if len(sys.argv) > 1:
        topo = json.loads(Path(sys.argv[1]).read_text())
    else:
        with urllib.request.urlopen(URL) as r:
            topo = json.loads(r.read())

    arcs = decode_arcs(topo)
    geometries = topo["objects"]["countries"]["geometries"]

    # Arcs used by more than one country are internal borders (the same rule
    # as topojson.mesh(a !== b) in the prototype).
    usage = {}
    def count(arc_indexes):
        for idx in arc_indexes:
            usage[idx if idx >= 0 else ~idx] = usage.get(idx if idx >= 0 else ~idx, 0) + 1

    countries = []
    for g in geometries:
        polys = g.get("arcs") or []
        if g.get("type") == "Polygon":
            polys = [polys]
        rings = []
        for poly in polys:
            for ring in poly:
                count(ring)
                pts = unwrap(ring_points(ring, arcs))
                # An odd number of antimeridian crossings means the ring
                # circles a pole: close it below the bottom clip edge.
                if abs(pts[-1][0] - pts[0][0]) > REF_W / 2:
                    pts = pts + [(pts[-1][0], POLAR_Y), (pts[0][0], POLAR_Y)]
                pts = decimate(pts)
                if len(pts) >= 3 and span(pts) >= MIN_RING_SPAN:
                    xs = [p[0] for p in pts]
                    for k in (-1, 0, 1):
                        if min(xs) + k * REF_W < REF_W and max(xs) + k * REF_W > 0:
                            rings.append(
                                flatten([(x + k * REF_W, y) for x, y in pts]))
        gid = str(g.get("id", "")).rjust(3, "0") if g.get("id") is not None else ""
        name = (g.get("properties") or {}).get("name", "")
        if rings:
            countries.append({"id": gid, "name": name, "p": rings})

    borders = [
        flatten(decimate(arcs[i]))
        for i, n in usage.items()
        if n >= 2 and len(arcs[i]) >= 2
    ]

    out = {"w": REF_W, "h": REF_H, "countries": countries, "borders": borders}
    dest = Path(__file__).resolve().parent.parent / "assets" / "world_geo.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, separators=(",", ":")))
    print(f"{dest}: {len(countries)} countries, {len(borders)} border arcs, "
          f"{dest.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
