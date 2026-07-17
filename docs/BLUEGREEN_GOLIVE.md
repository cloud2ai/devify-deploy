# Blue/green first go-live runbook (issue #17)

Concrete steps to switch aimychats production from the old single-container
deploy to single-node blue/green, and to prove the zero-downtime switch and
rollback afterwards. Run everything on the production host as the deploy user,
from `~/devify-deploy`.

Terms: **active color** = the color nginx currently routes to; **idle color** =
the other one. Only `devify-api` / `devify-ui` are colored.

---

## 0. Pre-flight (no traffic impact)

1. Merge both PRs: `cloud2ai/devify#18` and `cloud2ai/devify-deploy#1`.
2. On the host, refresh the deploy repo:
   ```bash
   cd ~/devify-deploy && git pull --ff-only origin main
   ```
3. Record the current running version (your fallback) and back up MySQL:
   ```bash
   docker inspect -f '{{.Config.Image}}' devify-api        # note the tag
   # take your usual MySQL backup here
   ```
4. Validate the merged compose without changing anything:
   ```bash
   ./scripts/devify-deploy.sh config
   ```
   Expect: "Compose configuration is valid."

## 1. Rehearse on the host with --local (no traffic impact)

`--local` runs the real flow against the already-present images and the current
`.devify` checkout, skipping every git sync and image pull. It still starts an
idle color and health-gates it, so do this in a maintenance window if the host
is tight on resources; it does not switch traffic on its own for a first run.

```bash
# Ensure .devify is at the version you will ship (a normal deploy or:)
DEVIFY_REF=v<VERSION> ./scripts/devify-deploy.sh pull   # once, to fetch images
# Dry-run the flow against local images:
DEVIFY_REF=v<VERSION> ./scripts/devify-deploy.sh upgrade --local
```
Watch the log: it should bring up the idle color, report it healthy, and only
then touch nginx. Abort (Ctrl-C) is safe before the switch line.

## 2. First cutover (one-time sub-second blip — low-traffic window)

The first switch from the single-container stack recreates the nginx container
(single-file mount -> conf.d directory mount). The new color is health-gated up
*before* nginx is recreated, so the blip is just nginx restarting (sub-second).

```bash
DEVIFY_REF=v<VERSION> ./scripts/devify-deploy.sh upgrade
```
Expected sequence in the log: first-install detected -> migrate (no-op if
already applied) -> start blue -> **healthy** -> nginx onto conf.d -> old single
`devify-api`/`devify-ui` removed -> serving **blue**.

> First install has **no previous color to fall back to**. If blue never becomes
> healthy the deploy aborts; your fallback is the recorded single-container image
> (re-run the previous deploy method). Keep those images on the host until step 4
> succeeds.

## 3. Verify

```bash
./scripts/devify-deploy.sh status                       # active=blue, healthy
curl -fsS https://app.aimychats.com/health              # 200
```
Also check by hand: a UI page, the admin port, an `/attachments/...` URL, and
send a test mail through haraka. Confirm nothing regressed.

## 4. Prove the switch + rollback (next deploy — this is the real payoff)

The **second** deploy exercises the true zero-downtime path (blue -> green with
an nginx reload, not a recreate). Trigger it via a normal tag release (CI runs
`devify-deploy.sh upgrade`) or manually:

```bash
DEVIFY_REF=v<NEXT_VERSION> ./scripts/devify-deploy.sh upgrade
```
While it runs, from another shell keep a load loop and expect **zero** non-200s:
```bash
while :; do curl -fsS -o /dev/null https://app.aimychats.com/health \
  || echo "FAIL $(date)"; done
```
After it lands, drill rollback (must return to the previous version without a
rebuild, using the pinned `.rollback_version`):
```bash
./scripts/devify-deploy.sh status                       # active=green
./scripts/devify-deploy.sh rollback                     # -> blue, pinned version
./scripts/devify-deploy.sh status                       # active=blue
```
Roll forward again when satisfied.

## 5. Steady state

- Releases: push a `v*` tag; CI builds/pushes images and runs
  `devify-deploy.sh upgrade` = a health-gated zero-downtime switch.
- Rollback anytime: `./scripts/devify-deploy.sh rollback` (seconds, no rebuild).
- Runtime state on the host (git-ignored): `.active_color`, `.rollback_version`,
  `data/nginx/conf.d/active-upstream.conf`.

## Notes / limits

- Single shared MySQL: keep migrations expand/contract (backward-compatible for
  the observe window) — see the compose overlay comments and playbook §5.3.
- Single-node only. `devify-home` and stateful services are not colored.
- The one-time first-cutover blip (step 2) is the only non-zero-downtime moment;
  every subsequent deploy is a reload.
