# Bamboo-api

A multi-protocol AI gateway with a billing ledger and a console, written in the
[Bun language](https://github.com/Iotatg/Bun) — the small dynamically typed
language whose runtime lives in that repository, not the JavaScript runtime of
the same name.

One upstream key in, three wire protocols out:

| Endpoint | Protocol |
|---|---|
| `POST /v1/chat/completions` | OpenAI Chat Completions |
| `POST /v1/messages` | Anthropic Messages |
| `POST /v1/responses` | OpenAI Responses |
| `GET /v1/models` | the catalogue with live prices |
| `GET /v1/balance`, `/v1/usage`, `/v1/rpm` | wallet and limits |

It is a reimplementation of the architecture of
[APInexGate](https://github.com/Apinex-AI/APInexGate) (MIT) — gateway, reseller
catalogue, wallet, admin control plane — rebuilt from scratch on the Bun
language's own primitives: `tcp_listen`/`tcp_accept`/`tcp_read`/`tcp_write` for
HTTP, `bun:sqlite`-free JSON persistence, `pbkdf2_sha512` for passwords, and
`http_post` for the upstream.

---

## See it running

A live instance with demo data is at
[`a12127ad908120d7b.apps.workbuddy.host`](https://a12127ad908120d7b.apps.workbuddy.host/?sharecode=XEP4TCDWAO)
— sign in as `ravi@example.com` / `bamboo12345`, or as the admin at `/admin`
with `admin@localhost` / `bamboo-admin`. Its upstream is a mock, so answers come
back as `echo: …`; the billing, streaming and console are real.

## Run it

```bash
# 1. the language runtime (Python 3.8+)
git clone https://github.com/Iotatg/Bun
export BUN_LANG_HOME=$PWD/Bun/bun

# 2. this gateway
cd Bamboo-api
cp .env.example .env        # then set UPSTREAM_API_KEY and ADMIN_PASSWORD
./bin/bamboo app.bun
```

```
  Bamboo-api
  console   http://localhost:8787/dashboard
  admin     http://localhost:8787/admin
  gateway   http://localhost:8787/v1
  upstream  https://api.apinex.bond/v1
```

The first start creates the admin account from `ADMIN_EMAIL` / `ADMIN_PASSWORD`
(`admin@localhost` / `bamboo-admin` if you did not set them — change it).

Open `/admin`, sign in, paste your
`sk-apx-...` key under **Upstream**, then press **Import from APInex**. The
catalogue arrives with the upstream's context windows and per-million prices;
edit any price to set your own margin.

A customer registers at `/register`, creates a key at `/dashboard`, and points
an SDK at `http://localhost:8787/v1`.

### Without an APInex key

`scripts/mock_upstream.py` is a stand-in that speaks the same shape, so the
whole gateway can be exercised offline:

```bash
python3 scripts/mock_upstream.py &
UPSTREAM_BASE_URL=http://127.0.0.1:9001/v1 UPSTREAM_API_KEY=test ./bin/bamboo app.bun
```

### Test it

```bash
BUN_LANG_HOME=$PWD/../Bun/bun ./scripts/smoke.sh
# 29 passed, 0 failed
```

The smoke test registers a customer, imports the catalogue, credits a wallet,
and calls all three protocols with and without streaming, asserting on the
bytes each one returns.

---

## How it is put together

```
app.bun                  entry: build the router, listen, serve
bin/bamboo               launcher; finds the language runtime
src/http.bun             HTTP/1.1 on raw sockets, keep-alive, chunked SSE
src/router.bun           method + path with :params and *rest
src/store.bun            the database: one JSON document, written under a mutex
src/auth.bun             API keys (hashed) and console sessions (cookies)
src/crypto.bun           hex, key generation, PBKDF2 passwords
src/billing.bun          micro-dollar arithmetic, price formatting
src/limit.bun            fixed-window rate limits
src/upstream.bun         the only module that talks to APInex
src/transform/anthropic.bun   Messages <-> chat completions, including SSE
src/transform/responses.bun   Responses <-> chat completions, including SSE
src/gateway.bun          the /v1 handlers
src/console.bun          pages and the /api routes behind them
src/ui.bun               HTML; CSS and page scripts live in assets/ and src/ui/
src/seed.bun             creates the first admin
```

### Why the server is hand-written

`bun:web` has a router and a server, but its `chunked()` sends every piece at
once. A gateway has to forward an SSE event the moment it lands, so
`src/http.bun` owns the socket: it parses the request, keeps the connection
open, writes `Transfer-Encoding: chunked` frames as the upstream produces them,
and hands the handler a `write` function.

### Billing

Money is an integer count of micro-dollars (1 unit = $0.000001), so no charge
loses a fraction. A model price is stored as micro-dollars per million tokens;
the charge for a request is

```
ceil(input_tokens  × input_price  / 1e6)
+ ceil(output_tokens × output_price / 1e6)
```

rounded up per component and written to the ledger as one `usage` row. A model
priced at zero is metered against the account's monthly free token pool
instead. The wallet is checked before the request is forwarded and charged
after it completes, from the usage the upstream reported — never from an
estimate.

### Limits

Each key gets a fixed-window RPM budget (`DEFAULT_RPM`, per account). The
response carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`,
`X-RateLimit-Reset`, and `Retry-After` when the window is closed.

---

## The console

Four pages, server-rendered, with a small script each:

- `/dashboard` — wallet, free allowance, RPM, keys (shown once), the last fifty
  requests, and a copy-ready `curl`.
- `/admin` — the catalogue with editable prices, one-click import, accounts with
  a credit action, and the upstream key.
- `/docs` — the reference: endpoints, both protocols, the error shape.
- `/login`, `/register` — auth.

The design is a ledger: warm black paper, one bamboo-green accent, hairlines
instead of cards, tabular numerals so a column of money lines up. The visual
system was built with [Impeccable](https://github.com/pbakaus/impeccable) and
checked with its detector:

```bash
npx impeccable detect assets/app.css src/ui/     # 0 findings
npx impeccable detect http://localhost:8787/docs # 0 findings
```

`DESIGN.md` records the tokens and the rules that keep it consistent.

---

## What is not here

Honest scope. APInexGate is a large product; this is the gateway core, and the
following are deliberately absent:

- **Payments.** No card or crypto processor. Wallets are credited by an admin,
  or by whatever you wire to `POST /api/admin/users/:id/credit`.
- **Subscriptions, promo codes, vouchers, referrals, Google OAuth.** The
  ledger and the account model are here; the commerce around them is not.
- **SQL.** The store is a single JSON document, rewritten on every mutation.
  It is correct under the mutex and fine for a small reseller, but it is not a
  database: a few thousand requests per day, not a few million.
- **TLS verification on the upstream.** The language's `tcp_tls_connect`
  builtin disables certificate verification; the non-streaming path uses
  `http_post`, which verifies. Streaming inherits the builtin's behaviour.
- **Multi-process.** One process, one file. Two instances would fight over the
  document.

---

## Credits

- [APInexGate](https://github.com/Apinex-AI/APInexGate) (MIT) — the architecture,
  the protocol surface, and the ledger model this follows.
- [APInex](https://apinex.bond) — the upstream that serves the models.
- [Bun language](https://github.com/Iotatg/Bun) — the runtime and standard library.
- [Impeccable](https://github.com/pbakaus/impeccable) (Apache-2.0) — the design
  vocabulary and the anti-pattern detector.
