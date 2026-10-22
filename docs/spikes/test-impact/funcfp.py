#!/usr/bin/env python3
"""Indexes a build's per-file Mach-O objects for selection by file and by function.

For each object: its fingerprint (as SwiftImpact computes it), the instrumented functions it defines
(profile NameRef -> symbol), a fingerprint per instrumented function, its "residue" (the code no
instrumented function accounts for, such as #Preview bodies), the global variables it defines with
a fingerprint of their initialization, the addressors it reads, its conformances, and the types it
uses.

A function's fingerprint covers its own bytes and its relocations, each naming its target:
- an external symbol by name;
- a C string by its contents;
- an uninstrumented function in the same object (a thunk, an outlined helper, a closure from a
  macro) by that function's own fingerprint, recursively;
- an instrumented function by name, since it is fingerprinted separately and counts only if it ran;
- other data by its section, its atom's bytes, and the names its relocations point at.

Atoms are the ranges between symbols, as the linker splits sections with MH_SUBSECTIONS_VIA_SYMBOLS.
"""
import bisect
import hashlib
import json
import os
import pickle
import struct
import sys

ADDEND = 10
TEXT = ("__TEXT", "__text")


class Obj:
    def __init__(self, path):
        data = open(path, "rb").read()
        self.data = data
        assert struct.unpack_from("<I", data, 0)[0] == 0xFEEDFACF
        ncmds = struct.unpack_from("<I", data, 16)[0]
        off = 32
        self.sections = []  # (seg, name, addr, size, offset, reloff, nreloc, flags)
        symtab = None
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", data, off)
            if cmd == 0x19:
                nsects = struct.unpack_from("<I", data, off + 64)[0]
                for i in range(nsects):
                    s = off + 72 + i * 80
                    name = data[s : s + 16].rstrip(b"\0").decode()
                    seg = data[s + 16 : s + 32].rstrip(b"\0").decode()
                    addr, sz, fo, _, reloff, nreloc, flags = struct.unpack_from("<QQIIIII", data, s + 32)
                    self.sections.append((seg, name, addr, sz, fo, reloff, nreloc, flags))
            elif cmd == 0x2:
                symtab = struct.unpack_from("<IIII", data, off + 8)
            off += size
        symoff, nsyms, stroff, _ = symtab
        self.symbols = []  # (name, type, sect, value)
        for i in range(nsyms):
            strx, ntype, nsect, _, value = struct.unpack_from("<IBBhQ", data, symoff + i * 16)
            end = data.index(b"\0", stroff + strx)
            self.symbols.append((data[stroff + strx : end].decode(errors="replace"), ntype, nsect, value))
        # Atom starts per section (1-based index), from defined, non-debug symbols.
        self.starts = {}
        for name, ntype, nsect, value in self.symbols:
            if ntype & 0xE0 or ntype & 0x0E != 0x0E:
                continue
            self.starts.setdefault(nsect, {}).setdefault(value, []).append(name)
        self.sorted_starts = {k: sorted(v) for k, v in self.starts.items()}
        self.relocs = {}
        for idx, sec in enumerate(self.sections, 1):
            reloff, nreloc = sec[5], sec[6]
            rs = []
            for r in range(nreloc):
                address, info = struct.unpack_from("<iI", data, reloff + r * 8)
                rs.append((address, info))
            rs.sort(key=lambda x: x[0])
            self.relocs[idx] = rs
        self.index = {(s[0], s[1]): i for i, s in enumerate(self.sections, 1)}
        self.memo = {}
        # Per atom: the global addressors it references, directly or through uninstrumented helpers.
        self.reads = {}

    def section(self, idx):
        return self.sections[idx - 1]

    def atom(self, idx, addr):
        """The atom of section idx containing address addr: (start, end, names)."""
        starts = self.sorted_starts.get(idx, [])
        seg, name, saddr, size = self.section(idx)[:4]
        i = bisect.bisect_right(starts, addr) - 1
        start = starts[i] if i >= 0 else saddr
        end = starts[i + 1] if i + 1 < len(starts) else saddr + size
        names = self.starts[idx].get(start, ["<section start>"]) if i >= 0 else ["<section start>"]
        return start, end, names

    def bytes_of(self, idx, start, end):
        sec = self.section(idx)
        if sec[7] & 0xFF in (0x1, 0xC, 0x12):
            return b""
        return self.data[sec[4] + start - sec[2] : sec[4] + end - sec[2]]

    def relocs_in(self, idx, start, end):
        sec = self.section(idx)
        lo, hi = start - sec[2], end - sec[2]
        rs = self.relocs[idx]
        i = bisect.bisect_left(rs, (lo, -1))
        out = []
        while i < len(rs) and rs[i][0] < hi:
            out.append(rs[i])
            i += 1
        return out

    def fingerprint_atom(self, idx, start, end, instrumented, depth=0):
        key = (idx, start)
        if key in self.memo:
            return self.memo[key]
        self.memo[key] = b"<cycle>"
        reads = self.reads.setdefault(key, set())
        h = hashlib.sha256(self.bytes_of(idx, start, end))
        addend = 0
        for address, info in self.relocs_in(idx, start, end):
            symnum = info & 0xFFFFFF
            pcrel, length, extern, rtype = (info >> 24) & 1, (info >> 25) & 3, (info >> 27) & 1, info >> 28
            if rtype == ADDEND:
                addend = symnum - (1 << 24) if symnum & 0x800000 else symnum
                continue
            if extern:
                name = self.symbols[symnum][0]
                if name.endswith("vau") or name.endswith("vauZ"):
                    reads.add(name)
            target = self.target_key(extern, symnum, addend, instrumented, depth)
            if target.startswith(b"helper:"):
                helper = self.symbols[symnum]
                hstart = self.atom(helper[2], helper[3] + addend)[0]
                reads.update(self.reads.get((helper[2], hstart), ()))
            addend = 0
            h.update(struct.pack("<iBBB", address - (start - self.section(idx)[2]), pcrel, length, rtype))
            h.update(target)
        digest = h.digest()
        self.memo[key] = digest
        return digest

    def target_key(self, extern, symnum, addend, instrumented, depth):
        if not extern:
            return b"sect:%d" % symnum
        name, ntype, nsect, value = self.symbols[symnum]
        if ntype & 0x0E != 0x0E:
            return b"ext:" + name.encode() + b"+%d" % addend
        target = value + addend
        seg, sname = self.section(nsect)[:2]
        if (seg, sname) == TEXT:
            start, end, names = self.atom(nsect, target)
            if any(n in instrumented for n in names):
                return b"fn:" + min(names).encode()
            if depth > 64:
                return b"deep:" + min(names).encode()
            return b"helper:" + self.fingerprint_atom(nsect, start, end, instrumented, depth + 1)
        if sname == "__cstring":
            sec = self.section(nsect)
            o = sec[4] + target - sec[2]
            return b"str:" + self.data[o : self.data.index(b"\0", o)]
        start, end, names = self.atom(nsect, target)
        h = hashlib.sha256(f"{seg},{sname}+{target - start}".encode())
        h.update(self.bytes_of(nsect, start, end))
        for address, info in self.relocs_in(nsect, start, end):
            if info >> 27 & 1 and info >> 28 != ADDEND:
                h.update(self.symbols[info & 0xFFFFFF][0].encode())
        return b"data:" + h.digest()


def index_object(path):
    o = Obj(path)
    prf = o.index.get(("__DATA", "__llvm_prf_data"))
    functions = {}  # nameref -> symbol
    if prf:
        sec = o.section(prf)
        # Each record's CounterPtr is relocated against ___profc_<PGO name>. The PGO name is the
        # function's mangled name, after "<path>:" for file-local functions.
        counters = {a: o.symbols[info & 0xFFFFFF][0] for a, info in o.relocs[prf]
                    if info >> 27 & 1 and info >> 28 == 0}
        defined_names = {s[0] for s in o.symbols if s[1] & 0x0E == 0x0E}
        for rec in range(0, sec[3], 64):
            nameref = struct.unpack_from("<Q", o.data, sec[4] + rec)[0]
            profc = counters.get(rec + 16, "")
            if not profc.startswith("___profc_"):
                continue
            pgo = profc[len("___profc_"):]
            symbol = "_" + pgo.rsplit(":", 1)[-1]
            if symbol in defined_names:
                functions[nameref] = symbol
    instrumented = set(functions.values())
    text = o.index.get(TEXT)
    fps = {}
    residue = hashlib.sha256()
    globals_init = {}
    if text:
        for start in o.sorted_starts.get(text, []):
            s, e, names = o.atom(text, start)
            fp = o.fingerprint_atom(text, s, e, instrumented)
            if any(n in instrumented for n in names):
                for n in names:
                    fps[n] = fp.hex()[:24]
            else:
                residue.update(min(names).encode() + fp)
            for n in names:
                # A global's initialization: its once-function, initializer, and addressors.
                if n.endswith("_WZ") or "vpfi" in n or n.endswith("vau") or n.endswith("vauZ"):
                    globals_init[n] = fp.hex()[:24]
    # Reads per instrumented function, and each defined global's own initialization: the atoms
    # named after it (its addressor, initializer, and once-function), by content.
    fn_reads = {}
    atoms_by_name = {}
    if text:
        for start in o.sorted_starts.get(text, []):
            s, e, names = o.atom(text, start)
            for n in names:
                atoms_by_name[n] = (s, e)
                if n in instrumented and o.reads.get((text, s)):
                    fn_reads[n] = sorted(o.reads[(text, s)])
    globals_ = {}
    global_reads = {}
    for addressor in [n for n in atoms_by_name if n.endswith("vau") or n.endswith("vauZ")]:
        base = addressor[: -4] if addressor.endswith("vauZ") else addressor[: -3]
        parts = sorted(
            n for n in atoms_by_name
            if n.startswith(base) or (n.endswith("_WZ") and base.startswith(n[: -3])))
        h = hashlib.sha256()
        reads = set()
        for n in parts:
            s, e = atoms_by_name[n]
            h.update(n.encode() + o.fingerprint_atom(text, s, e, set()))
            reads |= o.reads.get((text, s), set())
        globals_[addressor] = h.hexdigest()[:24]
        global_reads[addressor] = sorted(reads - {addressor})
    # Dispatch data: each witness table (WP) and full type metadata (Mf, which holds a class's
    # vtable), by content.
    dispatch = {}
    for name, ntype, nsect, value in o.symbols:
        if ntype & 0xE0 or ntype & 0x0E != 0x0E or not name.startswith("_$s"):
            continue
        # Struct and enum metadata dispatches nothing; code that reads their fields changes itself.
        if name.endswith("WP") or name.endswith("CMf"):
            # The table's bytes, and each entry's target by content: a witness thunk's name stays
            # the same when the member it calls changes. Instrumented targets go by name, since
            # their own changes count when they run.
            start, end, _ = o.atom(nsect, value)
            h = hashlib.sha256(o.bytes_of(nsect, start, end))
            for address, info in o.relocs_in(nsect, start, end):
                if info >> 28 == ADDEND:
                    continue
                h.update(struct.pack("<i", address))
                h.update(o.target_key(info >> 27 & 1, info & 0xFFFFFF, 0, instrumented, 0))
            dispatch[name] = h.hexdigest()[:24]
    defined = [s[0] for s in o.symbols if not s[1] & 0xE0 and s[1] & 0x0E == 0x0E]
    undefined = [s[0] for s in o.symbols if not s[1] & 0xE0 and s[1] & 0x0E == 0]
    types = set()
    for n in defined + undefined:
        if n.startswith("_$s"):
            for suffix in ("Mn", "Ma", "N"):
                if n.endswith(suffix):
                    types.add(n[: -len(suffix)])
                    break
    return {
        "functions": {str(k): v for k, v in functions.items()},
        "fps": fps,
        "residue": residue.hexdigest()[:24],
        "globals_init": hashlib.sha256(json.dumps(sorted(globals_init.items())).encode()).hexdigest()[:24],
        "addressors_defined": [n for n in defined if n.endswith("vau") or n.endswith("vauZ")],
        "addressors_read": [n for n in undefined if n.endswith("vau") or n.endswith("vauZ")],
        "fn_reads": fn_reads,
        "dispatch": dispatch,
        "globals": globals_,
        "global_reads": global_reads,
        "conformances": [n for n in defined if n.startswith("_$s") and n.endswith("Mc")],
        "defined_types": sorted(n[:-2] for n in defined if n.startswith("_$s") and n.endswith("Mn")),
        "types": sorted(types),
    }


def index_state(state):
    cache = os.path.join(state, "index.pickle")
    if os.path.exists(cache):
        return pickle.load(open(cache, "rb"))
    objects = {}
    file_maps = {}
    for root, _, files in os.walk(os.path.join(state, "out")):
        for f in files:
            path = os.path.join(root, f)
            rel = os.path.relpath(path, state)
            if f.endswith(".o"):
                objects[rel] = index_object(path)
                objects[rel]["fingerprint"] = file_fingerprint(path)
            elif f.endswith("-OutputFileMap.json"):
                module = f[: -len("-OutputFileMap.json")]
                for source, outs in json.load(open(path)).items():
                    if source and "object" in outs:
                        obj = outs["object"]
                        rel_obj = obj[obj.index("out/Intermediates.noindex") :]
                        file_maps[f"{module}/{os.path.basename(source)}"] = rel_obj
    result = {"objects": objects, "sources": file_maps}
    pickle.dump(result, open(cache, "wb"))
    return result


def file_fingerprint(path):
    """SwiftImpact's object fingerprint: every non-__DWARF section's bytes and relocations, with
    relocations naming their symbols."""
    o = Obj(path)
    total = hashlib.sha256()
    for idx, sec in enumerate(o.sections, 1):
        seg, name, _, size, off, _, _, flags = sec
        if seg == "__DWARF":
            continue
        h = hashlib.sha256(f"{seg},{name}".encode())
        if flags & 0xFF not in (0x1, 0xC, 0x12):
            h.update(o.data[off : off + size])
        for address, info in sorted(o.relocs[idx], key=lambda r: r[0]):
            h.update(struct.pack("<iI", address, info & 0xFF000000))
            h.update(o.symbols[info & 0xFFFFFF][0].encode() if info >> 27 & 1 else str(info & 0xFFFFFF).encode())
        total.update(h.digest())
    return total.hexdigest()[:24]


if __name__ == "__main__":
    for state in sys.argv[1:]:
        r = index_state(state)
        n = sum(len(o["fps"]) for o in r["objects"].values())
        print(f"{state}: {len(r['objects'])} objects, {n} instrumented functions fingerprinted")
