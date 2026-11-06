#!/usr/bin/env python3
"""Regenerate synthetic Cognito fixtures using a pinned independent Python oracle."""

import ast
import base64
import binascii
import datetime
import hashlib
import hmac
import json
import os
import types
import urllib.request
from pathlib import Path

REVISION = "6b8de182c6918de133f452af30e87e3d8aecc20e"
URL = f"https://raw.githubusercontent.com/NabuCasa/pycognito/{REVISION}/pycognito/aws_srp.py"


def generate():
    source = urllib.request.urlopen(URL, timeout=30).read()
    tree = ast.parse(source)
    # Run the pinned reference's arithmetic and AWSSRP class, with no network SDK
    # imports or account data. No authentication method is invoked.
    selected = [
        node
        for node in tree.body
        if isinstance(node, (ast.Assign, ast.FunctionDef, ast.ClassDef))
    ]
    fixed = datetime.datetime(2026, 11, 5, 21, 55, 7)

    class Clock:
        @staticmethod
        def utcnow():
            return fixed

    ns = dict(
        base64=base64,
        binascii=binascii,
        hashlib=hashlib,
        hmac=hmac,
        os=os,
        datetime=types.SimpleNamespace(datetime=Clock),
    )
    exec(compile(ast.Module(body=selected, type_ignores=[]), URL, "exec"), ns)
    cls = ns["AWSSRP"]
    vectors = []
    for name, a_hex, salt, server_b in [
        ("leading-zero", "00" * 127 + "01", "000001", "80"),
        ("sign-padding", "80" + "a5" * 127, "80", "f1" * 384),
        ("odd-salt", "5a" * 128, "abc", "7e" * 384),
    ]:
        cls.generate_random_small_a = lambda self: int(a_hex, 16) % self.big_n
        config = dict(
            pool_id="us-west-2_SYNTHETIC",
            client_id="synthetic-client",
            client_secret="synthetic-client-secret",
        )
        srp = cls(
            username="installer@example.invalid",
            password="Synthetic-Passphrase-Only!",
            client=object(),
            **config,
        )
        challenge = dict(
            USERNAME="internal-canonical-user",
            USER_ID_FOR_SRP="srp-canonical-user",
            SALT=salt,
            SRP_B=server_b,
            SECRET_BLOCK=base64.b64encode(b"Synthetic secret block\x00\xff").decode(),
        )
        params = srp.get_auth_params()
        key = srp.get_password_authentication_key(
            challenge["USER_ID_FOR_SRP"], srp.password, int(server_b, 16), salt
        )
        vectors.append(
            dict(
                name=name,
                config=config,
                username=srp.username,
                password=srp.password,
                private_hex=a_hex,
                challenge=challenge,
                timestamp=cls.get_cognito_formatted_timestamp(fixed),
                auth_parameters=params,
                key_hex=key.hex(),
                response=srp.process_challenge(challenge, params),
            )
        )
    return dict(
        reference=URL,
        source_sha256=hashlib.sha256(source).hexdigest(),
        synthetic=True,
        timestamp_epoch=int(fixed.replace(tzinfo=datetime.timezone.utc).timestamp()),
        padding=[
            dict(input=h, output=ns["pad_hex"](h))
            for h in ("0", "1", "7f", "80", "ff", "abc", "000001", "0080")
        ],
        vectors=vectors,
    )


if __name__ == "__main__":
    output = (
        Path(__file__).resolve().parents[1]
        / "test/fixtures/schlage/cognito-vectors.json"
    )
    output.write_text(json.dumps(generate(), indent=2) + "\n")
    print(f"Wrote {output.name}: synthetic vectors from pycognito {REVISION}")
