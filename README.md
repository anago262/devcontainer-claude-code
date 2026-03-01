# Dev Container for Claude Code

Claude Code 開発環境の共通ベースイメージ。GHCR に公開し、各プロジェクトから `image:` 参照で利用する。

## 含まれるもの

| カテゴリ | 内容 |
|---------|------|
| ランタイム | Node.js 20, npm, Bun |
| AI ツール | Claude Code, Playwright (Chromium + Chrome) |
| MCP 基盤 | claude-mem, ChromaDB, ONNX 埋め込みモデル |
| MCP キャッシュ | Context7, Playwright, GitHub, Brave Search, draw.io, spec-workflow |
| 開発ツール | git, gh (GitHub CLI), delta, fzf, jq, nano, vim, uv/uvx |
| シェル | zsh + Powerlevel10k |
| ネットワーク | iptables, ipset, dnsutils, aggregate（ファイアウォール用） |

## 3 層ファイアウォール

Dev Container 内のネットワークアクセスを制限する `init-firewall.sh` は 3 層構成:

| 層 | ソース | 説明 |
|----|--------|------|
| **Core（固定）** | スクリプト内にハードコード | GitHub, npm, Anthropic, VS Code, Sentry/Statsig |
| **Project（ファイル）** | `.devcontainer/allowed-domains.txt` | プロジェクト固有のドメイン（MCP サーバー等） |
| **Extra（環境変数）** | `EXTRA_ALLOWED_DOMAINS` | アドホックな一時追加（カンマ区切り） |

ワークスペースパスは自動検出される（`/workspace` と `/workspaces/<name>` の両方に対応）。

### Core ドメイン（常に許可）

- `registry.npmjs.org` — npm パッケージ
- `api.anthropic.com` — Claude API
- `sentry.io`, `statsig.anthropic.com`, `statsig.com` — テレメトリ
- `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com` — VS Code
- GitHub（`api.github.com/meta` から自動取得）

## claude-mem スタック

ベースイメージに claude-mem の全インフラが組み込まれている:

| コンポーネント | 説明 |
|---------------|------|
| **ChromaDB** | ベクトル検索バックエンド（pip でインストール済み） |
| **Bun** | claude-mem ワーカーサービスのランタイム |
| **claude-mem** | MCP サーバー + ワーカーサービス（npm -g） |
| **ONNX モデル** | all-MiniLM-L6-v2 埋め込みモデル（事前ダウンロード済み） |

### 起動スクリプト

| スクリプト | 説明 |
|-----------|------|
| `init-claude-mem-settings.sh` | ChromaDB 接続設定、プラグイン登録、hooks 設定 |
| `start-chromadb.sh` | ChromaDB をバックグラウンドで起動（ポート 8100） |
| `start-claude-mem-worker.sh` | claude-mem ワーカーをデーモンとして起動（ポート 37777） |

`postStartCommand` で以下の順に呼び出す:

```bash
sudo /usr/local/bin/init-firewall.sh; /usr/local/bin/init-claude-mem-settings.sh; /usr/local/bin/start-chromadb.sh; /usr/local/bin/start-claude-mem-worker.sh
```

## MCP サーバーキャッシュ

以下の MCP サーバーパッケージがビルド時にキャッシュ済み（初回起動の `npx` が高速化）:

- `@upstash/context7-mcp` — ライブラリドキュメント検索
- `@playwright/mcp` — ブラウザ操作・E2E テスト
- `@modelcontextprotocol/server-github` — GitHub Issue/PR 操作
- `@modelcontextprotocol/server-brave-search` — Web 検索
- `drawio-mcp` — 構成図・設計図作成
- `@pimzino/spec-workflow-mcp` — 仕様管理・タスク分解

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
  "image": "ghcr.io/anago262/devcontainer-claude-code:2",
  "runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"],
  "remoteUser": "node",
  "mounts": [
    "source=claude-code-bashhistory-${devcontainerId},target=/commandhistory,type=volume",
    "source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume",
    "source=claude-mem-data-${devcontainerId},target=/home/node/.claude-mem,type=volume",
    "source=${localEnv:HOME}/.claude/CLAUDE.md,target=/home/node/.claude/CLAUDE.md,type=bind,readonly"
  ],
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true"
  },
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/${localWorkspaceFolderBasename},type=bind,consistency=delegated",
  "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",
  "postStartCommand": "sudo /usr/local/bin/init-firewall.sh; /usr/local/bin/init-claude-mem-settings.sh; /usr/local/bin/start-chromadb.sh; /usr/local/bin/start-claude-mem-worker.sh",
  "waitFor": "postStartCommand"
}
```

### 3. プロジェクト固有ドメインの追加

`.devcontainer/allowed-domains.txt` に 1 行 1 ドメインで記載:

```
# Context7 MCP
context7.com
clerk.context7.com

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
docker run --rm -v "$(pwd)/tests:/workspace/tests" devcontainer-claude-code:local bash tests/test-image.sh
```

### リリース（GHCR パブリッシュ）

```bash
git tag v2.0.0
git push origin v2.0.0
```

GitHub Actions が自動で以下のタグを GHCR に push:
- `ghcr.io/anago262/devcontainer-claude-code:2.0.0`
- `ghcr.io/anago262/devcontainer-claude-code:2.0`
- `ghcr.io/anago262/devcontainer-claude-code:2`
- `ghcr.io/anago262/devcontainer-claude-code:latest`

マルチアーキテクチャ対応: `linux/amd64` + `linux/arm64`
