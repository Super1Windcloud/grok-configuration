#!/opt/homebrew/bin/python3
"""Grok Build custom statusline - High performance asynchronous statusline."""

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


def duration_info(data):
    started_at = pick(data, "turn.started_at_ms")
    if isinstance(started_at, (int, float)) and started_at > 0:
        elapsed = max(0.0, (time.time() * 1000.0 - started_at) / 1000.0)
        return f"running:{fmt_duration(elapsed)}"

    total_ms = pick(data, "cost.total_duration_ms")
    if isinstance(total_ms, (int, float)) and total_ms >= 1000:
        return f"took:{fmt_duration(total_ms / 1000.0)}"

    return ""


def cost_info(data):
    cost_usd = pick(data, "cost.total_cost_usd")
    if isinstance(cost_usd, (int, float)) and cost_usd > 0:
        if cost_usd >= 0.01:
            return f"${cost_usd:.2f}"
        return f"${cost_usd:.3f}"
    return ""


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
    session_name = text(pick(data, "session_name"))

    left_parts = []
    branch, git_root = git_info(cwd, data)
    if branch:
        left_parts.append(ansi("1;35", f"git:{branch}"))
    if session_name:
        left_parts.append(ansi("1;33", session_name))
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
