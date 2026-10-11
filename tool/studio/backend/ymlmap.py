#!/usr/bin/env python3
"""Masked YAML walker (stdlib only). Prints each leaf as `path: class`.

Usage: ymlmap.py FILE [FILE ...]        -> masked listing
       import ymlmap; ymlmap.parse(path) -> list of (path, raw_value, commented, lineno)
Real values are printed only for an explicit allowlist; everything else is classified.
"""
import re
import sys

ALLOW = {
    "server.port", "spring.profiles.active", "spring.jpa.hibernate.ddl-auto",
    "spring.liquibase.enabled", "spring.datasource.url", "spring.datasource.username",
    "logging.file.name", "jhipster.mail.base-url", "jhipster.mail.from",
    "jhipster.cors.allowed-origins", "sabily.spc-name", "sabily.stripe.success-url",
    "sabily.stripe.cancel-url",
}
URLISH = ("url", "host", "base-url", "endpoint")
JWT = re.compile(r"^eyJ[\w-]{5,}\.[\w-]{5,}\.?[\w-]*$")
NUM = re.compile(r"^[+-]?(\d+(\.\d+)?|0x[0-9a-fA-F]+)$")
KEYLINE = re.compile(r"""^(?P<key>"[^"]*"|'[^']*'|[^\s#'"\-][^:#]*?|-[^\s][^:#]*?)\s*:(?:\s+(?P<val>.*))?$""")
COMMENTED_LEAF = re.compile(r"""^[A-Za-z_"'][\w.\-"' \[\]]*:(\s+\S.*)?$""")


def strip_comment(v):
    """Remove a trailing ' # comment' that is outside quotes."""
    out, q = [], None
    for i, c in enumerate(v):
        if q:
            if c == q:
                q = None
        elif c in "\"'" and (i == 0 or v[i - 1] in " \t[{,:"):
            q = c
        elif c == "#" and (i == 0 or v[i - 1] in " \t"):
            break
        out.append(c)
    return "".join(out).rstrip()


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def unkey(k):
    k = k.strip()
    return unquote(k)


def parse(path):
    """Return list of (dotted_path, value_or_None, commented, lineno)."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    leaves = []
    stack = []          # list of (indent, name)
    pending = None      # (indent, path, lineno) for `key:` with no value yet
    list_idx = {}       # parent path -> next index
    doc = 0
    i = 0
    while i < len(lines):
        raw = lines[i].rstrip("\r")
        lineno = i + 1
        i += 1
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        body = raw.strip()
        if body == "---":
            if pending:
                leaves.append((pending[1], None, False, pending[2]))
                pending = None
            stack, list_idx, doc = [], {}, doc + 1
            continue
        if body.startswith("#"):
            inner = body.lstrip("#").strip()
            m = KEYLINE.match(inner) if COMMENTED_LEAF.match(inner) else None
            if m and m.group("val") and strip_comment(m.group("val")):
                col = len(raw) - len(raw.lstrip(" #"))  # indent of the text after '#'
                base = [n for (ind, n) in stack if ind < col]
                leaves.append((".".join(base + [unkey(m.group("key"))]),
                               unquote(strip_comment(m.group("val"))), True, lineno))
            continue
        # resolve a pending `key:` now that we see the next real line
        if pending:
            p_ind, p_path, p_ln = pending
            deeper = indent > p_ind or (indent == p_ind and body.startswith("- "))
            if not deeper:
                leaves.append((p_path, None, False, p_ln))
                stack.pop()
            pending = None
        is_list = body.startswith("- ") or body == "-"
        while stack and (stack[-1][0] > indent or (stack[-1][0] == indent and not (
                is_list and not stack[-1][1].startswith("[")))):
            stack.pop()
        prefix = [n for (_, n) in stack]
        if is_list:
            parent = ".".join(prefix)
            idx = list_idx.get((parent, indent), 0)
            list_idx[(parent, indent)] = idx + 1
            item = body[1:].strip()
            name = f"[{idx}]"
            quoted = item[:1] in "\"'" and item.rstrip().endswith(item[:1]) and len(item) > 1
            m = None if quoted else KEYLINE.match(item)
            if m:
                stack.append((indent, name))
                k = unkey(m.group("key"))
                v = strip_comment(m.group("val") or "")
                full = ".".join(prefix + [name, k])
                if not v:
                    stack.append((indent + 2, k))
                    pending = (indent + 2, full, lineno)
                else:
                    leaves.append((full, unquote(v), False, lineno))
            else:
                leaves.append((".".join(prefix + [name]), unquote(strip_comment(item)) or None, False, lineno))
            continue
        m = KEYLINE.match(body)
        if not m:
            leaves.append((".".join(prefix + [f"<unparsed@{lineno}>"]), body, False, lineno))
            continue
        key = unkey(m.group("key"))
        val = m.group("val")
        full = ".".join(prefix + [key])
        v = strip_comment(val) if val is not None else ""
        if v in ("|", ">", "|-", ">-", "|+", ">+"):
            block = []
            while i < len(lines) and (not lines[i].strip() or
                                      len(lines[i]) - len(lines[i].lstrip(" ")) > indent):
                block.append(lines[i].strip())
                i += 1
            leaves.append((full, "\n".join(block).strip(), False, lineno))
            continue
        if not v:
            stack.append((indent, key))
            pending = (indent, full, lineno)
            continue
        leaves.append((full, unquote(v), False, lineno))
    if pending:
        leaves.append((pending[1], None, False, pending[2]))
    return leaves


def norm_path(p):
    return re.sub(r"\.\[(\d+)\]", r"[\1]", p)


def classify(path, v):
    p = norm_path(path)
    last = p.split(".")[-1].lower()
    if v is None or v == "" or v in ("~", "null", '""', "''"):
        return "<empty>"
    m = re.fullmatch(r"\$\{([A-Za-z0-9_.\-]+)(?::(.*))?\}", v)
    if m:
        d = "none" if m.group(2) is None else classify(path, m.group(2))
        return f"<env:{m.group(1)},default={d}>"
    # Credentials inside a URL (`://user:pass@`) are masked, allowlisted key or not.
    creds = re.search(r"://[^/@\s]*@", v)
    if (p in ALLOW or last.endswith(URLISH)) and not creds:
        if p in ALLOW or "@" not in v:
            return v.split("?")[0] if ("url" in last or "?" in v) else v
    if creds:
        return "<url-with-credentials>"
    if v.startswith("PENDING_"):
        return "<PENDING>"
    for pre in ("sk_live_", "sk_test_", "pk_live_", "pk_test_", "rk_live_", "rk_test_", "whsec_"):
        if v.startswith(pre):
            return pre
    if JWT.match(v):
        return "<jwt-like>"
    if "-----BEGIN" in v:
        return "<pem>"
    if v.lower() in ("true", "false"):
        return v.lower()
    if NUM.match(v):
        return f"<number,len={len(v)}>"
    return f"<set,len={len(v)}>"


def hash_nulls(path):
    """Keys written `key: # ...`: YAML reads the value as null, not as the text after #.
    A placeholder must be a quoted string ("PENDING_...") instead."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    return [norm_path(p) for p, v, commented, ln in parse(path)
            if v is None and not commented and re.search(r":\s+#", lines[ln - 1])]


def main(argv):
    for f in argv:
        print(f"### {f}")
        for path, v, commented, ln in parse(f):
            flag = "   # COMMENTED-OUT" if commented else ""
            print(f"{norm_path(path)}: {classify(path, v)}{flag}")


if __name__ == "__main__":
    main(sys.argv[1:])
