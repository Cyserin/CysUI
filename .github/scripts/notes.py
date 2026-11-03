"""
Builds the release notes from the newest What's New entry in Core.lua.

Usage: python3 .github/scripts/notes.py <version>

Writes:
  CHANGELOG.md  - used by the packager for CurseForge, Wago and the GitHub release
                  (the web changelog page reads the GitHub release text)
  discord.md    - shorter copy for the Discord post

If Core.lua has no entry for <version>, a short placeholder is written so the release
still goes out.
"""
import re
import sys

version = sys.argv[1].strip()
src = open("Core.lua", encoding="utf-8").read()

SECTIONS = [("added", "Added"), ("improved", "Improved"), ("fixed", "Fixed")]
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Find this version's entry: from its '{ version = "x"' up to the next entry (or end of list).
start = re.search(r'\{\s*version\s*=\s*"' + re.escape(version) + r'"', src)
found = {}
if start:
    nxt = re.search(r'\{\s*version\s*=\s*"', src[start.end():])
    block = src[start.start(): start.end() + nxt.start()] if nxt else src[start.start():]
    for key, _ in SECTIONS:
        m = re.search(key + r'\s*=\s*\{(.*?)\n\s*\}', block, re.S)
        if m:
            items = [s.replace('\\"', '"').replace("\\\\", "\\") for s in STRING.findall(m.group(1))]
            if items:
                found[key] = items
else:
    print(f"::warning::No What's New entry for {version} in Core.lua - using a placeholder note.")

md, dc = [], []
for key, title in SECTIONS:
    if key in found:
        md.append(f"### {title}")
        dc.append(f"**{title}**")
        for line in found[key]:
            md.append(f"- {line}")
            dc.append(f"• {line}")
        md.append("")
        dc.append("")

if not md:
    md = ["### Improved", "- Maintenance update.", ""]
    dc = ["Maintenance update."]

md += [
    "---",
    "Install: download **CysUI-v...zip** (not \"Source code\"), unzip it so the folder is named "
    "`CysUI` inside `World of Warcraft\\_classic_era_\\Interface\\AddOns\\`, then type `/cui` in game.",
    "",
    "Bugs and ideas: the Issues tab, or the cysui-feedback channel on Discord.",
]

open("CHANGELOG.md", "w", encoding="utf-8").write("\n".join(md) + "\n")

text = "\n".join(dc).strip()
if len(text) > 3800:  # Discord embed text limit is 4096
    text = text[:3800].rsplit("\n", 1)[0] + "\n…and more on the changelog page."
open("discord.md", "w", encoding="utf-8").write(text + "\n")

print(open("CHANGELOG.md", encoding="utf-8").read())
