#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generates versioned winget manifests from the templates next to this
script. Run by the release workflow:

    python3 packaging/winget/generate.py --version 0.6.0 --sha256 <hex> --out winget-manifests

The output directory holds the three YAML files of one winget manifest
version (version / installer / defaultLocale), ready to be copied into a
microsoft/winget-pkgs pull request (see docs/distribution.md).
"""

import argparse
import os
import sys

TEMPLATES = [
    "Rtynbirf.Domovoy.version.template.yaml",
    "Rtynbirf.Domovoy.installer.template.yaml",
    # The defaultLocale manifest must carry the locale in its file name
    # (<PackageIdentifier>.locale.<PackageLocale>.yaml) - the winget-pkgs
    # validation pipeline rejects the old bare "locale.yaml" naming.
    "Rtynbirf.Domovoy.locale.en-US.template.yaml",
]

PLACEHOLDERS = {
    "__VERSION__": None,
    "__SHA256__": None,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="module version, e.g. 0.6.0")
    parser.add_argument("--sha256", required=True, help="sha256 of the release zip")
    parser.add_argument("--out", required=True, help="output directory for the manifests")
    args = parser.parse_args()

    placeholders = dict(PLACEHOLDERS)
    placeholders["__VERSION__"] = args.version
    placeholders["__SHA256__"] = args.sha256

    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    for template_name in TEMPLATES:
        with open(os.path.join(here, template_name), "r", encoding="utf-8") as fh:
            content = fh.read()
        for key, value in placeholders.items():
            if value is None:
                print("missing value for", key, file=sys.stderr)
                return 1
            content = content.replace(key, value)
        target_name = template_name.replace(".template", "")
        target = os.path.join(out_dir, target_name)
        with open(target, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        print("wrote", target)

    for key in ("__VERSION__", "__SHA256__"):
        for template_name in TEMPLATES + [
            name.replace(".template", "") for name in TEMPLATES
        ]:
            path = os.path.join(out_dir, template_name)
            if not os.path.exists(path):
                continue
            with open(path, "r", encoding="utf-8") as fh:
                if key in fh.read():
                    print("FAIL: placeholder", key, "left in", path, file=sys.stderr)
                    return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
