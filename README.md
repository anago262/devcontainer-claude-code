# Dev Container for Claude Code

Claude Code 開発環境の共通ベースイメージ。GHCR に公開し、各プロジェクトから `image:` 参照で利用する。

## 含まれるもの

| カテゴリ | 内容 |
|---------|------|
| ランタイム | Node.js 20, npm |
| AI ツール | Claude Code, Playwright (Chromium) |
| 開発ツール | git, gh (GitHub CLI), delta, fzf, jq, nano, vim |
| シェル | zsh + Powerlevel10k |
| ネットワーク | iptables, ipset, dnsutils, aggregate（ファイアウォール用） |

## 3 層ファイアウォール

Dev Container 内のネットワークアクセスを制限する `init-firewall.sh` は 3 層構成:

| 層 | ソース | 説明 |
|----|--------|------|
| **Core（固定）** | スクリプト内にハードコード | GitHub, npm, Anthropic, VS Code, Sentry/Statsig |
| **Project（ファイル）** | `/workspace/.devcontainer/allowed-domains.txt` | プロジェクト固有のドメイン（MCP サーバー等） |
| **Extra（環境変数）** | `EXTRA_ALLOWED_DOMAINS` | アドホックな一時追加（カンマ区切り） |

### Core ドメイン（常に許可）

- `registry.npmjs.org` — npm パッケージ
- `api.anthropic.com` — Claude API
- `sentry.io`, `statsig.anthropic.com`, `statsig.com` — テレメトリ
- `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com` — VS Code
- GitHub（`api.github.com/meta` から自動取得）

## 使い方

### 1. プロジェクトに Dev Container 設定を追加

`templates/` ディレクトリのファイルを参考に、プロジェクトの `.devcontainer/` に以下を配置:

```
.devcontainer/
  devcontainer.json       # templates/devcontainer.json をコピー・カスタマイズ
  allowed-domains.txt     # プロジェクト固有の許可ドメイン（任意）
```

プロジェクトルートに MCP 設定を配置:

```
.mcp.json                 # templates/.mcp.json をコピー・カスタマイズ
```

### 2. `devcontainer.json` の最小構成

```jsonc
{
  "name": "My Project",
  "image": "ghcr.io/anago262/devcontainer-claude-code:1",
  "runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"],
  "remoteUser": "node",
  "mounts": [
    "source=claude-code-bashhistory-${devcontainerId},target=/commandhistory,type=volume",
    "source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume",
    "source=${localEnv:HOME}/.claude/CLAUDE.md,target=/home/node/.claude/CLAUDE.md,type=bind,readonly"
  ],
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true"
  },
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "postStartCommand": "sudo /usr/local/bin/init-firewall.sh",
  "waitFor": "postStartCommand"
}
```

### 3. プロジェクト固有ドメインの追加

`.devcontainer/allowed-domains.txt` に 1 行 1 ドメインで記載:

```
# Context7 MCP
mcp.context7.com
api.context7.com

# Playwright downloads
cdn.playwright.dev
playwright.download.prss.microsoft.com

# Brave Search
api.search.brave.com
```

### 4. 環境変数でアドホックにドメインを追加

`devcontainer.json` の `containerEnv` に追加:

```jsonc
"containerEnv": {
  "EXTRA_ALLOWED_DOMAINS": "api.example.com,cdn.example.com"
}
```

## 開発

### ローカルビルド

```bash
docker build -t devcontainer-claude-code:local .
```

### テスト実行

```bash
docker run --rm devcontainer-claude-code:local bash tests/test-image.sh
```

### リリース（GHCR パブリッシュ）

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions が自動で以下のタグを GHCR に push:
- `ghcr.io/anago262/devcontainer-claude-code:1.0.0`
- `ghcr.io/anago262/devcontainer-claude-code:1.0`
- `ghcr.io/anago262/devcontainer-claude-code:1`
- `ghcr.io/anago262/devcontainer-claude-code:latest`

マルチアーキテクチャ対応: `linux/amd64` + `linux/arm64`
