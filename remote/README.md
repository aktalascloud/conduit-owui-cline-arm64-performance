# OWUI + Cline remote access

Conduit opens the installed Cline Hub dashboard through an encrypted SSH tunnel. Cline, its providers, sessions and project files stay on the PC. The APK contains no Cline binary, provider credential or configured server address.

## Windows

Install Python 3.12+ and Cline Desktop. Clone this repository and run:

```powershell
.\remote\Setup.cmd -HostAddress your-host.example -ListenAddress 0.0.0.0 -Workspace C:\Projects\Example -InstallStartup -Start
```

Use `-ClineCli` and `-ClineConfig` for a different installed CLI/profile. Setup creates a private directory under Local AppData, a persistent Ed25519 host key and two independent random access secrets. It prints only the connection-document path. Existing keys are retained. The optional login shortcut starts the gateway outside Codex.

For public access, allow inbound TCP 2222 for the gateway interpreter and forward that one router port to the PC. Keep the dashboard port 11280 on loopback. Restrict access by source IP when practical. No VPN subscription is required.

## Android

Install the signed OWUI + Cline APK. In Conduit, open **Cline via SSH** on the first screen (also in Accounts/Settings), import the private `connection.json` from the PC, and connect. Transfer it privately; never publish it. Connection settings are saved only in secure device storage. The server fingerprint must match; there is no trust-all fallback.

Open an existing session in the dashboard, or choose a PC project folder before starting a new session. Existing sessions keep their own folder. The dashboard uses its Cline UI; the native connection screen supports English and Russian. Sign in to model providers on the PC if needed.

## Scope and security

- Shell, SFTP, reverse forwarding and arbitrary TCP destinations are rejected. Only the local Cline dashboard and one fixed upload RPC are reachable.
- Host-key pinning, independent dashboard authentication, bounded connections/login attempts and no automatic command replay are enforced.
- Cline's approvals remain enabled. An already running Desktop turn can retain its original approval owner; subsequent turns started from the dashboard use its approval prompts.
- An SSH connection does **not** protect an internet connection from volumetric DDoS. Use an upstream protected service or private VPN when that is required.
- A disconnected phone is not a request to replay a message. Read the session state before manually retrying uncertain actions.

Conduit remains GPL-3.0. Cline is separately installed under its own license; see [Cline](https://github.com/cline/cline). Dart SSH dependencies retain their package notices; AsyncSSH is available under EPL-2.0 or GPL-2.0-or-later. Private configuration, keys and runtime data must stay outside the checkout and releases.

## Images and documents

Use the paperclip to transfer a file through SSH into the private PC `user-uploads` inbox. Size and SHA256 are verified; identical uploads reuse the same content-addressed file. Limits: 64 MiB/file, 1 GiB/inbox, 4 attachments/message. Images up to 8 MiB also use the normal `userImages` field; other files are referenced by their PC path. Image understanding requires a vision-capable model. Cline reads documents with its normal tools and approval rules.

Files attach only to the next message you send yourself. Clear pending attachments before sending if needed. Completed uploads are user data, never disposable cache. No shell, SFTP or arbitrary destination path is exposed. Desktop voice input is configured separately in Cline.
