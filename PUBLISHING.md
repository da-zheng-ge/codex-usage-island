# Publishing

## GitHub CLI

From the repository root, authenticate once if needed:

```powershell
gh auth login
```

Create a public GitHub repository and push `main`:

```powershell
gh repo create codex-usage-island --public --source . --remote origin --push `
  --description "Unofficial Windows usage island for OpenAI Codex"
```

Create the first release from the generated artifacts:

```powershell
gh release create v1.0.0 `
  ..\codex-usage-island-v1.0.0.zip `
  ..\codex-usage-island-v1.0.0.zip.sha256 `
  --title "Codex Usage Island v1.0.0" `
  --notes-file CHANGELOG.md
```

## Before publishing

- Review the repository diff and release archive.
- Confirm the archive contains no `.git` directory, binaries, credentials, logs, or machine-specific paths.
- Enable GitHub Security Advisories.
- Add repository topics such as `codex`, `powershell`, `wpf`, `windows`, and `usage-monitor`.
- Keep the unofficial-project disclaimer visible in the repository description and README.
