# Third-party notices

Agentic Vim is an independent Neovim distribution. It is not affiliated with
or endorsed by the Agentic.nvim or Neovim projects.

The installer downloads third-party software from its original distribution
source. Those components remain subject to their own licenses; their license
files are included in the downloaded source trees, packages, or release
archives. Exact plugin revisions are recorded in `nvim/plugins.lock`, and exact
Node package versions are recorded in `provider/package-lock.json`.

## Modified Agentic.nvim

This distribution applies `patches/agentic-hud.patch` to
[Agentic.nvim](https://github.com/carlos-algms/agentic.nvim), originally written
by Carlos Gomes. The patch is a derivative modification and is not an upstream
release.

Agentic.nvim is licensed as follows:

> MIT License
>
> Copyright (c) 2025 Carlos Gomes
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Modified Neo-tree.nvim and nui.nvim

This distribution applies the checksum-pinned
`patches/neo-tree-fs-churn.patch` and `patches/nui-tree-reuse.patch` overlays to
their respective pinned MIT-licensed plugin revisions. These local fixes make
filesystem refresh completion tolerant of paths disappearing mid-scan and
preserve reused tree-node descendants. They are derivative modifications, not
upstream releases.

Neo-tree.nvim copyright: Copyright (c) 2021 cseickel
(<https://github.com/cseickel>) and nvim-neo-tree maintainers.

nui.nvim copyright: Copyright (c) 2021 Munif Tanjim.

Both are licensed under these MIT terms:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Direct installed components

| Component | License | Source |
| --- | --- | --- |
| Neovim | Apache-2.0 and Vim license for inherited portions | <https://github.com/neovim/neovim> |
| Node.js | MIT and licenses for bundled dependencies | <https://github.com/nodejs/node> |
| Tree-sitter CLI | MIT | <https://github.com/tree-sitter/tree-sitter> |
| JetBrainsMono Nerd Font | SIL Open Font License 1.1 | <https://github.com/ryanoasis/nerd-fonts> |
| Agentic.nvim | MIT | <https://github.com/carlos-algms/agentic.nvim> |
| Catppuccin for Neovim | MIT | <https://github.com/catppuccin/nvim> |
| Neo-tree.nvim | MIT | <https://github.com/nvim-neo-tree/neo-tree.nvim> |
| nui.nvim | MIT | <https://github.com/MunifTanjim/nui.nvim> |
| nvim-autopairs | MIT | <https://github.com/windwp/nvim-autopairs> |
| nvim-web-devicons | MIT | <https://github.com/nvim-tree/nvim-web-devicons> |
| plenary.nvim | MIT | <https://github.com/nvim-lua/plenary.nvim> |
| nvim-treesitter | Apache-2.0 | <https://github.com/nvim-treesitter/nvim-treesitter> |
| render-markdown.nvim | MIT | <https://github.com/MeanderingProgrammer/render-markdown.nvim> |
| snacks.nvim | Apache-2.0 | <https://github.com/folke/snacks.nvim> |
| Codex CLI | Apache-2.0 | <https://github.com/openai/codex> |
| codex-acp | Apache-2.0 | <https://github.com/agentclientprotocol/codex-acp> |
| Pyright | MIT | <https://github.com/microsoft/pyright> |

Tree-sitter language grammars and transitive Node packages have their own
licenses. Their source packages and license metadata are obtained by the
upstream installers rather than copied into this repository.

Product and project names belong to their respective owners. Their appearance
here identifies compatibility or provenance and does not imply endorsement.
