FROM node:20

LABEL org.opencontainers.image.title="Dev Container for Claude Code"
LABEL org.opencontainers.image.description="Shared base image for Claude Code development environments"
LABEL org.opencontainers.image.source="https://github.com/anago262/devcontainer-claude-code"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="anago262"

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools, iptables/ipset, and python3-pip (for ChromaDB)
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  python3-pip \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv/uvx (for Serena MCP server)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install ChromaDB (claude-mem vector search backend)
RUN pip3 install --break-system-packages chromadb

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Bun (claude-mem worker service runtime)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/home/node/.bun/bin:$PATH"

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Install claude-mem (MCP server + worker service)
RUN npm install -g claude-mem
ENV CLAUDE_MEM_SCRIPTS="/usr/local/share/npm-global/lib/node_modules/claude-mem/plugin/scripts"

# Create claude-mem directories and hook fallback symlink
# claude-mem hooks expect plugin at ~/.claude/plugins/marketplaces/thedotmack/plugin
# but npm -g installs to /usr/local/share/npm-global/lib/node_modules/claude-mem/plugin
RUN mkdir -p /home/node/.claude-mem /home/node/.claude/plugins/marketplaces/thedotmack \
  && ln -s /usr/local/share/npm-global/lib/node_modules/claude-mem/plugin \
     /home/node/.claude/plugins/marketplaces/thedotmack/plugin

# Pre-download ChromaDB ONNX embedding model (all-MiniLM-L6-v2)
# Avoids runtime download which may be blocked by network restrictions
RUN python3 -c "from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2; ef = ONNXMiniLM_L6_V2(); ef(['warmup'])"

# Pre-install MCP server packages at build time (avoids slow npx warmup on every start)
RUN npx -y @upstash/context7-mcp@latest --help > /dev/null 2>&1 || true & \
    npx -y @playwright/mcp@latest --help > /dev/null 2>&1 || true & \
    npx -y @modelcontextprotocol/server-brave-search --help > /dev/null 2>&1 || true & \
    npx -y drawio-mcp --help > /dev/null 2>&1 || true & \
    npx -y @modelcontextprotocol/server-github --help > /dev/null 2>&1 || true & \
    npx -y @pimzino/spec-workflow-mcp@latest --help > /dev/null 2>&1 || true & \
    wait

# Playwright: install browsers with system dependencies (requires root)
# Chromium: default for Playwright test automation
# Chrome: default for Playwright MCP server
# --with-deps installs both system deps and browser binaries in one step
USER root
RUN npx -y playwright install --with-deps chromium chrome && \
    chown -R node:node /home/node/.cache/ms-playwright
USER node

# Copy firewall script and startup scripts
COPY init-firewall.sh /usr/local/bin/
COPY scripts/ /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh \
    /usr/local/bin/start-chromadb.sh \
    /usr/local/bin/start-claude-mem-worker.sh \
    /usr/local/bin/init-claude-mem-settings.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
