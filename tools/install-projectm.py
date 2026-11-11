"""Stage projectM's corresponding source, local patch and original notices."""
import os
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
prefix = Path(os.environ["MESON_INSTALL_DESTDIR_PREFIX"])
datadir = Path(sys.argv[2])
if datadir.is_absolute():
    destination = Path(os.environ.get("DESTDIR") or "/") / datadir.relative_to("/")
else:
    destination = prefix / datadir
destination /= "doc/gtkplayer/projectm"
upstream = root / "subprojects/libprojectM-4.1.8"
files = {
    root / "subprojects/packagecache/libprojectM-4.1.8.tar.gz": "libprojectM-4.1.8.tar.gz",
    root / "subprojects/projectm.wrap": "projectm.wrap",
    root / "subprojects/packagefiles/projectm/gtk-framebuffer.patch": "gtk-framebuffer.patch",
    root / "docs/projectm.md": "projectm.md",
    upstream / "LICENSE.txt": "LICENSE.txt",
    upstream / "COPYING": "COPYING",
    upstream / "vendor/hlslparser/LICENSE": "hlslparser/LICENSE",
    upstream / "vendor/projectm-eval/LICENSE.md": "projectm-eval/LICENSE.md",
}
for source, relative in files.items():
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
