"""Identity imports permit self-service credentials without administrator access."""

import importlib.util
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "hosts/nixos/desktop/local/homelab/credentials/identity_to_bitwarden.py"
)
spec = importlib.util.spec_from_file_location("identity_credentials", SCRIPT)
assert spec is not None
assert spec.loader is not None
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class IdentityRealmTests(unittest.TestCase):
    """Check the imported member's authorization boundary."""

    def test_member_can_manage_own_credentials_without_admin_roles(self) -> None:
        """Account Console requires account roles even for imported members."""
        realm = identity.realm_document(
            "fixture",
            "https://wardrobe.example.org",
            "https://identity.example.org",
            "member",
            "fixture-password",
            "fixture-client-secret",
        )
        user = realm["users"][0]
        roles = user.get("clientRoles", {})
        self.assertTrue(
            {"manage-account", "view-profile"} <= set(roles.get("account", []))
        )
        self.assertEqual(set(roles), {"account"})
        self.assertFalse(user.get("realmRoles"))
        self.assertFalse(realm["registrationAllowed"])


if __name__ == "__main__":
    unittest.main()
