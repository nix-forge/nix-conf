"""Public fixture tests for vault matching and secret-safe CLI input."""

import base64

# Standard-library unittest keeps this standalone maintenance script testable
# without installing pytest. Test method names describe each fixture.
# ruff: file-ignore[undocumented-public-method]
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "vault",
    Path(__file__).resolve().parents[2]
    / "hosts/nixos/desktop/local/homelab/credentials/homelab_to_bitwarden.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError
vault = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(vault)


class VaultTests(unittest.TestCase):  # ruff: ignore[too-many-public-methods] - Independent regressions share the same vault fixture.
    """Verify credential matching, preservation, and subprocess input."""

    def setUp(self) -> None:
        domain_patch = patch.object(vault, "DOMAIN", "example.test")
        domain_patch.start()
        self.addCleanup(domain_patch.stop)
        self.account: dict = {
            "name": "FreshRSS",
            "url": "https://reader.example.test",
            "username": "reader",
            "password": "fixture-new-password",
        }
        self.item: dict = {
            "id": "fixture-id",
            "type": 1,
            "name": "FreshRSS",
            "folderId": "folder",
            "notes": "Keep my notes",
            "fields": [{"name": "extra", "value": "keep", "type": 0}],
            "login": {
                "username": "old-name",
                "password": "old-password",
                "totp": "fixture-totp",
                "fido2Credentials": [{"credentialId": "keep"}],
                "uris": [{"uri": "https://reader.example.test", "match": 0}],
            },
        }

    def test_renamed_login_preserves_passkey_and_fields(self) -> None:
        self.assertEqual(vault.select_item([self.item], self.account), self.item)
        updated = vault.updated_item(self.item, self.account)
        self.assertEqual(
            updated["login"]["fido2Credentials"], self.item["login"]["fido2Credentials"]
        )
        self.assertEqual(updated["login"]["totp"], "fixture-totp")
        self.assertEqual(updated["notes"], self.item["notes"])
        self.assertEqual(updated["fields"], self.item["fields"])
        self.assertEqual(updated["folderId"], "folder")
        self.assertEqual(updated["login"]["uris"][0]["match"], 1)
        self.assertEqual(self.item["login"]["username"], "old-name")

    def test_miniflux_reader_alias_is_idempotent(self) -> None:
        account = {
            **self.account,
            "name": "Miniflux",
            "url": "https://miniflux.example.test",
        }
        updated = vault.updated_item(self.item, account)
        repeated = vault.updated_item(updated, account)
        self.assertEqual(updated, repeated)
        self.assertIn(
            {"uri": f"https://news.{vault.DOMAIN}", "match": 1},
            updated["login"]["uris"],
        )
        self.assertIn({"uri": account["url"], "match": 1}, updated["login"]["uris"])
        self.assertEqual(
            updated["login"]["fido2Credentials"], self.item["login"]["fido2Credentials"]
        )

    def test_multiple_accounts_same_url_are_distinct(self) -> None:
        other = vault.updated_item(self.item, {**self.account, "username": "viewer"})
        other["id"] = "viewer-id"
        other["name"] = "Viewer"
        chosen = vault.select_item([other, self.item], self.account)
        self.assertEqual(chosen["id"], "fixture-id")

    def test_ambiguous_rename_is_rejected(self) -> None:
        duplicate = {**self.item, "id": "duplicate"}
        with self.assertRaisesRegex(RuntimeError, "Ambiguous"):
            vault.select_item([self.item, duplicate], self.account)

    def test_different_site_name_does_not_overwrite(self) -> None:
        unrelated = {
            **self.item,
            "login": {
                **self.item["login"],
                "uris": [{"uri": "https://different.example.test"}],
            },
        }
        self.assertIsNone(vault.select_item([unrelated], self.account))

    def test_cli_credentials_only_in_stdin(self) -> None:
        with patch.object(
            vault, "run", return_value=json.dumps({"id": "fixture-id"})
        ) as run:
            self.assertEqual(
                vault.save_account(self.account, self.item, {}), "fixture-id"
            )
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["bw", "edit", "item", "fixture-id"])
        payload = json.loads(base64.b64decode(kwargs["data"]))
        self.assertEqual(payload["login"]["password"], self.account["password"])
        self.assertEqual(
            payload["login"]["fido2Credentials"], self.item["login"]["fido2Credentials"]
        )
        self.assertNotIn(self.account["password"], " ".join(args[0]))

    def test_missing_password_rejected_before_vault_access(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Missing or invalid"):
            vault.accounts(dict.fromkeys(vault.source_inventory(), ""))

    def test_stirling_login_uses_sealed_username(self) -> None:
        sources = vault.account_sources()["Stirling PDF"]
        self.assertEqual(
            sources,
            ["homelab-stirling-admin-username", "homelab-stirling-admin-password"],
        )
        selected = vault.accounts(
            {
                sources[0]: "sealed-stirling-user",
                sources[1]: "fixture-stirling-password",
            },
            {"Stirling PDF"},
        )
        self.assertEqual(selected[0]["username"], "sealed-stirling-user")

    def test_homebridge_uses_the_pis_deployed_login(self) -> None:
        sources = vault.account_sources()["Homebridge"]
        self.assertEqual(sources, ["homebridge-ui-username", "homebridge-ui-password"])
        selected = vault.accounts(
            {sources[0]: "fixture-ui-user", sources[1]: "fixture-ui-password"},
            {"Homebridge"},
        )
        self.assertEqual(selected[0]["url"], "https://homebridge.example.test")
        self.assertEqual(selected[0]["username"], "fixture-ui-user")

    def test_scrypted_uses_the_pis_deployed_login(self) -> None:
        sources = vault.account_sources()["Scrypted"]
        self.assertEqual(sources, ["scrypted-ui-username", "scrypted-ui-password"])
        selected = vault.accounts(
            {sources[0]: "fixture-ui-user", sources[1]: "fixture-ui-password"},
            {"Scrypted"},
        )
        self.assertEqual(selected[0]["url"], "https://scrypted.example.test")
        self.assertEqual(selected[0]["username"], "fixture-ui-user")

    def test_vesync_uses_the_pis_sealed_account(self) -> None:
        names = vault.account_sources()["VeSync (Homebridge)"]
        self.assertEqual(
            names, ["homebridge-vesync-username", "homebridge-vesync-password"]
        )
        selected = vault.accounts(
            {names[0]: "fixture-email", names[1]: "fixture-password"},
            {"VeSync (Homebridge)"},
        )
        self.assertEqual(selected[0]["url"], "https://account.vesync.com/")
        updated = vault.updated_item(None, selected[0])
        self.assertEqual(
            updated["login"]["uris"],
            [{"uri": "https://account.vesync.com/", "match": 1}],
        )
        self.assertEqual(vault.updated_item(updated, selected[0]), updated)

    def test_indexer_proxy_is_a_login_without_a_website_uri(self) -> None:
        names = vault.account_sources()["Indexer proxy (service)"]
        selected = vault.accounts(
            {names[0]: "fixture-user", names[1]: "fixture-password"},
            {"Indexer proxy (service)"},
        )[0]
        self.assertEqual(selected["url"], "")
        updated = vault.updated_item(None, selected)
        self.assertEqual(updated["login"]["uris"], [])
        updated["id"] = "fixture-proxy-id"
        self.assertEqual(vault.build_plan([updated], [selected])[0][1], updated)
        vault.verify_item(updated, selected, None)

    def test_all_sealed_username_password_pairs_are_in_the_inventory(self) -> None:
        root = Path(__file__).resolve().parents[2]
        inventory = set(vault.source_inventory())
        for directory in (
            root / "hosts/nixos/desktop/local/secrets",
            root / "hosts/nixos/raspberry-pi/local/secrets",
        ):
            names = {path.stem for path in directory.glob("*.age")}
            for username in names:
                if not username.endswith("-username"):
                    continue
                password = username.removesuffix("-username") + "-password"
                if password in names:
                    with self.subTest(source=username):
                        self.assertIn(username, inventory)
                        self.assertIn(password, inventory)

    def test_homebridge_secret_is_read_from_pi_through_admin_host(self) -> None:
        encoded = base64.b64encode(b"fixture-ui-user\n").decode()
        result = SimpleNamespace(
            returncode=0,
            stdout=f"homebridge-ui-username\t{encoded}\n",
            stderr="",
        )
        with patch.object(vault.subprocess, "run", return_value=result) as command:
            values = vault.read_sources(
                "fixture-admin-host", ["homebridge-ui-username"]
            )
        self.assertEqual(values, {"homebridge-ui-username": "fixture-ui-user"})
        self.assertEqual(command.call_args.args[0][:3], ["ssh", "-o", "BatchMode=yes"])
        self.assertIn("root@raspberry-pi", command.call_args.args[0][-1])
        self.assertNotIn("fixture-ui-user", str(command.call_args))

    def test_scrypted_secret_is_read_from_pi_through_admin_host(self) -> None:
        encoded = base64.b64encode(b"fixture-ui-user\n").decode()
        result = SimpleNamespace(
            returncode=0,
            stdout=f"scrypted-ui-username\t{encoded}\n",
            stderr="",
        )
        with patch.object(vault.subprocess, "run", return_value=result) as command:
            values = vault.read_sources("fixture-admin-host", ["scrypted-ui-username"])
        self.assertEqual(values, {"scrypted-ui-username": "fixture-ui-user"})
        self.assertIn("root@raspberry-pi", command.call_args.args[0][-1])

    def test_vesync_secret_is_read_from_pi_through_admin_host(self) -> None:
        encoded = base64.b64encode(b"fixture-email\n").decode()
        result = SimpleNamespace(
            returncode=0,
            stdout=f"homebridge-vesync-username\t{encoded}\n",
            stderr="",
        )
        with patch.object(vault.subprocess, "run", return_value=result) as command:
            values = vault.read_sources(
                "fixture-admin-host", ["homebridge-vesync-username"]
            )
        self.assertEqual(values, {"homebridge-vesync-username": "fixture-email"})
        self.assertIn("root@raspberry-pi", command.call_args.args[0][-1])
        self.assertNotIn("find -L", command.call_args.kwargs["input"])

    def test_dotenv_does_not_execute_shell(self) -> None:
        self.assertEqual(
            vault.dotenv('PASSWORD="$(touch /tmp/not-created)"')["PASSWORD"],
            "$(touch /tmp/not-created)",
        )

    def test_selector_needs_only_selected_credentials(self) -> None:
        values = {
            "homelab-freshrss-username": "reader",
            "homelab-freshrss-password": "fixture-password",
        }
        selected = vault.accounts(values, {"FreshRSS"})
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["name"], "FreshRSS")

    def test_receipt_excludes_credentials_and_is_private(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            vault.write_receipt(path, [(self.account, "fixture-id")])
            receipt = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                receipt["accounts"],
                [
                    {
                        "name": "FreshRSS",
                        "itemId": "fixture-id",
                        "verified": True,
                        "verifiedAt": receipt["verifiedAt"],
                    }
                ],
            )
            self.assertNotIn(self.account["password"], path.read_text(encoding="utf-8"))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_identity_realm_and_administrator_remain_distinct(self) -> None:
        values = {
            "homelab-identity-realm": json.dumps({
                "users": [
                    {
                        "username": "fixture-household",
                        "credentials": [
                            {"type": "password", "value": "fixture-password"}
                        ],
                    }
                ]
            }),
            "homelab-identity-admin-env": "HOMELAB_ADMIN_USERNAME=fixture-admin\nHOMELAB_ADMIN_PASSWORD=fixture-admin-password",
        }
        selected = vault.accounts(
            values, {"Wardrowbe", "Wardrowbe sign-in administrator"}
        )
        self.assertEqual(len(selected), 2)
        self.assertEqual(selected[0]["url"], "https://identity.example.test")
        self.assertEqual(selected[1]["url"], "https://identity.example.test/admin/")
        existing = {
            "id": "admin",
            "type": 1,
            "name": "Wardrowbe sign-in administrator",
            "login": {"username": "old-admin", "uris": [{"uri": selected[1]["url"]}]},
        }
        self.assertIsNone(vault.select_item([existing], selected[0]))
        self.assertEqual(vault.select_item([existing], selected[1])["id"], "admin")
        household = vault.updated_item(None, selected[0])
        administrator = vault.updated_item(existing, selected[1])
        self.assertEqual(
            household["login"]["uris"],
            [
                {"uri": "https://identity.example.test", "match": 3},
                {"uri": "https://identity.example.test/realms/homelab/", "match": 2},
            ],
        )
        self.assertEqual(administrator["login"]["uris"][0]["match"], 2)

    def test_wardrowbe_username_rotation_updates_existing_item(self) -> None:
        account = {
            "name": "Wardrowbe",
            "url": "https://identity.example.test",
            "username": "member",
            "password": "fixture-current-password",
        }
        original = {
            **self.item,
            "name": "Wardrowbe",
            "login": {
                **self.item["login"],
                "username": "member-old",
                "uris": [{"uri": account["url"], "match": 0}],
            },
        }
        plan = vault.build_plan([original], [account])
        self.assertEqual(plan[0][1]["id"], original["id"])
        updated = vault.updated_item(plan[0][1], account)
        vault.verify_item(updated, account, original)
        self.assertEqual(updated["name"], "Wardrowbe")
        self.assertEqual(updated["login"]["username"], "member")
        self.assertEqual(updated["login"]["uris"][0]["match"], 3)
        self.assertEqual(
            updated["login"]["fido2Credentials"], original["login"]["fido2Credentials"]
        )

    def test_wardrowbe_legacy_titles_migrate_in_place(self) -> None:
        for old, new in [
            ("Homelab identity", "Wardrowbe"),
            ("Homelab identity administrator", "Wardrowbe sign-in administrator"),
        ]:
            with self.subTest(name=new):
                account = {**self.account, "name": new}
                original = {**self.item, "name": old}
                selected = vault.build_plan([original], [account])[0][1]
                self.assertIsNotNone(selected)
                self.assertEqual(
                    vault.select_item([original], account)["id"], original["id"]
                )
                updated = vault.updated_item(selected, account)
                self.assertEqual(updated["name"], new)
                vault.verify_item(updated, account, original)
                self.assertIn(new, vault.account_sources())

    def test_readback_detects_a_lost_passkey(self) -> None:
        updated = vault.updated_item(self.item, self.account)
        vault.verify_item(updated, self.account, self.item)
        updated["login"]["fido2Credentials"] = []
        with self.assertRaisesRegex(RuntimeError, "preserved login field"):
            vault.verify_item(updated, self.account, self.item)

    def test_shared_identical_login_is_one_merged_vault_mutation(self) -> None:
        first = {
            **self.account,
            "name": "Jellyfin (admin)",
            "url": "https://jellyfin.example.test",
        }
        second = {
            **self.account,
            "name": "Seerr (admin)",
            "url": "https://seerr.example.test",
        }
        existing = {
            **self.item,
            "login": {
                **self.item["login"],
                "username": "reader",
                "uris": [{"uri": first["url"]}, {"uri": second["url"]}],
            },
        }
        plan = vault.build_plan([existing], [first, second])
        grouped = vault.group_plan(plan)
        self.assertEqual(len(grouped), 1)
        group, original = grouped[0]
        with patch.object(
            vault, "run", return_value=json.dumps({"id": "fixture-id"})
        ) as run:
            vault.save_accounts(group, original, {})
        run.assert_called_once()
        payload = json.loads(base64.b64decode(run.call_args.kwargs["data"]))
        self.assertEqual(
            payload["login"]["uris"],
            [{"uri": first["url"], "match": 1}, {"uri": second["url"], "match": 1}],
        )
        self.assertEqual(
            payload["login"]["fido2Credentials"], self.item["login"]["fido2Credentials"]
        )

    def test_exact_username_claim_wins_over_another_accounts_legacy_name(self) -> None:
        existing = {
            **self.item,
            "login": {**self.item["login"], "username": "administrator"},
        }
        administrator = {
            **self.account,
            "name": "FreshRSS (admin)",
            "username": "administrator",
            "password": "fixture-admin-password",
        }
        plan = vault.build_plan([existing], [self.account, administrator])
        self.assertIsNone(plan[0][1])
        self.assertEqual(plan[1][1]["id"], "fixture-id")
        self.assertEqual(len(vault.group_plan(plan)), 2)

    def test_conflicting_shared_passwords_report_accounts_before_mutation(self) -> None:
        first = {
            **self.account,
            "name": "Jellyfin (admin)",
            "url": "https://jellyfin.example.test",
        }
        second = {
            **self.account,
            "name": "Seerr (admin)",
            "url": "https://seerr.example.test",
            "password": "different-password",
        }
        existing = {
            **self.item,
            "login": {
                **self.item["login"],
                "username": "reader",
                "uris": [{"uri": first["url"]}, {"uri": second["url"]}],
            },
        }
        with (
            patch.object(vault, "run") as run,
            self.assertRaisesRegex(
                RuntimeError, r"Jellyfin \(admin\).*Seerr \(admin\)"
            ),
        ):
            vault.build_plan([existing], [first, second])
        run.assert_not_called()

    def test_username_change_preserves_custom_title_item_with_same_password(
        self,
    ) -> None:
        existing = {
            **self.item,
            "name": "My personal news reader",
            "login": {**self.item["login"], "password": self.account["password"]},
        }
        plan = vault.build_plan([existing], [self.account])
        self.assertEqual(plan[0][1]["id"], "fixture-id")
        updated = vault.updated_item(plan[0][1], self.account)
        self.assertEqual(updated["name"], "My personal news reader")
        self.assertEqual(updated["login"]["username"], "reader")

    def test_ambiguous_unchanged_password_rename_fails_before_mutation(self) -> None:
        existing = {
            **self.item,
            "name": "Custom title",
            "login": {**self.item["login"], "password": self.account["password"]},
        }
        duplicate = {**existing, "id": "duplicate-id", "name": "Another custom title"}
        with (
            patch.object(vault, "run") as run,
            self.assertRaisesRegex(RuntimeError, "Ambiguous.*FreshRSS"),
        ):
            vault.build_plan([existing, duplicate], [self.account])
        run.assert_not_called()

    def test_reconcile_identifies_unclaimed_domain_logins(self) -> None:
        account = {**self.account, "url": "https://reader.example.test"}
        current = vault.updated_item(None, account)
        current["id"] = "current"
        stale = {
            "id": "stale",
            "type": 1,
            "name": "Old reader login",
            "login": {
                "username": "old-user",
                "password": "old-password",
                "uris": [{"uri": account["url"]}],
            },
        }
        unrelated = {
            **stale,
            "id": "unrelated",
            "login": {**stale["login"], "uris": [{"uri": "https://elsewhere.test"}]},
        }
        plan = vault.build_plan([current, stale, unrelated], [account])
        groups, extras, unsafe = vault.reconcile_status(
            [current, stale, unrelated], plan
        )
        self.assertFalse(groups[0][2])
        self.assertEqual([item["id"] for item in extras], ["stale"])
        self.assertEqual(unsafe, [])

    def test_reconcile_preserves_passkeys_and_mixed_uri_items(self) -> None:
        account = {**self.account, "url": "https://reader.example.test"}
        current = vault.updated_item(None, account)
        current["id"] = "current"
        stale = {
            "id": "stale",
            "type": 1,
            "name": "Other reader login",
            "login": {
                "username": "other-user",
                "uris": [
                    {"uri": account["url"]},
                    {"uri": "https://elsewhere.test"},
                ],
                "fido2Credentials": [{"credentialId": "keep"}],
            },
        }
        plan = vault.build_plan([current, stale], [account])
        _, extras, unsafe = vault.reconcile_status([current, stale], plan)
        self.assertEqual(extras, [])
        self.assertEqual([item["id"] for item in unsafe], ["stale"])

    def test_unconfigured_domain_login_requires_review(self) -> None:
        account = {**self.account, "url": "https://reader.example.test"}
        unknown = {
            "id": "unknown",
            "type": 1,
            "name": "Unknown service",
            "login": {"uris": [{"uri": "https://unknown.example.test"}]},
        }
        _, extras, unsafe = vault.reconcile_status(
            [unknown], vault.build_plan([unknown], [account])
        )
        self.assertEqual(extras, [])
        self.assertEqual([item["id"] for item in unsafe], ["unknown"])

    def test_default_vault_plan_never_writes_items(self) -> None:
        account = {**self.account, "url": "https://reader.example.test"}
        with (
            patch.object(vault, "unlock"),
            patch.object(vault, "run", side_effect=["", "[]"]) as command,
            patch("builtins.print"),
        ):
            vault.reconcile_vault(
                [account],
                {},
                apply=False,
                only=False,
                receipt=Path("unused-receipt"),
            )
        self.assertEqual(
            [call.args[0][:2] for call in command.call_args_list],
            [["bw", "sync"], ["bw", "list"]],
        )

    def test_apply_leaves_unclaimed_domain_items_untouched(self) -> None:
        account = {**self.account, "url": "https://reader.example.test"}
        unclaimed = {
            "id": "another-id",
            "type": 1,
            "name": "Another login",
            "login": {
                "username": "another-user",
                "password": "another-password",
                "uris": [{"uri": account["url"]}],
            },
        }
        saved = vault.updated_item(None, account)
        saved["id"] = "created-id"

        def run_command(argv: list[str], **_kwargs: object) -> str:
            if argv[:3] == ["bw", "list", "items"]:
                return json.dumps([unclaimed])
            if argv[:3] == ["bw", "get", "item"]:
                return json.dumps(saved)
            if argv == ["bw", "sync"]:
                return ""
            self.fail(f"Unexpected Bitwarden command: {argv}")
            return ""

        with (
            patch.object(vault, "unlock"),
            patch.object(vault, "run", side_effect=run_command) as command,
            patch.object(vault, "save_accounts", return_value="created-id"),
            patch.object(vault, "write_receipt"),
            patch("builtins.print"),
        ):
            vault.reconcile_vault(
                [account],
                {},
                apply=True,
                only=False,
                receipt=Path("unused-receipt"),
            )
        self.assertNotIn(
            ["bw", "delete", "item", "another-id"],
            [call.args[0] for call in command.call_args_list],
        )

    def test_subset_receipt_retains_prior_verified_accounts_and_timestamps(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            path.write_text(
                json.dumps({
                    "verifiedAt": "2026-01-01T00:00:00+00:00",
                    "accounts": [
                        {
                            "name": "Other account",
                            "itemId": "other-id",
                            "verified": True,
                        },
                        {"name": "FreshRSS", "itemId": "old-id", "verified": True},
                    ],
                }),
                encoding="utf-8",
            )
            vault.write_receipt(path, [(self.account, "fixture-id")])
            receipt = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(len(receipt["accounts"]), 2)
            records = {record["name"]: record for record in receipt["accounts"]}
            self.assertEqual(
                records["Other account"]["verifiedAt"], "2026-01-01T00:00:00+00:00"
            )
            self.assertEqual(records["Other account"]["itemId"], "other-id")
            self.assertEqual(records["FreshRSS"]["itemId"], "fixture-id")
            self.assertEqual(records["FreshRSS"]["verifiedAt"], receipt["verifiedAt"])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_actual_uses_its_own_credentials_and_realm_autofill(self) -> None:
        values = {
            "homelab-actual-username": "actual-reader",
            "homelab-actual-password": "fixture-actual-password",
        }
        selected = vault.accounts(values, {"Actual"})
        self.assertEqual(len(selected), 1)
        self.assertEqual(
            vault.account_sources()["Actual"],
            ["homelab-actual-username", "homelab-actual-password"],
        )
        updated = vault.updated_item(None, selected[0])
        self.assertEqual(
            updated["login"]["uris"],
            [
                {"uri": "https://actual.example.test", "match": 1},
                {"uri": "https://identity.example.test/realms/actual/", "match": 2},
            ],
        )
        household = {
            "name": "Wardrowbe",
            "url": "https://identity.example.test",
            "username": "household-reader",
            "password": "fixture-household-password",
        }
        main = vault.updated_item(None, household)
        self.assertNotIn(
            {"uri": "https://identity.example.test/realms/actual/", "match": 2},
            main["login"]["uris"],
        )
        self.assertNotIn(
            {"uri": "https://identity.example.test/realms/homelab/", "match": 2},
            updated["login"]["uris"],
        )
        self.assertIsNone(vault.select_item([updated], household))
        vault.verify_item(updated, selected[0], None)
        updated["login"]["uris"][1]["match"] = 1
        with self.assertRaisesRegex(RuntimeError, "autofill URI"):
            vault.verify_item(updated, selected[0], None)

    def test_dashboard_password_only_login_uses_deployed_bundle(self) -> None:
        self.assertEqual(
            vault.account_sources()["Dashboard"], ["homelab-dashboard-env"]
        )
        selected = vault.accounts(
            {
                "homelab-dashboard-env": (
                    "HOMEPAGE_AUTH_SECRET=fixture-session-secret\n"
                    "HOMEPAGE_AUTH_PASSWORD='fixture-dashboard-password'\n"
                )
            },
            {"Dashboard"},
        )
        self.assertEqual(
            selected,
            [
                {
                    "name": "Dashboard",
                    "url": "https://dashboard.example.test",
                    "username": "",
                    "password": "fixture-dashboard-password",
                }
            ],
        )
        item = vault.updated_item(None, selected[0])
        self.assertIsNone(item["login"]["username"])
        self.assertEqual(
            item["login"]["uris"],
            [{"uri": "https://dashboard.example.test", "match": 1}],
        )
        vault.verify_item(item, selected[0], None)
        normalized = {
            **item,
            "login": {**item["login"], "username": ""},
        }
        vault.verify_item(normalized, selected[0], None)
        self.assertEqual(vault.updated_item(item, selected[0]), item)
        with self.assertRaisesRegex(RuntimeError, "password read-back"):
            vault.verify_item(
                {**item, "login": {**item["login"], "password": "wrong"}},
                selected[0],
                None,
            )
        with self.assertRaisesRegex(RuntimeError, "Missing or invalid"):
            vault.accounts(
                {"homelab-dashboard-env": "HOMEPAGE_AUTH_SECRET=fixture-only"},
                {"Dashboard"},
            )


if __name__ == "__main__":
    unittest.main()
