#!/usr/bin/env python3
"""Mirrors default.project.json + src/ into tree.luau for the emulator (same mapping rules as Rojo).
usage: gen_tree.py <aether-forge dir> <out tree.luau>"""
import json, os, sys

root, out_path = sys.argv[1], sys.argv[2]
project = json.load(open(os.path.join(root, "default.project.json")))

def q(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return "{enumOrString=" + q(v) + "}"
    if isinstance(v, list) and len(v) == 3:
        return "{color3={" + ",".join(repr(x) for x in v) + "}}"
    raise ValueError(v)

def from_path(path, name):
    """Rojo file-system rules for a directory or file."""
    full = os.path.join(root, path)
    if os.path.isdir(full):
        entries = sorted(os.listdir(full))
        init = None
        for cand, cls in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
            if cand in entries:
                init = (cand, cls)
        children = []
        for e in entries:
            if init and e == init[0]:
                continue
            p = os.path.join(path, e)
            n = e
            for suffix in (".server.luau", ".client.luau", ".luau"):
                if n.endswith(suffix):
                    n = n[: -len(suffix)]
                    break
            if os.path.isdir(os.path.join(root, p)) or e.endswith(".luau"):
                children.append(from_path(p, n))
        if init:
            return {"class": init[1], "name": name, "source": os.path.join(full, init[0]), "children": children}
        return {"class": "Folder", "name": name, "children": children}
    cls = "ModuleScript"
    if full.endswith(".server.luau"):
        cls = "Script"
    elif full.endswith(".client.luau"):
        cls = "LocalScript"
    return {"class": cls, "name": name, "source": full, "children": []}

def node(name, spec):
    n = {"name": name, "children": [], "props": spec.get("$properties", {})}
    if "$path" in spec:
        fs = from_path(spec["$path"], name)
        if "$className" in spec and fs["class"] == "Folder":
            fs["class"] = spec["$className"]
        n.update({k: v for k, v in fs.items() if k != "children"})
        n["children"] = fs["children"]
    if "$className" in spec and "class" not in n:
        n["class"] = spec["$className"]
    for k, v in spec.items():
        if not k.startswith("$"):
            n["children"].append(node(k, v))
    return n

def emit(n, indent=0):
    pad = "  " * indent
    parts = [f"class={q(n.get('class', 'Folder'))}", f"name={q(n['name'])}"]
    if n.get("source"):
        parts.append(f"source={q(n['source'])}")
    props = n.get("props") or {}
    if props:
        parts.append("props={" + ",".join(f"[{q(k)}]={lua_value(v)}" for k, v in props.items()) + "}")
    kids = ",\n".join(emit(c, indent + 1) for c in n["children"])
    parts.append("children={\n" + kids + "\n" + pad + "}")
    return pad + "{" + ", ".join(parts) + "}"

tree = node("Game", project["tree"])
open(out_path, "w").write("return " + emit(tree) + "\n")
print("wrote", out_path)
