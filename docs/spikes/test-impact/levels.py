#!/usr/bin/env python3
"""Compares selection by file with selection by function, commit by commit, against the truth from
replay.sh's full runs.

For each commit, units recorded at the previous state are selected when, between the previous
state's build and this one:
- F0 (by file, as the spike does): an object in the footprint changed. The footprint is the objects
  whose functions ran, the story's declaring object, and the objects defining globals those read.
- F1 (by function): a function that ran changed or vanished; the declaring object's residue (code
  no instrumented function accounts for, such as #Preview bodies) changed; or the initialization of
  globals the footprint's objects read changed.
- F2: F1, and also the residue of any object in the footprint, which covers thunks and witnesses
  that no instrumented function references.
All three also select on a conformance added or removed for a type the footprint's objects use, and
always select new units.
"""
import collections
import json
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import funcfp

S = os.path.dirname(os.path.abspath(__file__))
commits = sys.argv[1:]  # base first


def recordings(state):
    units = {}
    for f in os.listdir(os.path.join(state, "recordings")):
        r = json.load(open(os.path.join(state, "recordings", f)))
        units[r["unit"]] = r
    return units


def truth(commit):
    own = f"{S}/states/{commit}/truth.xml"
    root = ET.parse(own if os.path.exists(own) else f"{S}/logs/{commit}-b.xml")
    out = set()
    for case in root.iter("testcase"):
        if case.find("failure") is not None:
            name = case.get("name")
            story, variant = name.rsplit(" (mac.", 1)
            out.add(f"{story}|{variant.rstrip(')')}")
    return out


EXACT = os.environ.get("EXACT") == "1"
SURVIVING = os.environ.get("SURVIVING") == "1"


def conforms(conformance, type_):
    """Whether the conformance descriptor is for type_. By prefix, as the spike does; with EXACT,
    not when what follows the prefix is a nested type (an identifier, then a type kind)."""
    if not conformance.startswith(type_):
        return False
    if not EXACT:
        return True
    rest = conformance[len(type_):]
    digits = len(rest) - len(rest.lstrip("0123456789"))
    if digits == 0:
        return True
    length = int(rest[:digits])
    after = rest[digits + length : digits + length + 1]
    return after not in ("V", "C", "O")


def global_fps(index):
    """Each global's fingerprint and the globals its initialization reads, by addressor."""
    fps, reads = {}, {}
    for o in index["objects"].values():
        fps.update(o["globals"])
        reads.update(o["global_reads"])
    return fps, reads


def prepare(index):
    owner = {}  # nameref -> (object, symbol)
    addressor_definer = {}
    for path, o in index["objects"].items():
        for ref, sym in o["functions"].items():
            owner[int(ref)] = (path, sym)
        for a in o["addressors_defined"]:
            addressor_definer[a] = path
    reads = {
        path: {addressor_definer[a] for a in o["addressors_read"] if a in addressor_definer}
        for path, o in index["objects"].items()
    }
    conformances = set()
    for o in index["objects"].values():
        conformances.update(o["conformances"])
    return owner, reads, conformances


def footprint(unit, index, owner, reads):
    ran = {owner[f][0] for f in unit["functions"] if f in owner}
    declaring = {index["sources"][s] for s in unit["sources"] if s in index["sources"]}
    objects = ran | declaring
    globals_ = set()
    pending = list(objects)
    while pending:
        for definer in reads.get(pending.pop(), ()):
            if definer not in objects and definer not in globals_:
                globals_.add(definer)
                pending.append(definer)
    return ran, declaring, globals_


print("| Commit | Units | Changed | F0 by file | F1 by function | F2 F1 + residues | F3 F1, globals each | F4 F3 + dispatch | Escapes F0/F1/F2/F3/F4 |")
print("|---|---|---|---|---|---|---|---|---|")
totals = collections.Counter()
reasons_report = []
# With PAIRS, every state after the first is compared with the first, rather than with the one
# before it.
pairs = (
    [(commits[0], c) for c in commits[1:]]
    if os.environ.get("PAIRS") == "1"
    else list(zip(commits, commits[1:])))
for prev, commit in pairs:
    P = funcfp.index_state(f"{S}/states/{prev}")
    C = funcfp.index_state(f"{S}/states/{commit}")
    p_owner, p_reads, p_conf = prepare(P)
    c_owner, c_reads, c_conf = prepare(C)
    changed_conf = p_conf ^ c_conf
    if SURVIVING:
        # Only conformances of types in both builds: a type that's new or gone changes the code
        # that uses it, which selects its users anyway.
        p_types = {t for o in P["objects"].values() for t in o["defined_types"]}
        c_types = {t for o in C["objects"].values() for t in o["defined_types"]}
        churned = p_types ^ c_types
        changed_conf = {c for c in changed_conf if not any(conforms(c, t) for t in churned)}
    p_gfps, p_greads = global_fps(P)
    c_gfps, _ = global_fps(C)
    p_dispatch = {k: v for o in P["objects"].values() for k, v in o["dispatch"].items()}
    c_dispatch = {k: v for o in C["objects"].values() for k, v in o["dispatch"].items()}
    # Dispatch data that changed, kept or gone (new data can't be what anything ran through).
    # Gone tables belong to types or conformances that are gone, whose users changed anyway.
    changed_dispatch = [k for k, v in p_dispatch.items() if k in c_dispatch and c_dispatch[k] != v]
    units = recordings(f"{S}/states/{prev}")
    current = set(recordings(f"{S}/states/{commit}"))
    real = truth(commit)
    selected = {"F0": set(), "F1": set(), "F2": set(), "F3": set(), "F4": set()}
    why = collections.Counter()

    def obj_changed(path):
        return C["objects"].get(path, {}).get("fingerprint") != P["objects"][path]["fingerprint"]

    def residue_changed(path):
        return C["objects"].get(path, {}).get("residue") != P["objects"][path]["residue"]

    def globals_changed(path):
        return C["objects"].get(path, {}).get("globals_init") != P["objects"][path]["globals_init"]

    for name, unit in units.items():
        ran, declaring, globals_ = footprint(unit, P, p_owner, p_reads)
        objects = ran | declaring | globals_
        types = set()
        for path in objects:
            types.update(P["objects"][path]["types"])
        conformance = any(conforms(c, t) for c in changed_conf for t in types)
        if conformance:
            for k in selected:
                selected[k].add(name)
            continue
        if any(obj_changed(p) for p in objects):
            selected["F0"].add(name)
        fn_changed = []
        for f in unit["functions"]:
            if f not in p_owner:
                continue
            path, sym = p_owner[f]
            new = C["objects"].get(path, {}).get("fps", {}).get(sym)
            if new != P["objects"][path]["fps"].get(sym):
                fn_changed.append(sym)
        # F3: the globals this unit's functions read, and the declaring file's reads and globals,
        # since #Preview bodies aren't instrumented; then what those globals' initializers read.
        reads = set()
        for f in unit["functions"]:
            if f in p_owner:
                path, sym = p_owner[f]
                reads.update(P["objects"][path]["fn_reads"].get(sym, ()))
        for p in declaring:
            reads.update(P["objects"][p]["addressors_read"])
            reads.update(P["objects"][p]["globals"])
        pending = list(reads)
        while pending:
            for r in p_greads.get(pending.pop(), ()):
                if r not in reads:
                    reads.add(r)
                    pending.append(r)
        global_changed = [a for a in reads if a in p_gfps and c_gfps.get(a) != p_gfps[a]]
        if fn_changed or any(residue_changed(p) for p in declaring) or global_changed:
            selected["F3"].add(name)
            selected["F4"].add(name)
        elif any(conforms(d, t) for d in changed_dispatch for t in types):
            # F4: the witness tables and metadata of the types the footprint uses.
            selected["F4"].add(name)
            why["<dispatch data>"] += 1
        f1 = (
            fn_changed
            or any(residue_changed(p) for p in declaring)
            or any(globals_changed(p) for p in globals_ | ran)
        )
        if f1:
            selected["F1"].add(name)
            selected["F2"].add(name)
            for sym in fn_changed[:3]:
                why[sym] += 1
            if not fn_changed:
                if any(residue_changed(p) for p in declaring):
                    why["<declaring residue>"] += 1
                if any(globals_changed(p) for p in globals_):
                    why["<globals read>"] += 1
                if any(globals_changed(p) for p in ran - globals_):
                    why["<globals of objects run>"] += 1
        elif any(residue_changed(p) for p in ran):
            selected["F2"].add(name)
    new_units = current - set(units)
    for k in selected:
        selected[k] |= new_units
    escapes = {k: len(real - v) for k, v in selected.items()}
    print(
        f"| {commit} | {len(current)} | {len(real)} | {len(selected['F0'])} | {len(selected['F1'])} "
        f"| {len(selected['F2'])} | {len(selected['F3'])} | {len(selected['F4'])} "
        f"| {escapes['F0']}/{escapes['F1']}/{escapes['F2']}/{escapes['F3']}/{escapes['F4']} |")
    for k, v in selected.items():
        totals[k] += len(v)
        totals[k + " escapes"] += escapes[k]
    totals["changed"] += len(real)
    if why:
        top = ", ".join(f"{s[:70]} ×{n}" for s, n in why.most_common(4))
        reasons_report.append(f"{commit}: {top}")
    for k in ("F3", "F4"):
        for unit in sorted(real - selected[k]):
            reasons_report.append(f"{commit} {k} ESCAPE {unit}")

print()
print(f"Totals: changed {totals['changed']}; selected "
      + ", ".join(f"{k} {totals[k]}" for k in ("F0", "F1", "F2", "F3", "F4"))
      + "; escapes " + ", ".join(f"{k} {totals[k + ' escapes']}" for k in ("F0", "F1", "F2", "F3", "F4")))
print()
print("\n".join(reasons_report))
