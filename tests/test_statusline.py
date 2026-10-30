import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

STATUSLINE_PATH = Path(__file__).resolve().parents[1] / "statusline.sh"
loader = importlib.machinery.SourceFileLoader("statusline", str(STATUSLINE_PATH))
spec = importlib.util.spec_from_loader("statusline", loader)
statusline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(statusline)


class TestGrokStatusline(unittest.TestCase):
    def setUp(self):
        cache = tempfile.NamedTemporaryFile(delete=False)
        cache.close()
        self._cache_path = cache.name
        os.environ["GROK_STATUSLINE_TURN_CACHE"] = self._cache_path

    def tearDown(self):
        os.environ.pop("GROK_STATUSLINE_TURN_CACHE", None)
        try:
            os.unlink(self._cache_path)
        except OSError:
            pass

    def test_token_formatting(self):
        self.assertEqual(statusline.format_tokens(500), "500")
        self.assertEqual(statusline.format_tokens(1500), "1.5k")
        self.assertEqual(statusline.format_tokens(24000), "24k")
        self.assertEqual(statusline.format_tokens(1200000), "1.2M")
        self.assertEqual(statusline.format_tokens(0), "0")
        self.assertEqual(statusline.format_tokens(None), "")

    def test_context_info(self):
        # Direct used_percentage
        data = {"context_window": {"used_percentage": 15, "context_tokens": 30000, "context_window_size": 200000}}
        pct, tok = statusline.context_info(data)
        self.assertEqual(pct, "15")
        self.assertEqual(tok, "30k/200k")

        # Calculated from remaining
        data_rem = {"context_window": {"remaining_percentage": 70, "context_tokens": 60000, "context_window_size": 200000}}
        pct, tok = statusline.context_info(data_rem)
        self.assertEqual(pct, "30")

        # Calculated from tokens / size
        data_calc = {"context_window": {"context_tokens": 50000, "context_window_size": 200000}}
        pct, tok = statusline.context_info(data_calc)
        self.assertEqual(pct, "25")

    def test_ctx_color(self):
        self.assertEqual(statusline.ctx_color("15"), "2")
        self.assertEqual(statusline.ctx_color("74"), "2")
        self.assertEqual(statusline.ctx_color("75"), "1;33")
        self.assertEqual(statusline.ctx_color("89"), "1;33")
        self.assertEqual(statusline.ctx_color("90"), "1;31")
        self.assertEqual(statusline.ctx_color("99"), "1;31")

    def test_duration_formatting(self):
        self.assertEqual(statusline.fmt_duration(0.4), "0s")
        self.assertEqual(statusline.fmt_duration(12), "12s")
        self.assertEqual(statusline.fmt_duration(75), "1m15s")
        self.assertEqual(statusline.fmt_duration(3665), "1h01m")
        self.assertEqual(statusline.fmt_duration(None), "")

    def test_duration_info(self):
        now_ms = time.time() * 1000
        running_data = {"session_id": "s", "prompt_id": "p", "turn": {"started_at_ms": now_ms - 5200}}
        self.assertTrue(statusline.duration_info(running_data).startswith("running:"))

        # Session age is not a prompt duration. Without a finished turn there is no took.
        completed_data = {"session_id": "fresh", "cost": {"total_duration_ms": 15000}}
        self.assertEqual(statusline.duration_info(completed_data), "")

    def test_took_restarts_each_prompt(self):
        session = "sess-1"
        t0 = 1_700_000_000_000
        prompt_a = {
            "session_id": session,
            "prompt_id": "prompt-a",
            "turn": {"started_at_ms": t0},
            "cost": {"total_duration_ms": 400000},
        }
        self.assertEqual(statusline.duration_info(prompt_a, now_ms=t0 + 1000), "running:1s")
        self.assertEqual(statusline.duration_info(prompt_a, now_ms=t0 + 5000), "running:5s")

        idle = {"session_id": session, "cost": {"total_duration_ms": 900000}}
        self.assertEqual(statusline.duration_info(idle, now_ms=t0 + 5200), "took:5s")
        # Later refreshes keep the frozen prompt time. Session age must not keep climbing.
        self.assertEqual(statusline.duration_info(idle, now_ms=t0 + 80000), "took:5s")

        t1 = t0 + 90000
        prompt_b = {
            "session_id": session,
            "prompt_id": "prompt-b",
            "turn": {"started_at_ms": t1},
            "cost": {"total_duration_ms": 990000},
        }
        self.assertEqual(statusline.duration_info(prompt_b, now_ms=t1 + 2000), "running:2s")
        self.assertEqual(statusline.duration_info(idle, now_ms=t1 + 9000), "took:9s")
        self.assertEqual(statusline.duration_info({"session_id": "other"}, now_ms=t1 + 9000), "")

    def test_took_restarts_when_started_at_stays_put(self):
        session = "sess-sticky"
        t0 = 1_700_000_000_000
        first = {
            "session_id": session,
            "prompt_id": "prompt-a",
            "turn": {"started_at_ms": t0},
        }
        self.assertEqual(statusline.duration_info(first, now_ms=t0 + 4000), "running:4s")
        idle = {"session_id": session}
        self.assertEqual(statusline.duration_info(idle, now_ms=t0 + 4000), "took:4s")

        second = {
            "session_id": session,
            "prompt_id": "prompt-b",
            "turn": {"started_at_ms": t0},
        }
        seen = t0 + 20000
        self.assertEqual(statusline.duration_info(second, now_ms=seen), "running:0s")
        self.assertEqual(statusline.duration_info(second, now_ms=seen + 3000), "running:3s")
        self.assertEqual(statusline.duration_info(idle, now_ms=seen + 3000), "took:3s")

    def test_week_quota_formatting(self):
        self.assertEqual(statusline.format_week(None), "")
        self.assertEqual(statusline.format_week(0), "week:0%")
        self.assertEqual(statusline.format_week(42.4), "week:42%")
        self.assertEqual(statusline.format_week(42.6), "week:43%")
        self.assertEqual(statusline.format_week(-1), "")
        body = {
            "config": {
                "creditUsagePercent": 10,
                "productUsage": [{"product": "GrokBuild", "usagePercent": 43}],
            }
        }
        self.assertEqual(statusline.week_percent_from_body(body), 43)
        self.assertEqual(statusline.week_percent_from_body({"creditUsagePercent": 7}), 7)
        self.assertEqual(
            statusline.week_percent_from_body({"config": {"creditUsagePercent": 7}}),
            7,
        )
        self.assertIsNone(statusline.week_percent_from_body({}))
        self.assertEqual(statusline.ctx_color("43"), "2")
        self.assertEqual(statusline.ctx_color("90"), "1;31")

    def test_cost_info(self):
        self.assertEqual(statusline.cost_info({"cost": {"total_cost_usd": 0.035}}), "$0.04")
        self.assertEqual(statusline.cost_info({"cost": {"total_cost_usd": 0.005}}), "$0.005")
        self.assertEqual(statusline.cost_info({"cost": {"total_cost_usd": 0}}), "")
        self.assertEqual(statusline.cost_info({}), "")

    def test_smart_cwd(self):
        home = statusline.HOME
        self.assertEqual(statusline.smart_cwd(home), "~")
        self.assertEqual(statusline.smart_cwd(f"{home}/projects/app"), "~/projects/app")
        # In git repo
        repo = f"{home}/my-repo"
        self.assertEqual(statusline.smart_cwd(repo, git_root=repo), "my-repo")
        self.assertEqual(statusline.smart_cwd(f"{repo}/src/components", git_root=repo), "my-repo/src/components")
        self.assertEqual(statusline.smart_cwd(f"{repo}/a/b/c/d", git_root=repo), "my-repo/…/d")

    def test_visible_width(self):
        self.assertEqual(statusline.visible_width("hello"), 5)
        self.assertEqual(statusline.visible_width("\033[1;32mhello\033[0m"), 5)
        # East Asian wide characters (CJK: 2 chars * 2 = 4 + 1 + 4 = 9)
        self.assertEqual(statusline.visible_width("测试"), 4)
        self.assertEqual(statusline.visible_width("\033[1;35m分支:main\033[0m"), 9)

    def test_align_statusline(self):
        left = "left"
        right = "right"
        # Width 20: 4 + gap(11) + 5 = 20
        res = statusline.align_statusline(left, right, 20)
        self.assertEqual(statusline.visible_width(res), 20)
        self.assertTrue(res.startswith("left"))
        self.assertTrue(res.endswith("right"))

        # Fallback when too narrow
        fb_right = "rt"
        res_narrow = statusline.align_statusline("left-long", "right-very-long", 14, fallback_right_str=fb_right)
        self.assertTrue("rt" in res_narrow)

    def test_cli_execution_with_mock_json(self):
        now_ms = int(time.time() * 1000)
        payload = json.dumps({
            "cwd": "/Users/super/super",
            "workspace": {"current_dir": "/Users/super/super", "branch": "main"},
            "model": {"display_name": "Grok 4.7"},
            "effort": {"level": "medium"},
            "context_window": {"used_percentage": 22, "context_tokens": 44000, "context_window_size": 200000},
            "turn": {"started_at_ms": now_ms - 3000},
            "cost": {"total_cost_usd": 0.012}
        })
        p = subprocess.run(
            [str(STATUSLINE_PATH)],
            input=payload.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={
                "COLUMNS": "120",
                "GROK_STATUSLINE_TURN_CACHE": self._cache_path,
                "PATH": os.environ.get("PATH", ""),
                "HOME": os.environ.get("HOME", ""),
            },
        )
        self.assertEqual(p.returncode, 0)
        output = p.stdout.decode("utf-8")
        self.assertIn("Grok 4.7", output)
        self.assertIn("ctx:22%", output)
        self.assertIn("running:", output)
        self.assertIn("$0.01", output)


if __name__ == "__main__":
    unittest.main()
