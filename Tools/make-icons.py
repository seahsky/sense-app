#!/usr/bin/env python3
"""Generate the SENSE app icon as SVG, then rasterize to 1024x1024 PNG.

The mark is concentric dashed rings expanding from a solid core: a pulse
travelling outward. It shares the in-app web motif's dashed stroke and its exact
red, so the icon and the interface read as one system without being the same
drawing.

Two compositions, because the platforms crop differently. watchOS masks icons to
a circle, so the watch composition pulls the outermost ring well inside the
square. iOS keeps a rounded square and can carry the rings wider.

Three iOS appearances. Supplying only one lets the system derive the tinted
variant itself, which for a dark-ground mark comes out muddy.
"""
import subprocess, sys, pathlib

GROUND = "#0D0708"
MOTIF  = "#B3202A"
ACCENT = "#3A55E0"
INK    = "#F5EFE0"

def rings(size, spread, core_r, stroke_w, dash, ring_colour, core_colour,
          ground=None, ring_opacities=None):
    """Concentric dashed rings around a solid core.

    `spread` scales ring radii relative to the canvas, so the watch build can
    pull everything inward for the circular mask without redrawing anything.
    """
    c = size / 2
    parts = []
    if ground:
        parts.append(f'<rect width="{size}" height="{size}" fill="{ground}"/>')

    # Four rings at increasing radius, each fainter and more finely dashed than
    # the last, so the pulse reads as travelling outward and losing energy.
    radii = [0.20, 0.30, 0.40, 0.50]
    if ring_opacities is None:
        ring_opacities = [1.0, 0.86, 0.70, 0.54]
    for radius, opacity in zip(radii, ring_opacities):
        r = size * radius * spread
        dash_len = dash * (r / (size * 0.20 * spread))
        parts.append(
            f'<circle cx="{c}" cy="{c}" r="{r:.2f}" fill="none" '
            f'stroke="{ring_colour}" stroke-opacity="{opacity:.2f}" '
            f'stroke-width="{stroke_w:.2f}" '
            f'stroke-dasharray="{dash_len:.2f} {dash_len * 1.4:.2f}" '
            f'stroke-linecap="round"/>'
        )

    parts.append(
        f'<circle cx="{c}" cy="{c}" r="{size * core_r * spread:.2f}" fill="{core_colour}"/>'
    )
    return "\n  ".join(parts)


def svg(size, spread, ground, ring_colour, core_colour, ring_opacities=None):
    body = rings(
        size=size, spread=spread, core_r=0.105,
        stroke_w=size * 0.025, dash=size * 0.055,
        ring_colour=ring_colour, core_colour=core_colour,
        ground=ground, ring_opacities=ring_opacities,
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">\n  {body}\n</svg>\n'
    )


def render(path_svg, path_png, content, size):
    pathlib.Path(path_svg).write_text(content)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", path_png, path_svg],
        check=True,
    )
    print(f"  {path_png}")


def main(outdir):
    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    S = 1024

    variants = {
        # iOS keeps the rounded square, so the rings can run wider.
        "ios-light":  dict(spread=1.00, ground=GROUND, ring=MOTIF, core=ACCENT),
        "ios-dark":   dict(spread=1.00, ground=GROUND, ring=MOTIF, core=ACCENT),
        # Tinted is composited as a grayscale mask by the system: supply real
        # luminance separation rather than colour, or the mark disappears.
        "ios-tinted": dict(spread=1.00, ground=None, ring=INK, core=INK,
                           opacities=[1.0, 0.84, 0.66, 0.50]),
        # watchOS masks to a circle: pull everything inside the inscribed circle.
        "watch":      dict(spread=0.82, ground=GROUND, ring=MOTIF, core=ACCENT),
    }

    print("rendering:")
    for name, cfg in variants.items():
        content = svg(
            S, cfg["spread"], cfg["ground"], cfg["ring"], cfg["core"],
            cfg.get("opacities"),
        )
        render(out / f"{name}.svg", out / f"{name}.png", content, S)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icons")
