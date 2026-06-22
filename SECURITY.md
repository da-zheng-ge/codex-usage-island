# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories rather than opening a public issue.

Include the affected version, reproduction steps, and expected impact. Do not include Codex credentials, access tokens, private prompts, or session transcripts.

## Scope

The project launches the locally installed Codex app-server and reads local session event metadata. It must never collect or transmit authentication material. Changes that add networking, telemetry, credential access, or prompt-content parsing require explicit security review.
