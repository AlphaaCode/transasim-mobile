#!/usr/bin/env bash
# spc-backend-check.sh - READ-ONLY health/config check of one SPC backend. Run with sudo.
# Prints ONE JSON object (booleans, counts, enums, names, hashes; never a secret value).
# Studio (docs/STUDIO-SPEC.md §16.6) reads it; schema_version says which fields it holds.
#
#   sudo ./spc-backend-check.sh --slug acorn-backend --dir /apps/acorn-backend --db acorn_prod \
#        --pgport 6478 --port 9074 --domain acorn.transasim.com --expect-host vmi3448057 \
#        --public-ip 169.58.35.140 [--google-client <web client id>] [--stripe-account]
#
# Nothing is modified: only ps/ss/curl/getent/nginx -T/certbot certificates/journalctl/ufw
# status/systemctl show and SELECT/catalog queries via psql. --stripe-account also calls
# GET api.stripe.com/v1/account with the configured key, printing neither key nor answer.
# Needs ymlmap.py next to this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG= DIR= DB= PGPORT=5432 PORT= DOMAIN= EXPECT= PUBLIC_IP= GOOGLE_CLIENT= STRIPE_ACCOUNT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG=$2; shift 2;; --dir) DIR=$2; shift 2;; --db) DB=$2; shift 2;;
    --pgport) PGPORT=$2; shift 2;; --port) PORT=$2; shift 2;; --domain) DOMAIN=$2; shift 2;;
    --expect-host) EXPECT=$2; shift 2;; --public-ip) PUBLIC_IP=$2; shift 2;;
    --google-client) GOOGLE_CLIENT=$2; shift 2;; --stripe-account) STRIPE_ACCOUNT=1; shift;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
for v in SLUG DIR DB PORT DOMAIN EXPECT; do [ -n "${!v}" ] || { echo "--${v,,} is required" >&2; exit 2; }; done
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 2; }

exec python3 -I - "$HERE" "$SLUG" "$DIR" "$DB" "$PGPORT" "$PORT" "$DOMAIN" "$EXPECT" "$PUBLIC_IP" \
  "$GOOGLE_CLIENT" "$STRIPE_ACCOUNT" <<'PY'
import sys, os, re, json, glob, socket, subprocess, datetime, zipfile, urllib.request, ssl, hashlib, stat

SCRIPT_VERSION = "1.1.1"
SCHEMA_VERSION = 2  # 2: time precision 6 hashes as the default it equals
HERE = sys.argv[1]
sys.path.insert(0, HERE)
import ymlmap

# The guard of last resort: never print anything that looks like a secret marker.
MARKERS = re.compile(r"sk_|pk_|eyJ|BEGIN|password", re.I)


def sh(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except Exception as e:
        return 99, "", str(e)


def sha(data, n):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()[:n]


# ---- pure parsers (selftest below runs them on a PC) --------------------------

def ufw_open(text):
    """(active, entries open to Anywhere on no interface) from `ufw status`."""
    if "Status: active" not in text:
        return False, ["all (ufw inactive)"]
    out = []
    for line in text.splitlines():
        m = re.match(r"^(\S.*?)\s{2,}ALLOW(?: IN)?\s+Anywhere(?: \(v6\))?\s*$", line)
        if m and " on " not in m.group(1):
            entry = m.group(1).replace(" (v6)", "").strip()
            if entry not in out:
                out.append(entry)
    return True, out


def entry_covers(entry, port):
    """Whether a ufw entry such as '6478/tcp', '80,443/tcp' or '9060:9099/tcp' covers port."""
    spec = entry.split("/")[0]
    for part in spec.split(","):
        if ":" in part:
            lo, hi = part.split(":", 1)
            if lo.isdigit() and hi.isdigit() and int(lo) <= port <= int(hi):
                return True
        elif part.isdigit() and int(part) == port:
            return True
    return False


def postgres_ports(ss_text):
    return sorted({int(m.group(1)) for m in re.finditer(r"[:\]](\d+)\s.*\"postgres\"", ss_text)})


def server_blocks(nginx_t):
    """The text of every `server { ... }` block in `nginx -T` output."""
    blocks, i = [], 0
    for m in re.finditer(r"(^|[\s;{}])server\s*\{", nginx_t):
        start = m.end()
        if start < i:
            continue
        depth, j = 1, start
        while j < len(nginx_t) and depth:
            depth += {"{": 1, "}": -1}.get(nginx_t[j], 0)
            j += 1
        blocks.append(nginx_t[start:j - 1])
        i = j
    return blocks


def names_of(block):
    return re.findall(r"server_name\s+([^;]+);", block)


def management_denied(block):
    m = re.search(r"location\s+[\^~=]*\s*/management/?\s*\{([^}]*)\}", block)
    return bool(m and re.search(r"deny\s+all|return\s+40[34]", m.group(1)))


def http_only_backend(block):
    """A block served over plain HTTP that proxies to a local backend without redirecting."""
    listens = re.findall(r"listen\s+([^;]+);", block)
    plain = any("ssl" not in l and "443" not in l for l in listens)
    tls = any("ssl" in l or "443" in l for l in listens)
    redirects = re.search(r"return\s+30[18]", block)
    return plain and not tls and not redirects and re.search(r"proxy_pass\s+https?://(127\.0\.0\.1|localhost):", block)


def schema_hashes(column_rows, check_rows):
    """Per table, a hash of its sorted 'col type null=YES|NO' lines; per CHECK, of its definition."""
    cols = {}
    for t, c, typ, null in column_rows:
        # timestamp(6) is how Hibernate spells PostgreSQL's default precision, which Liquibase
        # leaves unwritten: the same column either way (seen on 32 columns, 2026-10-11).
        typ = re.sub(r"^(time(?:stamp)?)\(6\)", r"\1", typ)
        cols.setdefault(t, []).append(f"{c} {typ} null={null}")
    return {"tables": {t: sha("\n".join(sorted(v)), 8) for t, v in sorted(cols.items())},
            "checks": {f"{t}.{n}": sha(d, 8) for t, n, d in sorted(check_rows)}}


def world_readable(path):
    """Readable by anyone: the file is o+r and every directory above it is o+x."""
    try:
        if not os.stat(path).st_mode & stat.S_IROTH:
            return False
        d = os.path.dirname(os.path.abspath(path))
        while True:
            if not os.stat(d).st_mode & stat.S_IXOTH:
                return False
            if d == os.path.dirname(d):
                return True
            d = os.path.dirname(d)
    except OSError:
        return False


def host_of(url):
    m = re.match(r"^[a-z]+://([^/:?#]+)", url or "")
    return m.group(1).lower() if m else None


def selftest():
    active, entries = ufw_open("Status: active\n\nTo                         Action      From\n--  ------  ----\n"
                               "22/tcp                     ALLOW       Anywhere\n"
                               "Nginx Full                 ALLOW       Anywhere\n"
                               "6478/tcp                   ALLOW       Anywhere\n"
                               "9060:9099/tcp on docker0   ALLOW       Anywhere\n"
                               "22/tcp (v6)                ALLOW       Anywhere (v6)\n")
    assert active and entries == ["22/tcp", "Nginx Full", "6478/tcp"], entries
    assert ufw_open("Status: inactive\n") == (False, ["all (ufw inactive)"])
    assert entry_covers("6478/tcp", 6478) and entry_covers("80,443/tcp", 443) and entry_covers("9060:9099/tcp", 9074)
    assert not entry_covers("22/tcp", 6478)
    assert postgres_ports('LISTEN 0 200 0.0.0.0:6478 0.0.0.0:* users:(("postgres",pid=1,fd=6))\n'
                          'LISTEN 0 100 *:9074 *:* users:(("java",pid=2,fd=9))\n') == [6478]
    conf = ("server {\n listen 443 ssl;\n server_name acorn.transasim.com;\n"
            " location /api/ { proxy_pass http://127.0.0.1:9074; }\n location /management/ { deny all; }\n}\n"
            "server {\n listen 80;\n server_name acorn.transasim.com;\n return 301 https://$host$request_uri;\n}\n"
            "server {\n listen 80;\n server_name api.example.com;\n location / { proxy_pass http://127.0.0.1:9060; }\n}\n")
    blocks = server_blocks(conf)
    assert len(blocks) == 3, blocks
    assert names_of(blocks[0]) == ["acorn.transasim.com"] and management_denied(blocks[0])
    assert not management_denied(blocks[2])
    assert [bool(http_only_backend(b)) for b in blocks] == [False, False, True]
    h = schema_hashes([("t", "b", "integer", "NO"), ("t", "a", "character varying(50)", "YES")],
                      [("t", "t_check", "CHECK (b > 0)")])
    assert h["tables"]["t"] == sha("a character varying(50) null=YES\nb integer null=NO", 8)
    assert list(h["checks"]) == ["t.t_check"]
    six = schema_hashes([("t", "at", "timestamp(6) without time zone", "YES"), ("t", "d", "time(6) with time zone", "NO")], [])
    plain = schema_hashes([("t", "at", "timestamp without time zone", "YES"), ("t", "d", "time with time zone", "NO")], [])
    assert six == plain, (six, plain)
    assert schema_hashes([("t", "at", "timestamp(3) without time zone", "YES")], []) != plain
    assert host_of("https://Acorn.example.com:8443/x?y") == "acorn.example.com" and host_of("") is None
    print("selftest ok")


# ---- the check ----------------------------------------------------------------

def main(SLUG, DIR, DB, PGPORT, PORT, DOMAIN, EXPECT, PUBLIC_IP, GOOGLE_CLIENT, STRIPE_ACCOUNT):
    out = {}
    host = socket.gethostname()
    out["hostname"] = host  # first field: Studio refuses a report from the wrong box on it
    out["schema_version"] = SCHEMA_VERSION
    out["script_version"] = SCRIPT_VERSION
    out["generated_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out["hostname_match"] = host == EXPECT
    out["slug"] = SLUG

    # --- process / port / health
    _, ss_out, _ = sh(["ss", "-tlnpH"])
    out["port_listening"] = bool(re.search(rf"[:\]]{re.escape(PORT)}\s", ss_out))
    m = re.search(rf"[:\]]{re.escape(PORT)}\s.*pid=(\d+)", ss_out)
    pid = m.group(1) if m else None
    out["pg_ports_listening"] = postgres_ports(ss_out)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    def http_status(url, follow=True):
        try:
            handlers = [urllib.request.HTTPSHandler(context=ssl.create_default_context())]
            if not follow:
                handlers.append(NoRedirect())
            req = urllib.request.Request(url, headers={"User-Agent": "spc-check"})
            with urllib.request.build_opener(*handlers).open(req, timeout=8) as r:
                return r.status, '"status":"UP"' in r.read(4096).decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, False
        except Exception:
            return 0, False

    out["health_local_status"], out["health_local_up"] = http_status(f"http://127.0.0.1:{PORT}/management/health")
    pub_status, _ = http_status(f"https://{DOMAIN}/management/health")
    plain_status, _ = http_status(f"http://{DOMAIN}/management/health", follow=False)
    out["management_public_status"] = pub_status
    out["management_public_exposed"] = pub_status == 200 or plain_status == 200

    # --- jar
    cmdline = ""
    if pid:
        try:
            cmdline = open(f"/proc/{pid}/cmdline").read().replace("\0", " ")
        except OSError:
            pass
    jm = re.search(r"-jar\s+(\S+\.jar)", cmdline)
    jar = jm.group(1) if jm else (sorted(glob.glob(f"{DIR}/lib/*.jar")) or [None])[0]
    out["jar_name"] = os.path.basename(jar) if jar else None
    out["jar_version"] = None
    out["jar_sha256_16"] = None
    if jar and os.path.exists(jar):
        try:
            mf = zipfile.ZipFile(jar).read("META-INF/MANIFEST.MF").decode()
            v = re.search(r"Implementation-Version:\s*(\S+)", mf)
            out["jar_version"] = v.group(1) if v else None
        except Exception:
            pass
        h = hashlib.sha256()
        with open(jar, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        out["jar_sha256_16"] = h.hexdigest()[:16]
    out["running_jar_from_dir"] = bool(jar and jar.startswith(DIR.rstrip("/") + "/"))
    out["liquibase_disabled_on_cmdline"] = "--spring.liquibase.enabled=false" in cmdline

    # --- layout, APP_NAME, restart method
    out["layout_missing"] = [d for d in ("bin", "conf", "lib", "logs", "temp") if not os.path.isdir(f"{DIR}/{d}")]
    names, scripts = {}, []
    for s in ("startup.sh", "shutdown.sh"):
        p = f"{DIR}/bin/{s}"
        if os.path.exists(p):
            scripts.append(p)
            mm = re.search(r'^APP_NAME="?([^"\n]+)"?', open(p).read(), re.M)
            names[s] = mm.group(1) if mm else None
    out["scripts_executable"] = all(os.access(p, os.X_OK) for p in scripts) if scripts else None
    dirname = os.path.basename(DIR.rstrip("/"))
    out["app_name_values_consistent"] = bool(names) and len(set(names.values())) == 1 and dirname in names.values()
    _, unit, _ = sh(["systemctl", "show", "-p", "FragmentPath,MainPID,ActiveState", f"{SLUG}.service"])
    unit_path = re.search(r"FragmentPath=(\S*)", unit)
    has_unit = bool(unit_path and unit_path.group(1))
    main_pid = re.search(r"MainPID=(\d+)", unit)
    out["restart_method"] = ("systemd" if has_unit and main_pid and main_pid.group(1) == pid
                             else "startup.sh" if names else "unknown")
    _, enabled, _ = sh(["systemctl", "is-enabled", f"{SLUG}.service"])
    out["unit_enabled"] = has_unit and enabled.strip() == "enabled"
    pidfiles = glob.glob(f"{DIR}/temp/*.pid")
    out["pidfile_matches_process"] = bool(pidfiles and pid and open(pidfiles[0]).read().strip() == pid)

    # --- config
    def effective(conf_dir):
        vals, present = {}, set()
        for f in ("application.yml", "application-prod.yml"):
            p = os.path.join(conf_dir, f)
            if not os.path.exists(p):
                continue
            for path, v, commented, _ in ymlmap.parse(p):
                if not commented:
                    k = ymlmap.norm_path(path)
                    vals[k] = v
                    present.add(k)
        return vals, present

    conf = f"{DIR}/conf"
    try:
        out["conf_dir_mode"] = oct(stat.S_IMODE(os.stat(conf).st_mode))[2:]
    except OSError:
        out["conf_dir_mode"] = None
    out["conf_world_readable"] = any(world_readable(p) for p in glob.glob(f"{conf}/*") if os.path.isfile(p))
    vals, present = effective(conf)
    REQUIRED = ["server.port", "spring.datasource.url", "spring.datasource.username", "spring.datasource.password",
                "spring.jpa.hibernate.ddl-auto", "spring.mail.host", "spring.mail.password", "jhipster.mail.from",
                "jhipster.mail.base-url", "jhipster.security.authentication.jwt.base64-secret",
                "sabily.api.auth.baseUrl", "sabily.api.auth.login", "sabily.api.auth.password", "sabily.api.auth.cosRef",
                "sabily.api.auth.nvmoRef", "sabily.transatel.sftp.host", "sabily.transatel.sftp.password",
                "sabily.transatel.sftp.local-path", "sabily.stripe.secret-key", "sabily.stripe.success-url",
                "sabily.stripe.cancel-url", "sabily.spc-name", "google.recaptcha.project-id", "google.recaptcha.keys.web",
                "sabily.social-login.google.client-ids[0]", "sabily.social-login.apple.client-ids[0]"]
    out["config_files_present"] = [f for f in ("application.yml", "application-prod.yml") if os.path.exists(f"{conf}/{f}")]
    out["config_leaf_count"] = len(present)
    out["config_required_missing"] = [k.replace("password", "pw") for k in REQUIRED if not vals.get(k)]
    out["config_pending_count"] = sum(1 for v in vals.values() if (v or "").startswith("PENDING_"))
    out["config_port_matches_arg"] = vals.get("server.port") == PORT
    dsurl = (vals.get("spring.datasource.url") or "").split("?")[0]
    out["config_db_matches_arg"] = dsurl.endswith("/" + DB) and f":{PGPORT}/" in dsurl
    sk = vals.get("sabily.stripe.secret-key") or ""
    out["stripe_key_mode"] = ("live" if sk.startswith("sk_live_") else "test" if sk.startswith("sk_test_")
                              else "pending" if sk.startswith("PENDING_") else "missing" if not sk else "other")
    out["stripe_webhook_secret_key_present"] = any("webhook" in k.lower() for k in present)
    th = host_of(vals.get("sabily.api.auth.baseUrl")) or ""
    out["transatel_host_class"] = ("sandbox" if re.search(r"sandbox|test|preprod|staging|uat", th) else
                                   "production" if th == "api.transatel.com" else "missing" if not th else "other")
    out["ddl_auto"] = vals.get("spring.jpa.hibernate.ddl-auto")
    lq = vals.get("spring.liquibase.enabled")
    out["liquibase_mode"] = ("disabled_cmdline" if out["liquibase_disabled_on_cmdline"]
                             else "disabled_config" if lq == "false" else "enabled_or_default")
    jwt = vals.get("jhipster.security.authentication.jwt.base64-secret") or ""
    out["jwt_is_known_template_default"] = jwt.startswith("ZjljZjQ1")
    out["cors_allows_any_origin"] = (vals.get("jhipster.cors.allowed-origins") or "").strip() == "*"
    out["logging_keys_ok"] = any(k.startswith("logging.level.com.tamarisoft.sabily") for k in present)
    sftp_path = vals.get("sabily.transatel.sftp.local-path") or ""
    out["sftp_path_in_dir"] = sftp_path.startswith(DIR.rstrip("/") + "/") if sftp_path else None

    # Only hosts and a domain: an address would trip Studio's redactor.
    mail_from = vals.get("jhipster.mail.from") or ""
    urls = {"mail_base_url": vals.get("jhipster.mail.base-url"), "stripe_success_url": vals.get("sabily.stripe.success-url"),
            "stripe_cancel_url": vals.get("sabily.stripe.cancel-url")}
    out["config_values"] = {
        "mail_base_host": host_of(urls["mail_base_url"]),
        "stripe_success_host": host_of(urls["stripe_success_url"]),
        "stripe_cancel_host": host_of(urls["stripe_cancel_url"]),
        "mail_from_domain": mail_from.rsplit("@", 1)[-1].lower() if "@" in mail_from else None,
        "spc_name": vals.get("sabily.spc-name"),
        "log_file": vals.get("logging.file.name"),
    }

    my_ip = PUBLIC_IP or None
    if not my_ip:
        _, route, _ = sh(["ip", "-4", "route", "get", "1.1.1.1"])
        rm = re.search(r"\bsrc\s+(\S+)", route)
        my_ip = rm.group(1) if rm else None

    def resolves_here(h):
        if not h or not my_ip:
            return None
        try:
            return my_ip in {ai[4][0] for ai in socket.getaddrinfo(h, None, socket.AF_INET)}
        except Exception:
            return False

    out["url_host_resolves_to_this_box"] = {k: resolves_here(host_of(u)) for k, u in urls.items()}

    # Values left from the template or copied from another backend on this box: key names only.
    others_dirs = [d for d in glob.glob("/apps/*") if os.path.isdir(f"{d}/conf") and os.path.realpath(d) != os.path.realpath(DIR)]
    mine = re.sub(r"-backend$", "", dirname).lower()
    foreign = {re.sub(r"-backend$", "", os.path.basename(d)).lower() for d in others_dirs} | {"sabily"}
    foreign.discard(mine)
    left = []
    for k in ("jhipster.mail.base-url", "jhipster.mail.from", "sabily.stripe.success-url", "sabily.stripe.cancel-url",
              "logging.file.name", "sabily.transatel.sftp.local-path", "sabily.spc-name"):
        v = (vals.get(k) or "").lower()
        if "my-server-url-to-change" in v or any(f and f in v for f in foreign):
            left.append(k)
    for f in ("application.yml", "application-prod.yml"):
        p = os.path.join(conf, f)
        if os.path.exists(p):
            left += [f"{k} (key: #)".replace("password", "pw") for k in ymlmap.hash_nulls(p)]
    out["template_placeholder_left"] = left

    GROUPS = {"jwt": ["jhipster.security.authentication.jwt.base64-secret"],
              "stripe": ["sabily.stripe.secret-key"], "mail_pw": ["spring.mail.password"],
              "transatel_login_pw": ["sabily.api.auth.login", "sabily.api.auth.password"],
              "sftp_pw": ["sabily.transatel.sftp.password"],
              "db_pw": ["spring.datasource.password"],
              "recaptcha": ["google.recaptcha.project-id", "google.recaptcha.keys.web",
                            "google.recaptcha.keys.android", "google.recaptcha.keys.ios"]}
    others = {}
    for d in others_dirs:
        if os.path.exists(f"{d}/conf/application-prod.yml"):
            others[os.path.basename(d)] = effective(f"{d}/conf")[0]
    shared = {}
    for g, keys in GROUPS.items():
        me = tuple(vals.get(k) for k in keys)
        if all(not x or x.startswith("PENDING_") for x in me):
            shared[g] = "n/a"
            continue
        shared[g] = sorted(o for o, ov in others.items() if tuple(ov.get(k) for k in keys) == me)
    out["secret_shared_with"] = shared

    def gac_file(d):
        p = f"{d}/bin/startup.sh"
        g = re.search(r'GOOGLE_APPLICATION_CREDENTIALS="?([^"\n]+)"?', open(p).read()) if os.path.exists(p) else None
        f = g.group(1).replace("$CONF_DIR", f"{d}/conf") if g else None
        return f if f and os.path.exists(f) else None

    my_gac = gac_file(DIR)
    out["gcp_credentials_file_exists"] = my_gac is not None
    my_gac_hash = sha(open(my_gac, "rb").read(), 64) if my_gac else None
    out["gcp_credentials_shared_with"] = sorted(
        os.path.basename(d) for d in others_dirs
        if my_gac_hash and gac_file(d) and sha(open(gac_file(d), "rb").read(), 64) == my_gac_hash)
    google_ids = [v for k, v in vals.items() if k.startswith("sabily.social-login.google.client-ids[")]
    out["google_client_listed"] = (GOOGLE_CLIENT in google_ids) if GOOGLE_CLIENT else None

    out["stripe_account_ok"] = None
    out["stripe_charges_enabled"] = None
    if STRIPE_ACCOUNT == "1" and sk.startswith("sk_"):
        try:
            req = urllib.request.Request("https://api.stripe.com/v1/account", headers={"Authorization": f"Bearer {sk}"})
            with urllib.request.urlopen(req, timeout=10, context=ssl.create_default_context()) as r:
                acct = json.loads(r.read().decode())
            out["stripe_account_ok"] = str(acct.get("id", "")).startswith("acct_")
            out["stripe_charges_enabled"] = acct.get("charges_enabled") is True
        except Exception:
            out["stripe_account_ok"] = False

    # --- database
    def psql(sql, db=DB, sep=None):
        cmd = ["sudo", "-u", "postgres", "psql", "-p", PGPORT, "-d", db, "-X", "-qtA"]
        if sep:
            cmd += ["-F", sep]
        rc, o, e = sh(cmd + ["-c", sql])
        return o.strip() if rc == 0 else None

    TABLES = ["jhi_authority", "jhi_user", "jhi_user_authority", "country", "currency", "network", "operator", "area",
              "pack", "price", "allowance", "subscription_config", "display_config", "subscriber", "esim_inventory",
              "payment", "transaction", "databasechangelog"]
    for k in ("db_table_count", "anonymous_user_exists", "anonymous_subscriber_exists", "anonymous_subscriber_user_valid",
              "payment_method_check_present", "db_role", "db_role_exists", "db_role_create_on_public",
              "db_role_owns_tables", "schema"):
        out[k] = None
    out["ref_table_counts"] = {}
    out["authorities"] = []
    out["db_reachable"] = psql("select 1") == "1"
    if out["db_reachable"]:
        out["db_table_count"] = int(psql("select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'"))
        counts = {}
        for t in TABLES:
            r = psql(f"select count(*) from public.{t}") if psql(f"select to_regclass('public.{t}') is not null") == "t" else None
            counts[t] = int(r) if r not in (None, "") else None
        out["ref_table_counts"] = counts
        out["authorities"] = sorted(x for x in (psql("select name from jhi_authority") or "").split("\n") if x)
        out["anonymous_user_exists"] = psql("select exists(select 1 from jhi_user where lower(login)='anonymous' or lower(email)='anonymous@anonymous.com')") == "t"
        out["anonymous_subscriber_exists"] = psql("select exists(select 1 from subscriber where lower(email)='anonymous@anonymous.com')") == "t"
        out["anonymous_subscriber_user_valid"] = psql("select exists(select 1 from subscriber s join jhi_user u on u.id = s.user_id where lower(s.email)='anonymous@anonymous.com')") == "t"
        out["payment_method_check_present"] = psql("select exists(select 1 from pg_constraint where conname='payment_method_check')") == "t"
        role = vals.get("spring.datasource.username") or ""
        if re.fullmatch(r"[A-Za-z0-9_]+", role):
            out["db_role"] = role
            out["db_role_exists"] = psql(f"select exists(select 1 from pg_roles where rolname='{role}')") == "t"
            if out["db_role_exists"]:
                out["db_role_create_on_public"] = psql(f"select has_schema_privilege('{role}','public','CREATE')") == "t"
                out["db_role_owns_tables"] = int(psql(f"select count(*) from pg_tables where schemaname='public' and tableowner='{role}'") or 0)
        cols = psql("select c.relname, a.attname, format_type(a.atttypid, a.atttypmod), "
                    "case when a.attnotnull then 'NO' else 'YES' end from pg_attribute a "
                    "join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace "
                    "where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped", sep="\t")
        checks = psql("select c.relname, con.conname, pg_get_constraintdef(con.oid) from pg_constraint con "
                      "join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace "
                      "where n.nspname = 'public' and con.contype = 'c'", sep="\t")
        if cols is not None and checks is not None:
            out["schema"] = schema_hashes([tuple(l.split("\t")) for l in cols.split("\n") if l.count("\t") == 3],
                                          [tuple(l.split("\t", 2)) for l in checks.split("\n") if l.count("\t") >= 2])
    listen = psql("show listen_addresses", db="postgres") or ""
    out["pg_listen_all"] = "*" in listen or "0.0.0.0" in listen
    _, ufw, _ = sh(["ufw", "status"])
    ufw_active, ufw_entries = ufw_open(ufw)
    out["ufw_pg_open_to_world"] = (not ufw_active) or any(entry_covers(e, int(PGPORT)) for e in ufw_entries)

    # --- nginx / cert / dns
    rc, nT, nErr = sh(["nginx", "-T"])
    blocks = server_blocks(nT)
    mine_blocks = [b for b in blocks if any(re.search(rf"(^|\s){re.escape(DOMAIN)}(\s|$)", n) for n in names_of(b))]
    out["nginx_test_ok"] = rc == 0
    out["nginx_server_name_present"] = bool(mine_blocks)
    out["nginx_conflicting_server_name"] = bool(re.search(rf"conflicting server name \"{re.escape(DOMAIN)}\"", nErr))
    out["nginx_proxies_to_port"] = any(f"127.0.0.1:{PORT}" in b for b in mine_blocks)
    out["nginx_management_denied"] = any(management_denied(b) for b in mine_blocks if "ssl" in b or "443" in b)
    rc, certs, _ = sh(["certbot", "certificates"], timeout=60)
    days = None
    for block in certs.split("Certificate Name:")[1:]:
        if re.search(rf"Domains:.*\b{re.escape(DOMAIN)}\b", block):
            dm = re.search(r"VALID: (\d+) day", block)
            days = int(dm.group(1)) if dm else (0 if "EXPIRED" in block else None)
    out["cert_days_left"] = days
    try:
        a = sorted({ai[4][0] for ai in socket.getaddrinfo(DOMAIN, None, socket.AF_INET)})
    except Exception:
        a = []
    out["dns_a_count"] = len(a)
    out["dns_match"] = bool(my_ip and my_ip in a)

    # --- transatel health from logs
    logtxt = ""
    if out["restart_method"] == "systemd":
        _, logtxt, _ = sh(["journalctl", "-u", f"{SLUG}.service", "-q", "-o", "cat", "--since", "-2d", "--grep", "APIs Transatel"], timeout=120)
    if not logtxt.strip():
        # A unit that logs to a file (logging.file.name) leaves the journal empty: read that file,
        # else the newest one in DIR/logs.
        cfg_log = out["config_values"].get("log_file")
        files = [cfg_log] if cfg_log and os.path.isfile(cfg_log) else             sorted(glob.glob(f"{DIR}/logs/*.log"), key=os.path.getmtime, reverse=True)[:1]
        for lf in files:
            _, logtxt, _ = sh(["grep", "APIs Transatel", lf])
    hits = re.findall(r"\((\d+/\d+)\)", logtxt)
    out["transatel_last_health"] = hits[-1] if hits else "unknown"
    ts = re.findall(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d).*APIs Transatel", logtxt, re.M)
    out["transatel_last_health_at"] = ts[-1] if ts else None

    # --- the server, once per box (Studio reads it from any backend's report)
    dumps = []
    for top in ("/apps", "/opt", "/root", "/home", "/var/backups"):
        for dirpath, dirs, files in os.walk(top):
            if dirpath.count("/") - top.count("/") >= 4:
                dirs[:] = []
            for f in files:
                if re.search(r"\.(dump|sql|sql\.gz|tar\.gz|tgz|backup)$", f) and world_readable(os.path.join(dirpath, f)):
                    dumps.append(f)
    _, ps_out, _ = sh(["ps", "-eo", "args"])
    running = {m.group(1) for m in re.finditer(r"-jar\s+(/apps/[^/\s]+)/", ps_out)}
    own_conf = re.compile(r"^(" + "|".join(re.escape(d) for d in running) + r")/conf/application[^/]*\.yml$") if running else None
    live_rc, live, _ = sh(["grep", "-rlI", "-e", "sk_" + "live_", "/apps", "/opt", "/root", "/home", "/etc"], timeout=240)
    stray = [p for p in live.splitlines()
             if p and not p.startswith(HERE + "/") and not (own_conf and own_conf.match(p))]
    rules = psql("select count(*) from pg_hba_file_rules where type like 'host%' and error is null and "
                 "coalesce(address, 'all') not like '127.%' and coalesce(address, 'all') not in ('::1', 'localhost', 'samehost')",
                 db="postgres")
    crons = ""
    for p in glob.glob("/etc/cron.d/*") + glob.glob("/etc/cron.daily/*") + glob.glob("/var/spool/cron/crontabs/*") + ["/etc/crontab"]:
        try:
            crons += open(p, errors="replace").read()
        except OSError:
            pass
    _, timers, _ = sh(["systemctl", "list-timers", "--all", "--no-pager"])
    _, certbot_timer, _ = sh(["systemctl", "is-active", "certbot.timer"])
    out["server"] = {
        "ufw_active": ufw_active,
        "ufw_open_ports": ufw_entries,
        "pg_hba_external_rules": int(rules) if rules and rules.isdigit() else None,
        "http_only_backend_vhosts": sorted({n.strip() for b in blocks if http_only_backend(b) for n in names_of(b)}),
        "world_readable_dumps": len(dumps),
        "stray_live_stripe_files": None if live_rc == 99 else len(stray),
        "certbot_timer_active": certbot_timer.strip() == "active",
        "backups_scheduled": bool(re.search(r"pg_dump|pg_basebackup|pgbackrest|barman", crons + timers)),
    }

    text = json.dumps(out, ensure_ascii=False)
    if MARKERS.search(text):
        print(json.dumps({"hostname": host, "error": "output withheld: secret-like marker detected"}))
        sys.exit(3)
    print(text)


if sys.argv[2] == "--selftest":
    selftest()
else:
    main(*sys.argv[2:12])
PY
