# Security policy

The app holds credentials for your opencode servers, and those servers can run commands on your computer. Please report vulnerabilities privately.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open this repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue, discussion or pull request.

Please include:

- the component: the iPhone and iPad app (with its notification service extension and widgets), the push plugin, the push relay or the shared push contracts;
- the app version and build, or the commit if you built it yourself;
- the opencode server version (`opencode --version`), and how the app reaches the server (same network, Tailscale, HTTPS or OpenTunnel);
- the steps to reproduce, and what an attacker gains.

The report stays private while it is investigated and fixed. It is published as a GitHub security advisory once a fix is released, with credit to you unless you would rather not be named.

## Scope

| Component | Path |
| --- | --- |
| The iPhone and iPad app, its notification service extension and its widgets | `App/`, `Extensions/`, `Packages/OpencodeKit/` |
| The push plugin that runs inside your opencode server | `server/plugin/` |
| The push relay | `server/relay/` |
| The push payload, envelope, digest and risk rules shared by all three | `server/contracts/` |

Examples of what matters most:

- reading or forging push content without the device's key;
- approving a permission request the user did not see, or approving one from a notification when the app should require opening it;
- getting at server passwords, pairing tokens or provider secrets;
- abusing the relay to reach devices or servers other than your own.

Problems in opencode itself belong to the [opencode project](https://github.com/anomalyco/opencode). If you run your own relay, the security of that deployment (its APNs key, its Cloudflare account) is yours to manage.

The design behind these guarantees is in [ARCHITECTURE.md](ARCHITECTURE.md): section 4 covers push and section 5 the security model.

## Supported versions

Fixes go to `main` and ship in the next release. Only the latest release of the app, the plugin and the relay is supported.
