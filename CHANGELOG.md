# Changelog

## [0.9.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.8.3...v0.9.0) (2026-05-16)


### ⚠ BREAKING CHANGES

* **config:** move `opts.prompts` to `opts.select.prompts`, unnest `opts.select.sections`
* **prompts:** simplify `opts.prompts` to string, use postfixes for ask and append
* **api:** only expose select server and session in `select` menu, not API

### Features

* **api:** only expose select server and session in `select` menu, not API ([fcfd017](https://github.com/nickjvandyke/opencode.nvim/commit/fcfd017a908a820085c04e8aba06153d76e55c92))
* **config:** move `opts.prompts` to `opts.select.prompts`, unnest `opts.select.sections` ([e2288db](https://github.com/nickjvandyke/opencode.nvim/commit/e2288db06c3865b0703d93c1d434a870ca119e43))
* **prompt:** replace `opts.submit` with ending space ([f6e1efd](https://github.com/nickjvandyke/opencode.nvim/commit/f6e1efd3455f0c56d8e45c517d148406f7cb19e3))
* **prompts:** simplify `opts.prompts` to string, use postfixes for ask and append ([48d0965](https://github.com/nickjvandyke/opencode.nvim/commit/48d09650dad64677c1318eab8de5458211b98835))
* **select:** clarify server item descriptions ([f7cd638](https://github.com/nickjvandyke/opencode.nvim/commit/f7cd63801da202b345cf030ee4acec3cec260d90))


### Bug Fixes

* **context:** highlighting visual block mode ([82ba668](https://github.com/nickjvandyke/opencode.nvim/commit/82ba6686ff7acdc39cb2ed019908d20f7a52b66d))
* **select:** override prompts and commands with passed opts ([bbed2b7](https://github.com/nickjvandyke/opencode.nvim/commit/bbed2b758c652e2b6262fede6ea5b298e852143e))

## [0.8.3](https://github.com/nickjvandyke/opencode.nvim/compare/v0.8.2...v0.8.3) (2026-05-15)


### Features

* **server:** support auth ([0dd8824](https://github.com/nickjvandyke/opencode.nvim/commit/0dd88243b151b25e291e714d572d303a694b5f7c))


### Bug Fixes

* **config:** ensure all config type defs can be found by Lua LSP ([03da482](https://github.com/nickjvandyke/opencode.nvim/commit/03da4820f30e8a6dce6d4f366e59eaa8f1f6d130))

## [0.8.2](https://github.com/nickjvandyke/opencode.nvim/compare/v0.8.1...v0.8.2) (2026-05-06)


### Bug Fixes

* **context:** reference file-backed bufs with non-empty buftype ([f77904d](https://github.com/nickjvandyke/opencode.nvim/commit/f77904d53bee4618e0b1e92796db4f154739777d))

## [0.8.1](https://github.com/nickjvandyke/opencode.nvim/compare/v0.8.0...v0.8.1) (2026-05-01)


### Bug Fixes

* **server:** correctly detect and discard discovered non-servers ([#244](https://github.com/nickjvandyke/opencode.nvim/issues/244)) ([97fbb2a](https://github.com/nickjvandyke/opencode.nvim/commit/97fbb2afde37d48d4bf4f222af559f179f54a043))
* **server:** process discovery on NixOS ([#245](https://github.com/nickjvandyke/opencode.nvim/issues/245)) ([840b2fa](https://github.com/nickjvandyke/opencode.nvim/commit/840b2fa8c3c03d716a4018a736797b9c6aed046b))

## [0.8.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.7.0...v0.8.0) (2026-04-29)


### ⚠ BREAKING CHANGES

* **ask:** trigger append on space suffix instead of \n; remove snacks.input append keymap
* **prompts:** remove resolving named prompts in `prompt()`

### Features

* **ask:** trigger append on space suffix instead of \n; remove snacks.input append keymap ([ceb0371](https://github.com/nickjvandyke/opencode.nvim/commit/ceb03717b7bb2060d8d3504b8d56017035f0edcc))
* **lsp:** attach to connected server (if any) for hover ([f5a8413](https://github.com/nickjvandyke/opencode.nvim/commit/f5a841314dd5a189fe2d34630cf7d3e6386d731d))
* **prompts:** remove resolving named prompts in `prompt()` ([16e2243](https://github.com/nickjvandyke/opencode.nvim/commit/16e2243ae66aee81b397e9799cb5e272bdaa6d32))
* **server:** don't auto-select servers that don't overlap CWD ([ad48ee2](https://github.com/nickjvandyke/opencode.nvim/commit/ad48ee24c7e2f90305134ca7762ca00c639a18e3))


### Bug Fixes

* **server:** emit one process entry per (PID, port) pair ([#242](https://github.com/nickjvandyke/opencode.nvim/issues/242)) ([0e3ae21](https://github.com/nickjvandyke/opencode.nvim/commit/0e3ae21c6c4c8def63e3503b238870f1251288e4))
* **server:** poll for 5s to account for slow `opencode` startup ([4002092](https://github.com/nickjvandyke/opencode.nvim/commit/4002092d701007acbb5b8fb1a47924ea719241b0))
* **terminal:** don't override focus behavior of other terminal integrations ([b3cdd74](https://github.com/nickjvandyke/opencode.nvim/commit/b3cdd746a5ca321b6884badefa0ba22c86c3d45e))

## [0.7.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.6.0...v0.7.0) (2026-04-07)


### ⚠ BREAKING CHANGES

* **config:** remove undocumented ability to clear built-in contexts and prompts
* remove buggy `opts.clear` from `ask` and `prompt`

### Bug Fixes

* remove buggy `opts.clear` from `ask` and `prompt` ([3a0b484](https://github.com/nickjvandyke/opencode.nvim/commit/3a0b484831f9edb1aac6423b30093a03335672f2))
* **terminal:** fallback win opts for backwards-compat ([fd7b4e5](https://github.com/nickjvandyke/opencode.nvim/commit/fd7b4e5899a4ade903e8bee4305ac72c1a36f522))


### Code Refactoring

* **config:** remove undocumented ability to clear built-in contexts and prompts ([78b720d](https://github.com/nickjvandyke/opencode.nvim/commit/78b720dfa6a55c3e2d167165320adc5c0ae87471))

## [0.6.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.5.2...v0.6.0) (2026-03-29)


### Features

* diff and accept/reject `opencode` edits ([8b4ec07](https://github.com/nickjvandyke/opencode.nvim/commit/8b4ec075cbaf869bb86f1a52e78f1478ea525000))
* **edits:** allow separately disabling edit permissions ([8804ffb](https://github.com/nickjvandyke/opencode.nvim/commit/8804ffb81f9784dcd0e9af43a2068fb55282c4dd))
* **permissions:** fallback to generic permissions for edits when edits disabled ([53014bc](https://github.com/nickjvandyke/opencode.nvim/commit/53014bc40fbe529a26c6feafbe395ffe5e3acda5))
* **server:** support arbitrary port discovery ([5067c80](https://github.com/nickjvandyke/opencode.nvim/commit/5067c80ee1f37b5f8a54244e184df44944175a84))


### Bug Fixes

* **checkhealth:** check `opencode` patch version only when minor matches ([#217](https://github.com/nickjvandyke/opencode.nvim/issues/217)) ([ecd6e9b](https://github.com/nickjvandyke/opencode.nvim/commit/ecd6e9b50d732280ef63f325ec29ec206f78be71))
* **context:** use only listed buffers for `[@buffers](https://github.com/buffers)` ([#213](https://github.com/nickjvandyke/opencode.nvim/issues/213)) ([e64a4a1](https://github.com/nickjvandyke/opencode.nvim/commit/e64a4a1172401a9dffd732bf61f032d038fd947c))
* **diff:** don't close the diff after accepting/rejecting a single hunk ([c7adcfe](https://github.com/nickjvandyke/opencode.nvim/commit/c7adcfe997535add53ac094a564a15348ab0c0de))
* empty err notification when `command` server selection is cancelled ([9db5914](https://github.com/nickjvandyke/opencode.nvim/commit/9db59145730ff9b8029b3dc9c5c6e714cd5485a8))
* **permissions:** error when replying to request ([931f94b](https://github.com/nickjvandyke/opencode.nvim/commit/931f94b99a6f70af43f5f7bce897a9e127b167c0))
* **status:** handle new event types for busy and idle states, update permission event type ([3d07744](https://github.com/nickjvandyke/opencode.nvim/commit/3d07744a05cc682c6706db21d90e43e513702dc4))
* **terminal:** exclude from session ([f8c46ed](https://github.com/nickjvandyke/opencode.nvim/commit/f8c46edbc1a905f35db3c076ee6cee73eab3df65))
* **terminal:** prevent appearing in bufferline ([#214](https://github.com/nickjvandyke/opencode.nvim/issues/214)) ([4f4ff2c](https://github.com/nickjvandyke/opencode.nvim/commit/4f4ff2c2a4bd979bf8f20a90e44be1b86855cfea))

## [0.5.2](https://github.com/nickjvandyke/opencode.nvim/compare/v0.5.1...v0.5.2) (2026-03-06)


### Bug Fixes

* **server:** error correctly when no processes found on Unix ([df98bfb](https://github.com/nickjvandyke/opencode.nvim/commit/df98bfba94190ca3584f862f5f0526c6dcd016fc))
* **terminal:** rare error when exiting Neovim and killing `opencode` ([c451511](https://github.com/nickjvandyke/opencode.nvim/commit/c451511a27d1a9c05bab173c919ef882cd6f72f3))

## [0.5.1](https://github.com/nickjvandyke/opencode.nvim/compare/v0.5.0...v0.5.1) (2026-03-03)


### Bug Fixes

* **server:** sometimes returned processes without ports ([#195](https://github.com/nickjvandyke/opencode.nvim/issues/195)) ([12a7c4e](https://github.com/nickjvandyke/opencode.nvim/commit/12a7c4e5496cd6a2c38533356c37bb7f3ee6d4d7))

## [0.5.0](https://github.com/nickjvandyke/opencode.nvim/compare/v0.4.0...v0.5.0) (2026-03-02)


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
* **health:** error when opts.server isn't configured ([37468a4](https://github.com/nickjvandyke/opencode.nvim/commit/37468a41d87fd71b4cc6180c5811d6719442f525))
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
