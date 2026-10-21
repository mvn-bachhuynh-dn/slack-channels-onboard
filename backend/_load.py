"""Load a sibling backend module by file path.

Kiro Crew loads app hook modules with ``spec_from_file_location`` (no package,
no ``sys.path`` entry), so ``from . import x`` and ``import x`` both fail. Each
module loads its siblings through this helper instead, cached in
``sys.modules`` under an app-unique name so every module shares one instance.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_PREFIX = "_kirocrew_app_slack_channels_onboard_sibling_"


def sibling(name: str) -> ModuleType:
    path = Path(__file__).with_name(f"{name}.py")
    key = _PREFIX + name
    st = path.stat()
    stamp = (str(path), st.st_mtime_ns, st.st_size)
    mod = sys.modules.get(key)
    # Re-load when the file changed: an app update/reinstall runs in the SAME
    # gateway process, so a cache keyed on the name alone keeps serving the old
    # code (seen 2026-10-19: new route, old gateway_ops without its function).
    if mod is not None and getattr(mod, "__kc_stamp__", None) == stamp:
        return mod
    spec = importlib.util.spec_from_file_location(key, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    mod.__kc_stamp__ = stamp  # type: ignore[attr-defined]
    sys.modules[key] = mod
    spec.loader.exec_module(mod)
    return mod
