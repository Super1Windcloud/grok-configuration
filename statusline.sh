#!/opt/homebrew/bin/python3
"""Grok Build custom statusline - High performance asynchronous statusline."""

import fcntl
import json
import os
import re
import sys
import time
import unicodedata

HOME = os.path.expanduser("~")


def text(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (int, float, bool)):
        return str(value)
    return ""


def pick(data, *paths):
    for path in paths:
        cur = data
        ok = True
        for key in path.split("."):
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            else:
                ok = False
                break
        if ok and cur not in (None, ""):
            return cur
    return None


def token_number(value):
    if isinstance(value, bool) or value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


def format_tokens(n):
    if n is None or n < 0:
        return ""
    if n >= 1_000_000:
        val = n / 1_000_000
        return f"{val:.1f}M".replace(".0M", "M")
    if n >= 1_000:
        val = n / 1_000
        return f"{val:.0f}k" if val >= 10 else f"{val:.1f}k".replace(".0k", "k")
    return str(int(n))


def context_info(data):
    window = pick(data, "context_window")
    if not isinstance(window, dict):
        window = {}

    used_pct = window.get("used_percentage")
    rem_pct = window.get("remaining_percentage")
    tokens = token_number(window.get("context_tokens"))
    size = token_number(window.get("context_window_size"))

    if used_pct is None:
        if rem_pct is not None:
            try:
                used_pct = 100 - int(rem_pct)
            except (ValueError, TypeError):
                pass
        elif tokens is not None and size is not None and size > 0:
            used_pct = int(round((tokens / size) * 100))

    if used_pct is not None:
        try:
            used_pct = int(round(float(used_pct)))
        except (ValueError, TypeError):
            used_pct = None

    pct_str = str(used_pct) if used_pct is not None else ""
    tok_detail = ""
    if tokens is not None and tokens > 0:
        tok_str = format_tokens(tokens)
        if size is not None and size > 0:
            tok_detail = f"{tok_str}/{format_tokens(size)}"
        else:
            tok_detail = tok_str

    return pct_str, tok_detail


def ctx_color(pct_str):
    try:
        pct = int(pct_str)
    except (ValueError, TypeError):
        return "2"
    if pct >= 90:
        return "1;31"  # Bold Red
    if pct >= 75:
        return "1;33"  # Bold Yellow
    return "2"        # Dim


def git_info(cwd, data=None):
    if not cwd:
        return "", None

    # Grok workspace hints
    repo_root_hint = pick(data or {}, "workspace.repo_root")
    branch_hint = pick(data or {}, "workspace.branch", "worktree.branch")
    wt_hint = pick(data or {}, "worktree.name", "workspace.git_worktree")

    cur = os.path.abspath(cwd)
    git_dir = None
    git_root = repo_root_hint if repo_root_hint and os.path.isdir(repo_root_hint) else None

    if not git_root:
        for _ in range(8):
            check_path = os.path.join(cur, ".git")
            if os.path.isdir(check_path):
                git_dir = check_path
                git_root = cur
                break
            elif os.path.isfile(check_path):
                try:
                    with open(check_path, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read().strip()
                    if content.startswith("gitdir:"):
                        real_git = content[7:].strip()
                        if not os.path.isabs(real_git):
                            real_git = os.path.normpath(os.path.join(cur, real_git))
                        git_dir = real_git
                        git_root = cur
                        break
                except Exception:
                    pass
            parent = os.path.dirname(cur)
            if parent == cur:
                break
            cur = parent
    else:
        check_path = os.path.join(git_root, ".git")
        if os.path.isdir(check_path):
            git_dir = check_path
        elif os.path.isfile(check_path):
            try:
                with open(check_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read().strip()
                if content.startswith("gitdir:"):
                    real_git = content[7:].strip()
                    if not os.path.isabs(real_git):
                        real_git = os.path.normpath(os.path.join(git_root, real_git))
                    git_dir = real_git
            except Exception:
                pass

    if not git_root:
        return "", None

    branch = branch_hint or ""
    if not branch and git_dir and os.path.isdir(git_dir):
        head_file = os.path.join(git_dir, "HEAD")
        if os.path.isfile(head_file):
            try:
                with open(head_file, "r", encoding="utf-8", errors="ignore") as f:
                    c = f.read().strip()
                if c.startswith("ref: refs/heads/"):
                    branch = c[16:]
                elif c:
                    branch = c[:7]
            except Exception:
                pass

    if not branch:
        try:
            import subprocess
            out = subprocess.check_output(
                ["git", "-c", "gc.auto=0", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                stderr=subprocess.DEVNULL,
                timeout=0.08,
            )
            b = out.decode("utf-8", "replace").strip()
            if b == "HEAD":
                out_short = subprocess.check_output(
                    ["git", "-c", "gc.auto=0", "-C", cwd, "rev-parse", "--short", "HEAD"],
                    stderr=subprocess.DEVNULL,
                    timeout=0.08,
                )
                branch = out_short.decode("utf-8", "replace").strip()
            else:
                branch = b
        except Exception:
            pass

    if not branch:
        return "", git_root

    state = ""
    if git_dir and os.path.isdir(git_dir):
        if os.path.isdir(os.path.join(git_dir, "rebase-merge")) or os.path.isdir(os.path.join(git_dir, "rebase-apply")):
            state = "[rebase]"
        elif os.path.isfile(os.path.join(git_dir, "MERGE_HEAD")):
            state = "[merge]"
        elif os.path.isfile(os.path.join(git_dir, "CHERRY_PICK_HEAD")):
            state = "[cherry-pick]"

    wt_str = f"[wt:{wt_hint}]" if wt_hint and wt_hint is not True else ""

    # Non-blocking async cached dirty check
    dirty = ""
    try:
        h = abs(hash(git_root)) % 1000000
        cache_file = f"/tmp/grok_git_{h}.cache"
        now = time.time()
        cache_mtime = 0
        if os.path.isfile(cache_file):
            try:
                with open(cache_file, "r") as cf:
                    parts = cf.read().split(":")
                    if len(parts) == 2:
                        cache_mtime = float(parts[0])
                        dirty = parts[1]
            except Exception:
                pass

        if now - cache_mtime > 4.0:
            import subprocess
            updater = (
                f"import time, subprocess;"
                f"res = subprocess.run(['git', '-c', 'gc.auto=0', '-C', '{cwd}', 'diff-files', '--quiet'], "
                f"stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);"
                f"d = '*' if res.returncode != 0 else '';"
                f"open('{cache_file}', 'w').write(f'{{time.time()}}:{{d}}')"
            )
            subprocess.Popen(["python3", "-c", updater], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

    full_branch = f"{branch}{dirty}{state}{wt_str}"
    return full_branch, git_root


def fmt_duration(seconds):
    if seconds is None or seconds < 0:
        return ""
    total = int(round(seconds))
    if total < 1:
        return "0s"
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h{minutes:02d}m"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def turn_cache_path():
    override = os.environ.get("GROK_STATUSLINE_TURN_CACHE")
    if override:
        return override
    return os.path.join(HOME, ".grok", "statusline-turn.json")


def mutate_turn_cache(mutator):
    """Read-modify-write the per-session turn clock. Returns False if the file could not be locked."""
    path = turn_cache_path()
    try:
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(path, "a+", encoding="utf-8") as handle:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            except Exception:
                pass
            handle.seek(0)
            raw = handle.read()
            try:
                state = json.loads(raw) if raw.strip() else {"sessions": {}}
            except Exception:
                state = {"sessions": {}}
            if not isinstance(state, dict) or not isinstance(state.get("sessions"), dict):
                state = {"sessions": {}}
            dirty = bool(mutator(state))
            if dirty:
                sessions = state["sessions"]
                if len(sessions) > 16:
                    ranked = sorted(
                        sessions.items(),
                        key=lambda item: item[1].get("updated_ms", 0) if isinstance(item[1], dict) else 0,
                    )
                    for key, _ in ranked[: len(sessions) - 16]:
                        sessions.pop(key, None)
                handle.seek(0)
                handle.truncate()
                json.dump(state, handle, separators=(",", ":"))
                handle.flush()
        return True
    except Exception:
        return False


def _duration_from_state(state, data, now_ms):
    """Per-prompt clock.

    cost.total_duration_ms is session age since this process attached, so it
    must not drive took. Each new prompt_id (or a new turn.started_at_ms)
    restarts the clock; the value freezes when the turn leaves the payload.
    """
    sessions = state.setdefault("sessions", {})
    session_id = text(pick(data, "session_id")) or "_"
    rec = sessions.get(session_id)
    if not isinstance(rec, dict):
        rec = {}
    started_at = token_number(pick(data, "turn.started_at_ms"))
    prompt_id = text(pick(data, "prompt_id"))
    dirty = False

    if started_at is not None and started_at > 0:
        turn_key = prompt_id or f"start:{int(started_at)}"
        same_turn = rec.get("phase") == "running" and rec.get("turn_key") == turn_key
        if same_turn:
            anchor = float(rec.get("anchor_ms") or started_at)
        else:
            anchor = float(started_at)
            prev_key = text(rec.get("turn_key"))
            prev_payload = token_number(rec.get("payload_started_at_ms"))
            if prev_key and prev_key != turn_key and prev_payload is not None and abs(prev_payload - float(started_at)) < 1:
                anchor = float(now_ms)
            rec = {
                "phase": "running",
                "turn_key": turn_key,
                "anchor_ms": anchor,
                "payload_started_at_ms": float(started_at),
                "took_ms": None,
                "updated_ms": now_ms,
            }
            sessions[session_id] = rec
            dirty = True
        elapsed = max(0.0, (float(now_ms) - anchor) / 1000.0)
        return f"running:{fmt_duration(elapsed)}", dirty

    if rec.get("phase") == "running":
        anchor = token_number(rec.get("anchor_ms"))
        took_ms = max(0.0, float(now_ms) - float(anchor)) if anchor is not None else None
        sessions[session_id] = {
            "phase": "idle",
            "turn_key": rec.get("turn_key") or "",
            "anchor_ms": None,
            "payload_started_at_ms": rec.get("payload_started_at_ms"),
            "took_ms": took_ms,
            "updated_ms": now_ms,
        }
        if took_ms is None:
            return "", True
        return f"took:{fmt_duration(took_ms / 1000.0)}", True

    took_ms = token_number(rec.get("took_ms"))
    if took_ms is not None and took_ms >= 0 and rec.get("phase") == "idle":
        return f"took:{fmt_duration(took_ms / 1000.0)}", False
    return "", False


def duration_info(data, now_ms=None):
    if now_ms is None:
        now_ms = time.time() * 1000.0
    box = {"text": ""}

    def mutate(state):
        text_value, dirty = _duration_from_state(state, data, now_ms)
        box["text"] = text_value
        return dirty

    if not mutate_turn_cache(mutate):
        text_value, _dirty = _duration_from_state({"sessions": {}}, data, now_ms)
        return text_value
    return box["text"]


def cost_info(data):
    cost_usd = pick(data, "cost.total_cost_usd")
    if isinstance(cost_usd, (int, float)) and cost_usd > 0:
        if cost_usd >= 0.01:
            return f"${cost_usd:.2f}"
        return f"${cost_usd:.3f}"
    return ""


WEEK_CACHE = os.path.join(HOME, ".grok", "statusline-week.json")
WEEK_TTL = 120
BILLING_URL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"


def format_week(pct):
    if pct is None:
        return ""
    try:
        shown = int(round(float(pct)))
    except (TypeError, ValueError):
        return ""
    if shown < 0:
        return ""
    if shown > 999:
        shown = 999
    return f"week:{shown}%"


def week_percent_from_body(body):
    if not isinstance(body, dict):
        return None
    nested = body.get("config")
    if isinstance(nested, dict):
        body = nested
    products = body.get("productUsage")
    if isinstance(products, list):
        for item in products:
            if isinstance(item, dict) and item.get("product") == "GrokBuild":
                pct = token_number(item.get("usagePercent"))
                if pct is not None:
                    return pct
    return token_number(body.get("creditUsagePercent"))


def read_week_cache():
    try:
        with open(WEEK_CACHE, "r", encoding="utf-8") as handle:
            cached = json.load(handle)
        pct = token_number(cached.get("percent"))
        ts = token_number(cached.get("ts"))
        if pct is None or ts is None:
            return None, None
        return pct, ts
    except Exception:
        return None, None


def write_week_cache(pct):
    try:
        os.makedirs(os.path.dirname(WEEK_CACHE), exist_ok=True)
        tmp = WEEK_CACHE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump({"ts": time.time(), "percent": pct}, handle)
        os.replace(tmp, WEEK_CACHE)
    except Exception:
        pass


def auth_token():
    path = os.path.join(HOME, ".grok", "auth.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return ""
    best = ""
    best_exp = ""
    if isinstance(data, dict):
        for entry in data.values():
            if not isinstance(entry, dict):
                continue
            key = entry.get("key") or ""
            exp = str(entry.get("expires_at") or "")
            if key and exp >= best_exp:
                best = key
                best_exp = exp
    return best


def client_version():
    path = os.path.join(HOME, ".grok", "version.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            ver = json.load(handle).get("version")
        if isinstance(ver, str) and ver.strip():
            return ver.strip()
    except Exception:
        pass
    return "1.0.67"


def fetch_week_percent():
    token = auth_token()
    if not token:
        return None
    import urllib.request

    req = urllib.request.Request(
        BILLING_URL,
        headers={
            "Authorization": "Bearer " + token,
            "x-grok-client-version": client_version(),
            "x-grok-client-identifier": "grok-shell",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            body = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        return None
    return week_percent_from_body(body)


def week_quota(data):
    trigger = text(pick(data or {}, "trigger"))
    pct, ts = read_week_cache()
    fresh = ts is not None and (time.time() - ts) < WEEK_TTL
    if trigger == "refresh_interval" or not fresh:
        fetched = fetch_week_percent()
        if fetched is not None:
            pct = fetched
            write_week_cache(pct)
    return format_week(pct)


def smart_cwd(cwd, git_root=None):
    if not cwd:
        return ""
    home = str(HOME)
    path = os.path.abspath(cwd)
    if path == home:
        return "~"
    if git_root and path.startswith(git_root):
        repo_name = os.path.basename(git_root)
        if path == git_root:
            return repo_name
        rel = os.path.relpath(path, git_root)
        parts = [p for p in rel.split(os.sep) if p]
        if len(parts) <= 2:
            return f"{repo_name}/{rel}"
        return f"{repo_name}/…/{parts[-1]}"
    if path.startswith(home + "/"):
        rel = "~/" + path[len(home) + 1:]
    else:
        rel = path
    parts = [p for p in rel.split("/") if p]
    if len(parts) <= 3:
        return rel
    return f"~/…/{parts[-2]}/{parts[-1]}"


def basename_cwd(cwd):
    if not cwd:
        return ""
    home = str(HOME)
    path = cwd.rstrip("/") or cwd
    if path == home:
        return "~"
    parts = [p for p in path.split("/") if p != ""]
    return parts[-1] if parts else path


def ansi(code, value):
    return f"\033[{code}m{value}\033[0m" if value else ""


def visible_width(s):
    if not s:
        return 0
    clean = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", s)
    width = 0
    for ch in clean:
        if unicodedata.east_asian_width(ch) in ("F", "W"):
            width += 2
        else:
            width += 1
    return width


def get_terminal_width():
    try:
        col = int(os.environ.get("COLUMNS", ""))
        if col > 0:
            return col
    except (KeyError, ValueError):
        pass
    try:
        col = os.get_terminal_size(1).columns
        if col > 0:
            return col
    except Exception:
        pass
    try:
        col = os.get_terminal_size(2).columns
        if col > 0:
            return col
    except Exception:
        pass
    try:
        with open("/dev/tty") as tty:
            col = os.get_terminal_size(tty.fileno()).columns
            if col > 0:
                return col
    except Exception:
        pass
    return 0


def align_statusline(left_str, right_str, term_width, fallback_right_str=None):
    if not right_str:
        return left_str
    if not left_str:
        if term_width > 0:
            gap = term_width - visible_width(right_str)
            if gap > 0:
                return (" " * gap) + right_str
        return right_str

    w_left = visible_width(left_str)
    w_right = visible_width(right_str)

    if term_width > 0:
        gap = term_width - w_left - w_right
        if gap >= 1:
            return f"{left_str}{' ' * gap}{right_str}"
        if fallback_right_str and fallback_right_str != right_str:
            w_fb = visible_width(fallback_right_str)
            gap_fb = term_width - w_left - w_fb
            if gap_fb >= 1:
                return f"{left_str}{' ' * gap_fb}{fallback_right_str}"

    return f"{left_str}  {right_str}"


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}

    cwd = text(pick(data, "cwd", "workspace.current_dir"))
    if not cwd:
        try:
            cwd = os.getcwd()
        except Exception:
            cwd = ""

    model = text(pick(data, "model.display_name", "model.id"))
    effort = text(pick(data, "effort.level"))

    left_parts = []
    branch, git_root = git_info(cwd, data)
    if branch:
        left_parts.append(ansi("1;35", f"git:{branch}"))
    if model:
        m_label = model
        if effort:
            m_label += f" ({effort})"
        left_parts.append(ansi("2", m_label))

    ctx_pct, ctx_tok = context_info(data)
    if ctx_pct:
        ctx_label = f"ctx:{ctx_pct}%"
        if ctx_tok:
            ctx_label += f" ({ctx_tok})"
        left_parts.append(ansi(ctx_color(ctx_pct), ctx_label))

    week = week_quota(data)
    if week:
        left_parts.append(ansi(ctx_color(week.split(":")[-1].rstrip("%")), week))

    duration = duration_info(data)
    if duration:
        left_parts.append(ansi("1;32", duration))

    cost = cost_info(data)
    if cost:
        left_parts.append(ansi("2", cost))

    left_str = " ".join(left_parts)

    dir_part = smart_cwd(cwd, git_root=git_root)
    right_str = ansi("1;36", dir_part) if dir_part else ""
    fb_dir = basename_cwd(cwd)
    fallback_right_str = ansi("1;36", fb_dir) if fb_dir else ""

    term_width = get_terminal_width()
    line = align_statusline(
        left_str,
        right_str,
        term_width,
        fallback_right_str=fallback_right_str,
    )
    sys.stdout.write(line + "\n")


if __name__ == "__main__":
    main()
