#!/usr/bin/env python3
"""Compare secret values across backends locally; print only shared/unique booleans."""
import sys, json, itertools
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import ymlmap

def effective(conf_dir):
    vals = {}
    for f in ("application.yml", "application-prod.yml"):
        try:
            for p, v, commented, _ in ymlmap.parse(f"{conf_dir}/{f}"):
                if not commented:
                    vals[ymlmap.norm_path(p)] = v
        except FileNotFoundError:
            pass
    return vals

GROUPS = {
    "jwt_base64_secret": ["jhipster.security.authentication.jwt.base64-secret"],
    "stripe_secret_key": ["sabily.stripe.secret-key"],
    "mail_password": ["spring.mail.password"],
    "transatel_login_password": ["sabily.api.auth.login", "sabily.api.auth.password"],
    "transatel_sftp_password": ["sabily.transatel.sftp.password"],
    "db_password": ["spring.datasource.password"],
    "recaptcha_keys": ["google.recaptcha.project-id", "google.recaptcha.keys.web",
                       "google.recaptcha.keys.android", "google.recaptcha.keys.ios"],
}

def main(pairs):
    eff = {name: effective(d) for name, d in (p.split("=", 1) for p in pairs)}
    out = {}
    for g, keys in GROUPS.items():
        tup = {b: tuple(eff[b].get(k) for k in keys) for b in eff}
        res = {}
        for b, t in tup.items():
            if all(x is None or x == "" for x in t):
                res[b] = "missing"; continue
            if any((x or "").startswith("PENDING_") for x in t):
                res[b] = "pending"; continue
            others = [o for o in tup if o != b and tup[o] == t]
            res[b] = f"shared between {sorted([b] + others)}" if others else "unique"
        out[g] = res
    out["jwt_is_template_default_ZjljZjQ1"] = {
        b: ("yes" if (eff[b].get(GROUPS["jwt_base64_secret"][0]) or "").startswith("ZjljZjQ1") else "no") for b in eff}
    print(json.dumps(out, indent=1))

if __name__ == "__main__":
    main(sys.argv[1:])
