#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

BASE_DIR = "/home/rev/My_Personal_Space/Projects/Unfinished/Miee"
DESIGN_DIR = os.path.join(BASE_DIR, "design_source", "miee_design_system")

ACTIVE_HTML_DIR = os.path.join(DESIGN_DIR, "active_screens", "html")
ACTIVE_IMG_DIR = os.path.join(DESIGN_DIR, "active_screens", "images")
ARCHIVE_HTML_DIR = os.path.join(DESIGN_DIR, "archive_variants", "html")
ARCHIVE_IMG_DIR = os.path.join(DESIGN_DIR, "archive_variants", "images")

for d in [ACTIVE_HTML_DIR, ACTIVE_IMG_DIR, ARCHIVE_HTML_DIR, ARCHIVE_IMG_DIR]:
    os.makedirs(d, exist_ok=True)

# 1. Load active screens from list_screens output
with open('/home/rev/.gemini/antigravity-ide/brain/ba6495dd-7d53-422d-b548-ea73b99b5b5b/.system_generated/steps/29/output.txt') as f:
    ls_data = json.load(f)

# 2. Load project data
with open('/home/rev/.gemini/antigravity-ide/brain/ba6495dd-7d53-422d-b548-ea73b99b5b5b/.system_generated/steps/23/output.txt') as f:
    project_data = json.load(f)

# 3. Load all screens from transcript
transcript_path = '/home/rev/.gemini/antigravity-ide/brain/ba6495dd-7d53-422d-b548-ea73b99b5b5b/.system_generated/logs/transcript.jsonl'
all_screens = {}

for s in ls_data['screens']:
    all_screens[s['name']] = s

with open(transcript_path) as f:
    for line in f:
        try:
            entry = json.loads(line)
            content = entry.get('content', '')
            if 'projects/5859565558274264408/screens/' in content and 'downloadUrl' in content:
                start = content.find('{\"name\":\"projects/5859565558274264408/screens/')
                if start != -1:
                    json_str = content[start:]
                    try:
                        s_data = json.loads(json_str)
                        all_screens[s_data['name']] = s_data
                    except:
                        pass
        except:
            pass

active_names = [s['name'] for s in ls_data['screens']]
archived_names = [k for k in all_screens.keys() if k not in active_names]

def slugify(title):
    cleaned = title.lower()
    cleaned = cleaned.replace("—", "-").replace("–", "-")
    cleaned = re.sub(r'[^a-z0-9]+', '_', cleaned).strip('_')
    return cleaned

# Save metadata
with open(os.path.join(DESIGN_DIR, "metadata.json"), "w") as f:
    json.dump({
        "project": {
            "name": project_data.get("name"),
            "title": project_data.get("title"),
            "designTheme": project_data.get("designTheme")
        },
        "active_screens": [all_screens[k] for k in active_names],
        "archived_screens": [all_screens[k] for k in archived_names]
    }, f, indent=2)

# Save Design System Markdown
with open(os.path.join(DESIGN_DIR, "DESIGN_SYSTEM.md"), "w") as f:
    f.write(project_data.get("designTheme", {}).get("designMd", "# Miee Design System\n"))

# Generate download script and download files
curl_commands = ["#!/usr/bin/env bash", "set -e", "echo 'Downloading Stitch Screens...'"]

downloads = []

for i, name in enumerate(active_names, 1):
    s = all_screens[name]
    sid = name.split('/')[-1]
    title = s.get('title', 'Untitled')
    dtype = s.get('deviceType', 'DESKTOP').lower()
    slug = f"{i:02d}_{dtype}_{slugify(title)}"
    
    html_url = s.get('htmlCode', {}).get('downloadUrl')
    img_url = s.get('screenshot', {}).get('downloadUrl')
    
    html_file = os.path.join(ACTIVE_HTML_DIR, f"{slug}.html")
    img_file = os.path.join(ACTIVE_IMG_DIR, f"{slug}.jpg")
    
    downloads.append((title, sid, "active", html_url, html_file, img_url, img_file, slug, dtype, s.get('width'), s.get('height')))

for i, name in enumerate(archived_names, 1):
    s = all_screens[name]
    sid = name.split('/')[-1]
    title = s.get('title', 'Untitled')
    dtype = s.get('deviceType', 'DESKTOP').lower()
    slug = f"{i:02d}_{dtype}_{slugify(title)}"
    
    html_url = s.get('htmlCode', {}).get('downloadUrl')
    img_url = s.get('screenshot', {}).get('downloadUrl')
    
    html_file = os.path.join(ARCHIVE_HTML_DIR, f"{slug}.html")
    img_file = os.path.join(ARCHIVE_IMG_DIR, f"{slug}.jpg")
    
    downloads.append((title, sid, "archive", html_url, html_file, img_url, img_file, slug, dtype, s.get('width'), s.get('height')))

for item in downloads:
    title, sid, category, html_url, html_file, img_url, img_file, slug, dtype, w, h = item
    rel_html = os.path.relpath(html_file, BASE_DIR)
    rel_img = os.path.relpath(img_file, BASE_DIR)
    curl_commands.append(f"echo 'Downloading code for: {title}'")
    curl_commands.append(f'curl -L -s -o "{rel_html}" "{html_url}"')
    curl_commands.append(f"echo 'Downloading screenshot for: {title}'")
    curl_commands.append(f'curl -L -s -o "{rel_img}" "{img_url}"')

curl_sh_path = os.path.join(DESIGN_DIR, "download_screens.sh")
with open(curl_sh_path, "w") as f:
    f.write("\n".join(curl_commands) + "\n")
os.chmod(curl_sh_path, 0o755)

print(f"Prepared {len(downloads)} screens ({len(downloads)*2} files). Downloading now with curl...")

success_count = 0
fail_count = 0

for item in downloads:
    title, sid, category, html_url, html_file, img_url, img_file, slug, dtype, w, h = item
    print(f"[{category.upper()}] {title} ({dtype})...")
    
    # Download HTML
    res1 = subprocess.run(["curl", "-L", "-s", "-o", html_file, html_url])
    # Download Image
    res2 = subprocess.run(["curl", "-L", "-s", "-o", img_file, img_url])
    
    h_size = os.path.getsize(html_file) if os.path.exists(html_file) else 0
    i_size = os.path.getsize(img_file) if os.path.exists(img_file) else 0
    
    if res1.returncode == 0 and res2.returncode == 0 and h_size > 0 and i_size > 0:
        success_count += 1
    else:
        fail_count += 1
        print(f"  FAILED: html_size={h_size}, img_size={i_size}")

print(f"Download complete: {success_count} succeeded, {fail_count} failed.")

# Generate Catalog Markdown
catalog_md = f"""# Miee Music Player Design System — Stitch Screen Catalog

**Project Title:** {project_data.get('title')}  
**Project ID:** 5859565558274264408  
**Design Theme:** Editorial Tactility  
**Total Screens:** {len(downloads)} (19 Active, 21 Archived / Variant)

---

## 1. Active Screens (19 Screens)
These are the current active screens in the Stitch design project:

| # | Device | Title | Screen ID | Dimensions | Code (HTML) | Screenshot (Image) |
|---|---|---|---|---|---|---|
"""

for item in downloads:
    title, sid, category, html_url, html_file, img_url, img_file, slug, dtype, w, h = item
    if category != "active":
        continue
    rel_html = os.path.relpath(html_file, DESIGN_DIR)
    rel_img = os.path.relpath(img_file, DESIGN_DIR)
    catalog_md += f"| {slug[:2]} | **{dtype.upper()}** | {title} | `{sid}` | {w}×{h} | [{slug}.html]({rel_html}) | [![Preview]({rel_img})]({rel_img}) |\n"

catalog_md += """
---

## 2. Archived / Variant Screens (21 Screens)
These are historical iterations and screen variants preserved from the project:

| # | Device | Title | Screen ID | Dimensions | Code (HTML) | Screenshot (Image) |
|---|---|---|---|---|---|---|
"""

for item in downloads:
    title, sid, category, html_url, html_file, img_url, img_file, slug, dtype, w, h = item
    if category != "archive":
        continue
    rel_html = os.path.relpath(html_file, DESIGN_DIR)
    rel_img = os.path.relpath(img_file, DESIGN_DIR)
    catalog_md += f"| {slug[:2]} | **{dtype.upper()}** | {title} | `{sid}` | {w}×{h} | [{slug}.html]({rel_html}) | [![Preview]({rel_img})]({rel_img}) |\n"

catalog_path = os.path.join(DESIGN_DIR, "README.md")
with open(catalog_path, "w") as f:
    f.write(catalog_md)

print("Wrote README.md and catalog.")
