# Changelog

## [0.5.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.4.0...v0.5.0) (2026-02-28)


### ⚠ BREAKING CHANGES

* **provider:** replace providers with simpler, more maintainable server option

### Features

* **server:** allow _all_ servers (but prioritize sharing CWD still) ([6d00f30](https://github.com/nickjvandyke/opencode.nvim/commit/6d00f3094af83748f94224647f62a215bca6a920))


### Bug Fixes

* **ask:** preserve formatting in completion docs ([9048f10](https://github.com/nickjvandyke/opencode.nvim/commit/9048f10130f76a39c4b5d0ba77890ec5031bb543))
* **client:** prevent hanging when `opencode` is suspended ([#183](https://github.com/nickjvandyke/opencode.nvim/issues/183)) ([c1afcf5](https://github.com/nickjvandyke/opencode.nvim/commit/c1afcf5ab4dce992ee41108fb056522db7385dd6))
* **context:** always pick the longer of overlapping placeholders ([e4f7555](https://github.com/nickjvandyke/opencode.nvim/commit/e4f755591db3ddf7b9ff6dcb4ae469faa36926b6))
* **context:** diagnostics context error ([a4dff90](https://github.com/nickjvandyke/opencode.nvim/commit/a4dff90c1a13b0bc5fdfc750feeba4e2501f5ef5))
* **context:** remove filename space suffix when no location, use `:`, join list contexts with `, ` ([8992d0c](https://github.com/nickjvandyke/opencode.nvim/commit/8992d0c6168ad28f91b03f7dcdb98b5ebb675c32))
* **server:** cache connected server even when events are disabled ([6b3eed0](https://github.com/nickjvandyke/opencode.nvim/commit/6b3eed0bce4c4cff928a8ef7222a0513382adcfc))
* **server:** don't needlessly reconnect to server ([1b90ae8](https://github.com/nickjvandyke/opencode.nvim/commit/1b90ae8936245255786b7789496f7d910ab8434d))
* **server:** more reliably detect server disappearing ([67a09c8](https://github.com/nickjvandyke/opencode.nvim/commit/67a09c88ca2326c12e6ca02ffa669f716341ddf1))
* **server:** race condition that'd disconnect from newly selected server ([c72a7bf](https://github.com/nickjvandyke/opencode.nvim/commit/c72a7bf28ac13fc54e3f12a99554b2309d0da175))


### Code Refactoring

* **provider:** replace providers with simpler, more maintainable server option ([82332cf](https://github.com/nickjvandyke/opencode.nvim/commit/82332cf924458dc9b6fcaecf25f52111544a1663))

## [0.4.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.3.0...v0.4.0) (2026-02-20)


### Features

* **lsp:** add code action to explain diagnostic under cursor ([8d95230](https://github.com/nickjvandyke/opencode.nvim/commit/8d9523081e89dc1775a2ac91ae1c2922d8293bd8))
* **lsp:** add hover functionality. disable lsp by default for stability. ([7d410cc](https://github.com/nickjvandyke/opencode.nvim/commit/7d410cc2c2f4d708fc79491c9d8ab0ff46a04116))
* **lsp:** add persistent in-process LSP, and code action to fix diagnostics ([a841138](https://github.com/nickjvandyke/opencode.nvim/commit/a841138e056f337c6ee7ad0aad0cc18b36806deb))
* **lsp:** allow configuring model ([bdb59d8](https://github.com/nickjvandyke/opencode.nvim/commit/bdb59d85ab8d1f323c4596dac9efc0229ab74fec))


### Bug Fixes

* **ask:** blink.cmp error when highlighting ([0a5306e](https://github.com/nickjvandyke/opencode.nvim/commit/0a5306ecd0e3d3a9358e8a6b15b55da12d611278))
* **provider:** more reliable autocmd for calling stop on exit ([1e31bbc](https://github.com/nickjvandyke/opencode.nvim/commit/1e31bbcea06966c004eb3b41e54e1c74136227c8))
* **provider:** reliably kill orphaned `opencode` in terminal, snacks, and tmux providers ([#168](https://github.com/nickjvandyke/opencode.nvim/issues/168)) ([125c7dc](https://github.com/nickjvandyke/opencode.nvim/commit/125c7dc991996446f4529ed6aa9e58965dbb9d01))
* **tmux:** cleanly shutdown `opencode` ([#178](https://github.com/nickjvandyke/opencode.nvim/issues/178)) ([1d1b39f](https://github.com/nickjvandyke/opencode.nvim/commit/1d1b39fd0f4a3951b048be944ed2a65348aad3f8))

## [0.3.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.2.0...v0.3.0) (2026-02-18)


### Features

* **ask:** end prompt with `\n` or press `<C-CR>` to append instead of submit ([65ce845](https://github.com/nickjvandyke/opencode.nvim/commit/65ce8453a9e73fc259c6d1899b3b99778e754108))
* **ask:** send actual newline to `opencode` when used to make ask append ([7cffee3](https://github.com/nickjvandyke/opencode.nvim/commit/7cffee32e5b7ab8cfbe5a8217ae563555f973220))
* **ask:** support all completion plugins via in-process LSP :D ([55ae1e5](https://github.com/nickjvandyke/opencode.nvim/commit/55ae1e5a75d46fadf450699f7b267a0be12940f3))
* **ask:** use `<S-CR>` instead of `<C-CR>` to append - more standard ([72e85ae](https://github.com/nickjvandyke/opencode.nvim/commit/72e85ae13a37213195d35b334739de6f3bc8f4b4))
* **snacks:** add `snacks.picker` action to send items to `opencode` ([#152](https://github.com/nickjvandyke/opencode.nvim/issues/152)) ([e478fce](https://github.com/nickjvandyke/opencode.nvim/commit/e478fce4a7d05e1ee0e0aed8cb582f0501228183))


### Bug Fixes

* **ask:** locate LSP module where it can reliably be found ([5336d93](https://github.com/nickjvandyke/opencode.nvim/commit/5336d93b4895b9c25940ca5e8194291ae16e59ed))
* **server:** do not search for other servers when port is configured ([#175](https://github.com/nickjvandyke/opencode.nvim/issues/175)) ([9fa26f0](https://github.com/nickjvandyke/opencode.nvim/commit/9fa26f0146fa00801f2c0eaefb4b75f0051d7292))

## [0.2.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.1.0...v0.2.0) (2026-02-09)


### Features

* **provider:** normal mode keymaps for navigating messages ([#151](https://github.com/nickjvandyke/opencode.nvim/issues/151)) ([a847e5e](https://github.com/nickjvandyke/opencode.nvim/commit/a847e5e5a6b738ed56b30c9dbb66d161914bb27c))
* select from available `opencode` servers ([fa26e86](https://github.com/nickjvandyke/opencode.nvim/commit/fa26e865200ceb0841284c9f2e86ffbd2d353233))


### Bug Fixes

* **select:** dont error when not in a git repository ([5de2380](https://github.com/nickjvandyke/opencode.nvim/commit/5de2380a4e87d493149838eab6599cf9f4b33a3e))
