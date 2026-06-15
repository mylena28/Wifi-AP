import os
import sys
from flask import Flask, send_file, abort, Response

app = Flask(__name__)

BASE = os.environ.get("IMAGE_DIR") or (sys.argv[1] if len(sys.argv) > 1 else ".")
BASE = os.path.realpath(BASE)

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp"}

HTML_HEAD = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Gallery</title>
  <style>
    body { font-family: sans-serif; margin: 0; padding: 12px; background: #111; color: #eee; }
    h2 { font-size: 1rem; word-break: break-all; margin-bottom: 12px; }
    a { color: #7bf; text-decoration: none; }
    .grid { display: flex; flex-wrap: wrap; gap: 10px; }
    .img-card { text-align: center; font-size: 0.75rem; max-width: 160px; }
    .img-card img { width: 150px; height: 110px; object-fit: cover;
                    border-radius: 6px; border: 1px solid #444; }
    .dir-list { list-style: none; padding: 0; margin-bottom: 16px; }
    .dir-list li { padding: 6px 0; border-bottom: 1px solid #333; }
    .back { display: inline-block; margin-bottom: 12px;
            padding: 6px 12px; background: #333; border-radius: 4px; }
  </style>
</head>
<body>
"""

@app.route("/", defaults={"subpath": ""})
@app.route("/<path:subpath>")
def browse(subpath):
    full_path = os.path.realpath(os.path.join(BASE, subpath))

    # prevent path traversal outside BASE
    if not full_path.startswith(BASE):
        abort(403)

    if os.path.isfile(full_path):
        return send_file(full_path)

    if not os.path.isdir(full_path):
        abort(404)

    entries = sorted(os.listdir(full_path))
    dirs = [e for e in entries if os.path.isdir(os.path.join(full_path, e))]
    images = [e for e in entries if os.path.splitext(e)[1].lower() in IMAGE_EXT]
    others = [e for e in entries
              if e not in dirs and os.path.splitext(e)[1].lower() not in IMAGE_EXT]

    def href(name):
        return ("/" + subpath + "/" + name).replace("//", "/")

    parts = [HTML_HEAD, f"<h2>/{subpath or ''}</h2>"]

    if subpath:
        parent = "/".join(subpath.rstrip("/").split("/")[:-1])
        parts.append(f'<a class="back" href="/{parent}">&#8592; Back</a>')

    if dirs:
        parts.append("<ul class='dir-list'>")
        for d in dirs:
            parts.append(f'<li>&#128193; <a href="{href(d)}">{d}/</a></li>')
        parts.append("</ul>")

    if others:
        parts.append("<ul class='dir-list'>")
        for f in others:
            parts.append(f'<li>&#128196; <a href="{href(f)}">{f}</a></li>')
        parts.append("</ul>")

    if images:
        parts.append("<div class='grid'>")
        for img in images:
            parts.append(
                f'<div class="img-card">'
                f'<a href="{href(img)}">'
                f'<img src="{href(img)}" loading="lazy"/>'
                f'</a><br>{img}</div>'
            )
        parts.append("</div>")

    if not dirs and not images and not others:
        parts.append("<p>Empty folder.</p>")

    parts.append("</body></html>")
    return Response("".join(parts), mimetype="text/html")


# Android network validation probe — returns 204 so Android stops cycling BT PAN
@app.route("/generate_204")
def generate_204():
    return Response(status=204)


if __name__ == "__main__":
    print(f"[GALLERY] Base folder: {BASE}")
    app.run(host="::", port=8080, debug=False)
