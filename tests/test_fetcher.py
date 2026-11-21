import os
import sys
import unittest
from unittest.mock import patch, MagicMock

# Ensure mock credentials exist so fetcher imports cleanly
os.environ.setdefault("GOOGLE_CLIENT_ID", "mock_client_id")
os.environ.setdefault("GOOGLE_CLIENT_SECRET", "mock_client_secret")

# Add repo root to sys.path
repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

from fetcher import query_google_api, parse_quota_data


class TestFetcher(unittest.TestCase):

    @patch("fetcher.requests.post")
    def test_retrieve_user_quota_summary_uses_daily_cloudcode_and_payload(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"groups": []}
        mock_resp.headers = {"content-type": "application/json"}
        mock_post.return_value = mock_resp

        # 1. Base call with payload
        res = query_google_api(
            access_token="test_access_token",
            endpoint="retrieveUserQuotaSummary",
            payload={"project": "my-sample-project"}
        )

        self.assertIsNotNone(res)
        mock_post.assert_called_once()
        call_args, call_kwargs = mock_post.call_args
        self.assertEqual(
            call_args[0],
            "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
        )
        self.assertEqual(call_kwargs.get("json"), {"project": "my-sample-project"})

        # 2. Even if legacy cloudcode-pa base_url is passed, it must route to daily-cloudcode-pa
        mock_post.reset_mock()
        query_google_api(
            access_token="test_access_token",
            endpoint="retrieveUserQuotaSummary",
            base_url="https://cloudcode-pa.googleapis.com",
            payload={"project": "my-sample-project"}
        )
        call_args, call_kwargs = mock_post.call_args
        self.assertEqual(
            call_args[0],
            "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
        )
        self.assertEqual(call_kwargs.get("json"), {"project": "my-sample-project"})

    @patch("fetcher.requests.post")
    def test_query_google_api_optional_payload(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"models": {}}
        mock_resp.headers = {}
        mock_post.return_value = mock_resp

        # Call without payload (default None -> {})
        query_google_api(access_token="token_xyz", endpoint="fetchAvailableModels")
        _, kwargs_none = mock_post.call_args
        self.assertEqual(kwargs_none.get("json"), {})

        # Call with explicit payload
        mock_post.reset_mock()
        custom_payload = {"metadata": {"ideType": "ANTIGRAVITY"}}
        query_google_api(access_token="token_xyz", endpoint="loadCodeAssist", payload=custom_payload)
        _, kwargs_custom = mock_post.call_args
        self.assertEqual(kwargs_custom.get("json"), custom_payload)

    def test_parse_quota_data_weekly_under_100_percent(self):
        models_data = {
            "models": {
                "gemini-2.5-pro": {
                    "quotaInfo": {
                        "remainingFraction": 0.85,
                        "resetTime": "2026-11-21T20:00:00Z"
                    }
                }
            }
        }
        quota_summary_data = {
            "groups": [
                {
                    "displayName": "Gemini models",
                    "buckets": [
                        {
                            "bucketId": "gemini-weekly",
                            "displayName": "Weekly Limit Remaining",
                            "window": "weekly",
                            "remainingFraction": 0.9935,
                            "resetTime": "2026-11-28T00:00:00Z"
                        },
                        {
                            "bucketId": "gemini-5h",
                            "displayName": "Five Hour Limit Remaining",
                            "window": "5h",
                            "remainingFraction": 0.85,
                            "resetTime": "2026-11-21T20:00:00Z"
                        }
                    ]
                }
            ]
        }

        # Case 1: models_data provides 5h, quota_summary provides weekly
        parsed = parse_quota_data(
            load_assist_data={"allowedTiers": [{"id": "tier-standard"}]},
            quota_summary_data=quota_summary_data,
            models_data=models_data
        )

        self.assertEqual(parsed["tier"], "tier-standard")
        self.assertEqual(len(parsed["groups"]), 1)
        gemini_group = parsed["groups"][0]
        self.assertIn("weekly", gemini_group["limits"])
        weekly = gemini_group["limits"]["weekly"]
        self.assertEqual(weekly["remaining_fraction"], 0.9935)
        self.assertEqual(weekly["used_percent"], 99)

        # Case 2: remainingFraction < 1.0 but close to 1.0 (e.g. 0.9995) must not round up to 100%
        quota_summary_near_full = {
            "groups": [
                {
                    "displayName": "Gemini models",
                    "buckets": [
                        {
                            "bucketId": "gemini-weekly",
                            "displayName": "Weekly Limit Remaining",
                            "window": "weekly",
                            "remainingFraction": 0.9995,
                            "resetTime": "2026-11-28T00:00:00Z"
                        }
                    ]
                }
            ]
        }
        parsed_near_full = parse_quota_data(
            load_assist_data={},
            quota_summary_data=quota_summary_near_full,
            models_data=models_data
        )
        self.assertEqual(parsed_near_full["groups"][0]["limits"]["weekly"]["used_percent"], 99)

        # Case 3: models_data is None (fallback path to quota_summary_data)
        parsed_fallback = parse_quota_data(
            load_assist_data={},
            quota_summary_data=quota_summary_data,
            models_data=None
        )
        self.assertEqual(len(parsed_fallback["groups"]), 1)
        weekly_fallback = parsed_fallback["groups"][0]["limits"]["weekly"]
        self.assertEqual(weekly_fallback["remaining_fraction"], 0.9935)
        self.assertEqual(weekly_fallback["used_percent"], 99)


if __name__ == "__main__":
    unittest.main()
