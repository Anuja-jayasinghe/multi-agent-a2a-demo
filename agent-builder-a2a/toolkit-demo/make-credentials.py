"""Writes Config.toml (Basic user and JWT secret) and demo-credentials.txt for the demo agents.

Both files are local and gitignored. Run again with --force to make new credentials.
"""
import base64, hashlib, hmac, json, os, secrets, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "Config.toml")
CREDS = os.path.join(HERE, "demo-credentials.txt")


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(secret: str) -> str:
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"iss": "toolkit-demo", "aud": "city-events-agent", "sub": "weekend-planner",
               "iat": now, "exp": now + 180 * 24 * 3600}
    signing = b64(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        b64(json.dumps(payload, separators=(",", ":")).encode())
    sig = hmac.new(secret.encode(), signing.encode(), hashlib.sha256).digest()
    return signing + "." + b64(sig)


if os.path.exists(CONFIG) and os.path.exists(CREDS) and "--force" not in sys.argv:
    sys.exit(0)

password = secrets.token_urlsafe(12)
jwt_secret = secrets.token_urlsafe(32)
with open(CONFIG, "w") as f:
    f.write(f'eventsJwtSecret = "{jwt_secret}"\n\n'
            '[[ballerina.auth.users]]\n'
            'username = "planner"\n'
            f'password = "{password}"\n'
            'scopes = []\n')
with open(CREDS, "w") as f:
    f.write("Secrets to paste into Add Tool -> Use Agent -> A2A Agent (Secret field, Expression mode, with the quotes)\n\n"
            'Weather Agent      http://localhost:9201   no secret\n'
            f'Currency Agent     http://localhost:9202   "planner:{password}"\n'
            f'City Events Agent  http://localhost:9203   "{token(jwt_secret)}"\n')
os.chmod(CONFIG, 0o600)
os.chmod(CREDS, 0o600)
