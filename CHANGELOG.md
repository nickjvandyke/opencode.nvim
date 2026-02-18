# Changelog

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
