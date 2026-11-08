"""Obtain an Actual OIDC session without putting credentials in arguments."""

import html.parser
import http.cookiejar
import json
import os
import pathlib
import sys
import urllib.parse
import urllib.request

SERVER = os.environ["ACTUAL_SERVER_URL"]
IDENTITY = os.environ["ACTUAL_IDENTITY_URL"]


class LoginForm(html.parser.HTMLParser):
    """Read only the identity provider login form and hidden fields."""

    def __init__(self) -> None:
        """Initialize an empty form."""
        super().__init__()
        self.action: str | None = None
        self.fields: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Collect the login action and hidden values."""
        attributes = dict(attrs)
        if tag == "form" and attributes.get("id") == "kc-form-login":
            self.action = attributes.get("action")
        name = attributes.get("name")
        if tag == "input" and attributes.get("type") == "hidden" and name:
            self.fields[name] = attributes.get("value") or ""


def login(username_file: str, password_file: str, token_file: str) -> None:
    """Authenticate with authorization code and persist a runtime-only token.

    Raises:
        RuntimeError: Login or its identity-provider boundary is invalid.

    """
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
    )
    request = urllib.request.Request(
        SERVER + "/account/login",
        data=json.dumps({"loginMethod": "openid", "returnUrl": SERVER}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with opener.open(request, timeout=30) as response:
        url = json.load(response)["data"]["returnUrl"]
    if (urllib.parse.urlsplit(url).scheme, urllib.parse.urlsplit(url).netloc) != (
        "https",
        urllib.parse.urlsplit(IDENTITY).netloc,
    ):
        raise RuntimeError("Unexpected identity provider")
    with opener.open(url, timeout=30) as response:
        form = LoginForm()
        form.feed(response.read().decode())
    if not form.action or (
        urllib.parse.urlsplit(form.action).scheme,
        urllib.parse.urlsplit(form.action).netloc,
    ) != ("https", urllib.parse.urlsplit(IDENTITY).netloc):
        raise RuntimeError("Unexpected login form")
    form.fields.update(
        username=pathlib.Path(username_file).read_text(encoding="utf-8").strip(),
        password=pathlib.Path(password_file).read_text(encoding="utf-8").strip(),
    )
    with opener.open(
        urllib.request.Request(
            form.action, data=urllib.parse.urlencode(form.fields).encode()
        ),
        timeout=30,
    ) as response:
        final = urllib.parse.urlsplit(response.geturl())
        if (
            final.netloc != urllib.parse.urlsplit(SERVER).netloc
            or final.path != "/openid-cb"
        ):
            raise RuntimeError("Login did not complete")
        token = urllib.parse.parse_qs(final.query)["token"][0]
    destination = pathlib.Path(token_file)
    temporary = destination.with_suffix(".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(token)
    temporary.replace(destination)


if __name__ == "__main__":
    try:
        login(*sys.argv[1:])
    except Exception:
        print(
            "Actual login failed; credentials and session URLs were not logged",
            file=sys.stderr,
        )
        sys.exit(1)
