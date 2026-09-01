# Changelog

## [1.2.0](https://github.com/Azure/osdu-spi/compare/v1.1.0...v1.2.0) (2026-09-01)


### ✨ Features

* **acceptance-resolver:** Add descriptor-driven acceptance env resolver ([6cafa60](https://github.com/Azure/osdu-spi/commit/6cafa60bf6ef9611984ccc75b65d5a585d40c858))
* **build:** Enable multi-arch docker image with entrypoint script ([5443d47](https://github.com/Azure/osdu-spi/commit/5443d470b9325ae2ebdf6538db7527ce44a61437))
* **build:** Multi-arch service images on Microsoft Azure Linux base ([7e8caeb](https://github.com/Azure/osdu-spi/commit/7e8caebd27e70b85004799b47e189c7f96d0d97c))
* **cascade:** Enable merge commits and improve auto-merge error reporting ([073cb57](https://github.com/Azure/osdu-spi/commit/073cb57a94d9709769c5a75b2c54a2b36d6d1212))
* **cascade:** Enforce merge-commit method via auto-merge on release PRs ([5c3540c](https://github.com/Azure/osdu-spi/commit/5c3540caed8c0df30aa7481063a2b3faa9b7c74e))
* **ci:** Acceptance test images in the docker lane ([3a235c6](https://github.com/Azure/osdu-spi/commit/3a235c6efb84189a28b4ef1132b4b1b5c189ba7f))
* **ci:** Add acceptance test image build and publish pipeline ([f694f06](https://github.com/Azure/osdu-spi/commit/f694f0670d27231168f76a349377558d6f18fd28))
* **ci:** Add fork repository setup automation with GitHub App token support ([19fbac5](https://github.com/Azure/osdu-spi/commit/19fbac5aa63d2a148c75d90a5597aa415e54c474))
* **ci:** Add self-healing for stale fork_integration divergence ([684b21b](https://github.com/Azure/osdu-spi/commit/684b21b675e38455301c910baea110b4a4a95aa0))
* **ci:** Build and publish service container images to GHCR ([2e40e87](https://github.com/Azure/osdu-spi/commit/2e40e874a39a2006ba1cd9075abd570423a62311))
* **ci:** Use GitHub App token for cascade PR creation ([3a3b1ab](https://github.com/Azure/osdu-spi/commit/3a3b1abf5a2cab26897ae2d2d28c6f6b706f3b97))
* Customer-tier mirror-mode syncing forks ([af7770e](https://github.com/Azure/osdu-spi/commit/af7770e4b8bff70427e1015075ea4cf7e327d868))
* **ghcr:** Enable GHCR as service image registry for SPI ([5019039](https://github.com/Azure/osdu-spi/commit/5019039b89d5d114250822e7120ff2d24ef5b6b6))
* **init:** Generate filtered fork_upstream and seed azure trees ([2987ed9](https://github.com/Azure/osdu-spi/commit/2987ed97fb852637a5092c4a03c9151ef3e3a698))
* **init:** Generate filtered fork_upstream and seed azure trees ([265d003](https://github.com/Azure/osdu-spi/commit/265d0032154c8bd888a0bb04e6327599be9e05c5))
* Service descriptor (schema v3) + acceptance resolver action ([855e936](https://github.com/Azure/osdu-spi/commit/855e936ca8ec7a9150a0bb1a4b392f3f9fdfdcaa))
* **sync:** Add customer-tier mirror mode and fork adoption workflow ([3a776a9](https://github.com/Azure/osdu-spi/commit/3a776a911fe6863c071219067285c5c7fd2eaa07))
* **sync:** Filter upstream syncs to Azure SPI code only ([02aa7dc](https://github.com/Azure/osdu-spi/commit/02aa7dca375eac8d9cea9dc772a13263ff20f501))
* **upstream-filter:** Add generate/verify/stamp/seed engine ([7867576](https://github.com/Azure/osdu-spi/commit/7867576e29251618c280da5092fe821cc9dd9879))
* **upstream-filter:** Generate sync branches via plumbing instead of ([93c5211](https://github.com/Azure/osdu-spi/commit/93c521146b235e9947255b4dd0eb9db28b5091b7))
* **upstream-filter:** Verify injected profiles and modules survive ([a529a70](https://github.com/Azure/osdu-spi/commit/a529a70ec6ff191d5679ba5c04f86754922744f0))


### 🐛 Bug Fixes

* **acceptance-image:** Add sidecar dockerignore for suite build context ([94470d7](https://github.com/Azure/osdu-spi/commit/94470d7def7530a813bd37e302559e2731c8332f))
* **acceptance-image:** Gate push token check on buildable suite ([e64544a](https://github.com/Azure/osdu-spi/commit/e64544a5cc551eb522bceec7240c415315e1f16d))
* **acceptance-image:** Halt when descriptor names a missing suite ([e701432](https://github.com/Azure/osdu-spi/commit/e7014322c57669cfdfc79629c5c0fac685aa6d73))
* **acceptance-resolver:** Guard against non-utf8 input and output ([1906d23](https://github.com/Azure/osdu-spi/commit/1906d239ad52c016a6608a49bfc0e841787e9aba))
* **acceptance-resolver:** Make comment stripping quote-aware ([6903aa0](https://github.com/Azure/osdu-spi/commit/6903aa0eeb654b519bf00b6c8251692929ab874f))
* **acceptance-resolver:** Name unpublished vault as root cause of secret ([ded3369](https://github.com/Azure/osdu-spi/commit/ded33697a4e96134eb226ae92effa3499e57196f))
* **acceptance-resolver:** Pass report path as argv instead of ([7353015](https://github.com/Azure/osdu-spi/commit/7353015472b644b2e889a1fd2f5122814eaea56a))
* **acceptance-resolver:** Reject control chars and unwritable output ([3a9f266](https://github.com/Azure/osdu-spi/commit/3a9f266a4caa659766344e6b034b69b3aacff176))
* **acceptance-resolver:** Reject oversized values and bad placeholders ([9f1f38a](https://github.com/Azure/osdu-spi/commit/9f1f38a2ecf6b85cb1ec7ad6a0ec640b9e8aee7a))
* **acceptance-resolver:** Reject symlinked env-file writes and bad ([409cc16](https://github.com/Azure/osdu-spi/commit/409cc1645b5ad86f6e894cdb199e27ba6b7542f3))
* **acceptance-resolver:** Reject tabs anywhere and add RESOLVER_ prefix ([9736b58](https://github.com/Azure/osdu-spi/commit/9736b580206689729f0282b3393442a6d96ee7e2))
* **acceptance-resolver:** Reject unescaped quotes and long descriptions ([acbbc76](https://github.com/Azure/osdu-spi/commit/acbbc76bf74e68dcab857875d933d8918231effc))
* **acceptance-resolver:** Reject wrong-typed facts and ambient env names ([ea65cc4](https://github.com/Azure/osdu-spi/commit/ea65cc45851a9596621487a1011bc6245401af7a))
* **acceptance-resolver:** Secure env file writes and discard on refusal ([e54ac56](https://github.com/Azure/osdu-spi/commit/e54ac568917207c39a304afa7a6fb2be424640d6))
* **acceptance-resolver:** Treat malformed facts nodes as contract ([a1bf116](https://github.com/Azure/osdu-spi/commit/a1bf116ff4ccf5ef502107a3b918986f34401032))
* **acceptance-resolver:** Validate keyvault fact before use ([38b829a](https://github.com/Azure/osdu-spi/commit/38b829ae5d04b44a255145585f632ec11a7e3f41))
* **acceptance-resolver:** Validate primary flag and UTF-8 encodability ([467eb5e](https://github.com/Azure/osdu-spi/commit/467eb5e1d124b7b63a32bf22a4b27ab9bb438fc3))
* **adopt-fork:** Enable Issues on the fork during adoption ([7ecb7f3](https://github.com/Azure/osdu-spi/commit/7ecb7f359b76b3ee7f3f630caa34174f3692434e))
* **adopt-fork:** Fail fast on unprotected branches after adoption ([665ece2](https://github.com/Azure/osdu-spi/commit/665ece2c2a8bae83846a325e5acf9a4840114e3a))
* **adopt-fork:** Pin sync branches at merge base with upstream ([5c94cba](https://github.com/Azure/osdu-spi/commit/5c94cba15d68e5af4e2fd1d8ca691a0a226b4da9))
* **cascade:** Enforce merge-commit method on release PRs via auto-merge ([d77997d](https://github.com/Azure/osdu-spi/commit/d77997d2540af262f2d3d0ca487c5c1a71c25a7a))
* **ci:** Add guard for missing tracking issue in sync workflow ([9b0961e](https://github.com/Azure/osdu-spi/commit/9b0961e896ee2af4e15776a22ae0bd0567bb6656))
* **ci:** Add guard to skip issue update when tracking issue is closed ([7975d25](https://github.com/Azure/osdu-spi/commit/7975d256dc2b788df28e0648752603c9463d8182))
* **ci:** Add missing GH_TOKEN to cascade merge step ([978f3b6](https://github.com/Azure/osdu-spi/commit/978f3b67ea0be67376ebd0503f3b58f6ad9824a3))
* **ci:** Analyze template workflows and drop pull_request_target ref ([d3cd529](https://github.com/Azure/osdu-spi/commit/d3cd529266e6d0846d9eb940f4ceba105e4539dd))
* **ci:** Clean up untracked files before checking out existing sync branch ([b2ab139](https://github.com/Azure/osdu-spi/commit/b2ab1397c85c0fcb2568c0c47a8d8a7271e028bf))
* **ci:** Clean up untracked files before sync branch checkout ([45185c5](https://github.com/Azure/osdu-spi/commit/45185c5ea1cbf6fe4953d6e8622772636c2a178a))
* **ci:** Correct actions/setup-node SHA pin ([ffb1b73](https://github.com/Azure/osdu-spi/commit/ffb1b7306b2497a3fd1bd8ceade8584a93ba5889))
* **ci:** Correct broken fallback detection in sync-template PR body ([dfb9bbc](https://github.com/Azure/osdu-spi/commit/dfb9bbc7ac4746c7214c96d84e3854fe0d437928))
* **ci:** Deduplicate sync and dependabot builds ([62514e5](https://github.com/Azure/osdu-spi/commit/62514e5ab7599c65215fdc408b73002deba976a6))
* **ci:** Drop the PR-head checkout from docker-build and scan template-workflows before sync ([e23608e](https://github.com/Azure/osdu-spi/commit/e23608ee317e0a42ef2cbf9184de8b313a2606bc))
* **ci:** Enable docker build validation for mirror-mode fork_upstream ([c84a23e](https://github.com/Azure/osdu-spi/commit/c84a23e75d95434c5282dde8ecb1fee79072c375))
* **ci:** Fetch fork PR head via refs/pull instead of head_ref ([7ecbc6a](https://github.com/Azure/osdu-spi/commit/7ecbc6a45b4cc0e137a91eddf36b06f1ed64b55f))
* **ci:** Guard sync deduplication by repository ([cef89bb](https://github.com/Azure/osdu-spi/commit/cef89bb5214639abf6639b57b56d9fbe500a7bd0))
* **ci:** Handle tracking issue closure in sync workflow status updates ([713a29c](https://github.com/Azure/osdu-spi/commit/713a29cb7e96831ecf07f71b278955df8741685b))
* **ci:** Make validate.yml work for external-fork PRs ([5f20ae4](https://github.com/Azure/osdu-spi/commit/5f20ae4759619a8ce79b01df968c070b130290f1))
* **ci:** Prevent cascade self-heal when upstream already merged ([26b6932](https://github.com/Azure/osdu-spi/commit/26b6932b193e38925a47273192086c6e97c4ec3c))
* **ci:** Remove duplicate pr builds via single-lane routing ([ce1cc2e](https://github.com/Azure/osdu-spi/commit/ce1cc2ee5597f6dc11743deebce10d3f34510757))
* **ci:** Remove failure-state labels on successful cascade completion ([0f6af7c](https://github.com/Azure/osdu-spi/commit/0f6af7cbf489dc7381c94aba4bcf4fcb02a358ee))
* **ci:** Resolve date command execution in PR title ([53e1828](https://github.com/Azure/osdu-spi/commit/53e1828ec7d6571fcc67a570cb1807fbd52bc059))
* **ci:** Resolve race condition in upstream sync issue creation ([1c8a85c](https://github.com/Azure/osdu-spi/commit/1c8a85c580384d94207c684450c77f3bbdec689a))
* **ci:** Skip pr-status comment for fork pull_request runs ([b664c52](https://github.com/Azure/osdu-spi/commit/b664c5210b01b73fc29bf9442ac930724dc414c7))
* **codeql:** Analyze GitHub Actions in forks and stop skipping .github changes ([2a4c3e7](https://github.com/Azure/osdu-spi/commit/2a4c3e73074578bbfc5b2d3b536ed840ecdaafaf))
* **codeql:** Analyze GitHub Actions in forks and stop skipping .github changes ([d981a4e](https://github.com/Azure/osdu-spi/commit/d981a4ec49f716306559c2b63437855da758bb35))
* **customer-tier:** Re-enable fork-disabled workflows and stop cache errors failing Docker builds ([1c3f391](https://github.com/Azure/osdu-spi/commit/1c3f39104426b2d2fe51c7320c7c0a6d1c2b0c81))
* Distinguish cleanup lookup failures ([25511dc](https://github.com/Azure/osdu-spi/commit/25511dc0d473b349928df630fa385d598a23c5a6))
* Drop invented mcp.json and remove dead .vscode plumbing ([125d749](https://github.com/Azure/osdu-spi/commit/125d749f7eafa80559ac7b8a8f43aed169ea1190))
* Harden upstream sync state management ([5ab4574](https://github.com/Azure/osdu-spi/commit/5ab457435b1ec9734fae7dc2b40d0e493ebd08fe))
* Harden upstream sync state management ([bfaff41](https://github.com/Azure/osdu-spi/commit/bfaff41307b785ee4d5adecfc8d6d03673e1503a))
* **init:** Pin gh commands to fork repository ([14294a4](https://github.com/Azure/osdu-spi/commit/14294a48f5288af3b8e67dd05e241f96253e1f85))
* Keep unchanged sync cycles silent ([8dead82](https://github.com/Azure/osdu-spi/commit/8dead8234599f3a1f7db05d510211b063c589361))
* Pin docs workflow python to 3.12 ([30811ce](https://github.com/Azure/osdu-spi/commit/30811ceaac067999105b4d19bc379c229829d2b6))
* Preserve canonical sync issue state ([95b9d5f](https://github.com/Azure/osdu-spi/commit/95b9d5f6502ee303b210c27cfd2295831c4d8229))
* Preserve local action on sync validation ([b097e15](https://github.com/Azure/osdu-spi/commit/b097e1519879d6bcc047f01d71fbae064e9b5d46))
* Prevent cascade deadlock from stale fork_integration divergence ([592165c](https://github.com/Azure/osdu-spi/commit/592165c649ca05b008b226f6a53af27760589cf2))
* **release:** Reorder retag steps and make root .mvn copy optional ([f60bc09](https://github.com/Azure/osdu-spi/commit/f60bc09fd497ad6e87f572dd18c2e34ea8eab118))
* Resolve date rendering in sync template PR title ([91cc929](https://github.com/Azure/osdu-spi/commit/91cc929e9c9f0ba5074771b523f2d7e376b36254))
* Restore trailing newline on dependabot.yml ([c688256](https://github.com/Azure/osdu-spi/commit/c6882562217b8d9ecd38f454affee9fa3f09f55c))
* **sync-state-manager:** Fingerprint the generator in the durable cache key ([0fe0516](https://github.com/Azure/osdu-spi/commit/0fe0516cd816bd4806a1f6d343d7932936023421))
* **sync-state-manager:** Ignore sigpipe on stdout debug output ([edfd207](https://github.com/Azure/osdu-spi/commit/edfd20743e907e807c02a1598f072febed70722b))
* **sync-state-manager:** Persist no-op SHA in repository variable ([5e44b35](https://github.com/Azure/osdu-spi/commit/5e44b35ddb3eaf44fe6dc39fdca02e67e05f32c0))
* **sync-state-manager:** Persist upstream SHA for filtered no-op syncs ([342add0](https://github.com/Azure/osdu-spi/commit/342add0c77a460d425bf1140e8bc52660b765ece))
* **sync-state-manager:** Scope durable no-op cache to generation revision ([ee039e1](https://github.com/Azure/osdu-spi/commit/ee039e1abbec5f6c7c95101707d7dffd256a9e65))
* **sync-state-manager:** Send fatal state errors to stderr ([266ec84](https://github.com/Azure/osdu-spi/commit/266ec8475d562ee15fa0f783a43017d36f257584))
* **sync:** Avoid sigpipe from piping git log into grep -q ([0fb6b19](https://github.com/Azure/osdu-spi/commit/0fb6b192b51afeec853e664fdab1622ed5fee1cc))
* **sync:** Compute upstream commit range against upstream sha ([3a3cdb2](https://github.com/Azure/osdu-spi/commit/3a3cdb21e570768837f91bedb30910e7113b7e14))
* **sync:** Target fork for GitHub CLI operations ([399b3a2](https://github.com/Azure/osdu-spi/commit/399b3a29a874901c61e8f0b5c68d1d3470f415bb))
* Target fork for gh sync operations ([3e842e4](https://github.com/Azure/osdu-spi/commit/3e842e4bd14d72f8b3c954eb8604287cf0d6983f))
* Update pymdown extensions to 11.0.1 ([995abcd](https://github.com/Azure/osdu-spi/commit/995abcd77b7f1fb21828bba54576ed7586a4234c))
* Update pymdown-extensions to 11.0.1 ([edb0c2e](https://github.com/Azure/osdu-spi/commit/edb0c2e5c494d3beff865561a138081f741ded99))
* **upstream-filter:** Derive service slug from config, ignore inline ([cc6628b](https://github.com/Azure/osdu-spi/commit/cc6628bf72c63de9dbbc9fdc24c6ea329a7d7f13))
* **upstream-filter:** Honor xml comments and force-add ignored files ([22c0f12](https://github.com/Azure/osdu-spi/commit/22c0f12ec967c22720ef0c095c5be646f866f873))
* **upstream-filter:** Materialize tree via read-tree/checkout-index ([611dabd](https://github.com/Azure/osdu-spi/commit/611dabd3ef28e72d6ed928ef4836f2f02f85e229))
* **upstream-filter:** Parse empty indented config blocks correctly ([cc5c52e](https://github.com/Azure/osdu-spi/commit/cc5c52e49dea38770d0025cfdffa00f4391eb366))
* **upstream-filter:** Validate inject profile requires inject verdict ([d8e372b](https://github.com/Azure/osdu-spi/commit/d8e372bd41dea80cf6a2514a72d378b60f000701))
* **workflows:** Derive service slug from upstream url not checkout dir ([fafebb1](https://github.com/Azure/osdu-spi/commit/fafebb1f640bd7795037d41d3f69b20c88f026bc))


### 📚 Documentation

* Add repository links and update support documentation ([d689ce6](https://github.com/Azure/osdu-spi/commit/d689ce65849ee2fd7f8156a0d49db1892018e399))
* Address review on PR 172 ([e585e2c](https://github.com/Azure/osdu-spi/commit/e585e2c3a621493c3471e05493f007b99d38ea98))
* **adoption:** Document adoption's automatic workflow re-enable step ([e5a4089](https://github.com/Azure/osdu-spi/commit/e5a4089c8984348121ccf401ef84ff05c83f61a5))
* **adoption:** Document schedule-triggered workflow enable steps ([e585dcc](https://github.com/Azure/osdu-spi/commit/e585dcca0deb1e74ee5f18462f5ce3fb48490c6f))
* **adoption:** Document schedule-triggered workflow enable steps ([b2a62ab](https://github.com/Azure/osdu-spi/commit/b2a62abc5357dbf201c6b4e4610f3b475ea7f40f))
* **adr:** Add adr-038 for upstream filter transform ([cdd72f8](https://github.com/Azure/osdu-spi/commit/cdd72f8e43a9ce0f4f4baddc8e4fe5d16c166f5e))
* **adr:** Add ADR-039 for customer-tier mirror sync ([3dd9c11](https://github.com/Azure/osdu-spi/commit/3dd9c1127932a848e1ac2e639b16324527808f3b))
* **adr:** Fix drift and cut scaffold sections across the ADR catalog ([210d2f9](https://github.com/Azure/osdu-spi/commit/210d2f97ccab7ce5e6bf745aa24386b4ea0c0d58))
* **adr:** Revise upstream filter design to use scratch git plumbing ([5a1d5c8](https://github.com/Azure/osdu-spi/commit/5a1d5c87b3e62938dab8706aee40192c50beeba4))
* Align duplicate state storage guidance ([3482ec6](https://github.com/Azure/osdu-spi/commit/3482ec600664fe53c826317fd8d2ad7aec0eed9d))
* Align workflow and architecture guides ([a9736ee](https://github.com/Azure/osdu-spi/commit/a9736eeed6f67838415a2e34e4a805316799e5c8))
* Align workflow and architecture guides with the 1.0 pipeline ([5f48326](https://github.com/Azure/osdu-spi/commit/5f48326c6074bcd56f9d246cde8ce5fff7c35203))
* Clarify expect-flag guidance and reword adr-043 reference ([248e047](https://github.com/Azure/osdu-spi/commit/248e0478b16ddc9745a0d9afebe00ccad9afeae5))
* **codeql:** Describe the skip gate as Markdown-only, not documentation-only ([ace66a1](https://github.com/Azure/osdu-spi/commit/ace66a181911a0b9e78dce9028cbbe8bfdfce20b))
* Document deduplicated validation paths ([0d25aeb](https://github.com/Azure/osdu-spi/commit/0d25aeb153a175e4fc09111ce17534ba653e04be))
* **github:** Condense workflow and script comments repo-wide ([077800c](https://github.com/Azure/osdu-spi/commit/077800c9dd2e4a71a0f38cac309c73476f3d71f8))
* **github:** Condense workflow and script comments repo-wide ([0c36e75](https://github.com/Azure/osdu-spi/commit/0c36e75d3992a4141cea7b2c35bb68c2aca3625b))
* **product:** Add upstream filter implementation plan for ADR-038 ([c50ab97](https://github.com/Azure/osdu-spi/commit/c50ab978a6404e5613f4c2af87a26fe219790fe8))
* **product:** Correct upstream filter file count breakdown ([9f8746c](https://github.com/Azure/osdu-spi/commit/9f8746ca2c5116bc686b95ffe91e619d24a1dd8f))
* Remove ai-enhanced sync claims, document deterministic behavior ([d5998f1](https://github.com/Azure/osdu-spi/commit/d5998f1d335b670d78224afa71736e0f8724c0df))
* Remove drift and AI-sounding prose from site pages and ADRs ([66ea3e4](https://github.com/Azure/osdu-spi/commit/66ea3e45230849db924e7be4be148b3d20bcbaa6))
* Remove drift, marketing prose, and em dashes from site pages ([597e628](https://github.com/Azure/osdu-spi/commit/597e6287e62161c41a9b1a857904e51232913e35))
* Remove product documentation directory and outdated references ([421ddea](https://github.com/Azure/osdu-spi/commit/421ddea2024cfd7b8677b68899609644a9ae8915))
* Remove unmaintained doc/product directory ahead of 1.0 ([ca4bb65](https://github.com/Azure/osdu-spi/commit/ca4bb65893efbc4c788c3add95591675bd3a2935))
* Update SUPPORT.md and add service links to README ([5469e49](https://github.com/Azure/osdu-spi/commit/5469e4922710e314c8ffe2593589d2bdc4054e25))
* **workflows:** Condense build/validate lane routing comments ([3cf0924](https://github.com/Azure/osdu-spi/commit/3cf09246ee606f2c4e35f83e515393abe4e1aa7c))


### 🔧 Miscellaneous

* **ci:** Remove unused Maven credentials ([16ca71b](https://github.com/Azure/osdu-spi/commit/16ca71b571d894c013a5daeb5ba8df78890767fd))
* **ci:** Remove unused Maven credentials ([3119a67](https://github.com/Azure/osdu-spi/commit/3119a6773ab678e8af37c2e46e135bf6a55c92ba))
* **dependabot:** Align fork config with filtered tree ([1704e42](https://github.com/Azure/osdu-spi/commit/1704e421f285a44aacdb1ef80d58789782916bbf))
* Remove mvn-mcp-server integration ([03b313b](https://github.com/Azure/osdu-spi/commit/03b313b77a6076121728d7ebb566a43608930da0))
* Remove mvn-mcp-server integration ([175e198](https://github.com/Azure/osdu-spi/commit/175e19891e60ada5311fdcfd6ea50d3b01c1c277))


### ♻️ Code Refactoring

* **acceptance-resolver:** Rename secret_name to kv_name for clarity ([b5658af](https://github.com/Azure/osdu-spi/commit/b5658afcdef33428f6c5d5cf38ef9aeb88ad9e01))
* **acceptance-resolver:** Simplify key vault secret check ([01329fc](https://github.com/Azure/osdu-spi/commit/01329fcb612876bf7aba8e6bbf22e2f74ea88180))
* **ci:** Improve auto-heal comment formatting in cascade workflow ([1d8cca7](https://github.com/Azure/osdu-spi/commit/1d8cca742aab71a5c7ee3a4f9a9a18a97ece48d7))
* **workflows:** Remove aipr ai path in favor of deterministic sync ([d347144](https://github.com/Azure/osdu-spi/commit/d34714469f9ecf274626588d55b05aa2b0d544ba))
* **workflows:** Remove the aipr AI path in favor of deterministic descriptions ([6f77527](https://github.com/Azure/osdu-spi/commit/6f775271537f8ff8125ee6c79bb02c4be08f263e))


### 🧪 Tests

* **resolver:** Verify empty fact values treated as missing ([4293c58](https://github.com/Azure/osdu-spi/commit/4293c58702e9423552e40715ec19948d08d3da3a))


### 🔨 Build System

* **ci:** Update actions/setup-node to latest v6 commit hash ([3296e17](https://github.com/Azure/osdu-spi/commit/3296e175e23c28f506f5e75fe589030648281462))
* **deps:** Bump idna from 3.11 to 3.15 in /doc ([9fca1d2](https://github.com/Azure/osdu-spi/commit/9fca1d2bb8cda3ad8b32d4e6868d3646661f2712))
* **deps:** Bump idna from 3.11 to 3.15 in /doc ([e2a4beb](https://github.com/Azure/osdu-spi/commit/e2a4bebb020afdd521090807144bed7ee5ecfafb))
* **deps:** Bump pygments from 2.19.2 to 2.20.0 in /doc ([09eb9dc](https://github.com/Azure/osdu-spi/commit/09eb9dcfeb235dd6ed6cc07ea909d0a593c20f6b))
* **deps:** Bump pygments from 2.19.2 to 2.20.0 in /doc ([79c79ba](https://github.com/Azure/osdu-spi/commit/79c79ba792d3b6919cc91a94d043fc65add9565a))
* **deps:** Bump pymdown-extensions from 10.16.1 to 10.21.3 in /doc ([52722d8](https://github.com/Azure/osdu-spi/commit/52722d86e9278cd32415410067becd0efecb112c))
* **deps:** Bump pymdown-extensions from 10.16.1 to 10.21.3 in /doc ([ad4897b](https://github.com/Azure/osdu-spi/commit/ad4897bc4dfebc5d887ff73487c15d2f82f04e62))
* **deps:** Bump requests from 2.32.5 to 2.33.0 in /doc ([89058a1](https://github.com/Azure/osdu-spi/commit/89058a11b34f66bc95cde790dce9b732c7ef34a9))
* **deps:** Bump requests from 2.32.5 to 2.33.0 in /doc ([aeb299b](https://github.com/Azure/osdu-spi/commit/aeb299befab9ff0e0bf2798f33133f6912ea1935))
* **deps:** Bump urllib3 from 2.6.3 to 2.7.0 in /doc ([f36faaa](https://github.com/Azure/osdu-spi/commit/f36faaa8807b1be779456363aa826790e1da8ce1))
* **deps:** Bump urllib3 from 2.6.3 to 2.7.0 in /doc ([020de71](https://github.com/Azure/osdu-spi/commit/020de713451a498a280c96eb95b316dc9bb710b3))


### ⚙️ Continuous Integration

* **actions:** Pass expression values through env in composite action scripts ([99a4a27](https://github.com/Azure/osdu-spi/commit/99a4a27ee92bf35c4697ce4033b0a4e910e56611))
* **actions:** Pass expression values through env vars to avoid injection ([44a3680](https://github.com/Azure/osdu-spi/commit/44a3680d6a9c7f454e0aefaaa599cf45192b646d))
* **adopt-fork:** Validate app key and harden shell steps ([ba7fca6](https://github.com/Azure/osdu-spi/commit/ba7fca66c139b4a88772085be3e696b5aafed0f0))
* **codeql:** Add advanced codeql analysis workflow ([002d6f8](https://github.com/Azure/osdu-spi/commit/002d6f83692271837facc474d5b8f39e4d3ba835))
* **codeql:** Guard sarif jq parsing against missing fields ([60c5c71](https://github.com/Azure/osdu-spi/commit/60c5c7121e81bd900e114c58373c44f8057a86ef))
* **codeql:** Pin actions to exact versions and fix tag-object ref ([0edfe34](https://github.com/Azure/osdu-spi/commit/0edfe343721ebdf81dfb2a942b01b76cdebec081))
* **codeql:** Replace default setup with an advanced CodeQL workflow ([652ee9a](https://github.com/Azure/osdu-spi/commit/652ee9a71f31294584ac4212c4aae4eb452fa429))
* Correct setup-node version comment in dev-ci ([c05a1c2](https://github.com/Azure/osdu-spi/commit/c05a1c2e6e5b096e5a7d1f7040e3b1ecf2401eea))
* **docker:** Enable multi-arch builds only on push ([c8114a2](https://github.com/Azure/osdu-spi/commit/c8114a2f49774231c412828573ab7fc2b7bdc2fb))
* **java-build:** Assert pr head sha before checkout validation ([bd9d207](https://github.com/Azure/osdu-spi/commit/bd9d20736db35ef15e73c52afbf9fc7dba834fea))
* Normalize template-workflow pins and close copilot-setup-steps sync gap ([9a2a202](https://github.com/Azure/osdu-spi/commit/9a2a202b3c40cc00ba7a3077560972b8181625a1))
* Normalize template-workflow pins and close copilot-setup-steps sync gap ([ae46895](https://github.com/Azure/osdu-spi/commit/ae468955a2f846a0c9f8b3c9668fb8b9b92f8d53))
* Pin GitHub Actions version comments and add Dependabot cooldown ([5f7432e](https://github.com/Azure/osdu-spi/commit/5f7432e7ba396bc414bba8f60651751bb13e0a38))
* **template-sync:** Give sync PR titles a conventional prefix ([dc60d5e](https://github.com/Azure/osdu-spi/commit/dc60d5eeb09006bc7341384ba53460359a8536fb))
* **template-sync:** Use conventional prefix for sync pr titles ([5051b2d](https://github.com/Azure/osdu-spi/commit/5051b2dd8cdb83df832ef77a84bf393bb1573d17))
* **validate,build:** One validation lane per pull request ([8f11cc1](https://github.com/Azure/osdu-spi/commit/8f11cc1a42c987dc8e5725475d8ba2dcab65c3f3))
* **validate:** Improve error message and clarify comment gating logic ([4dd5372](https://github.com/Azure/osdu-spi/commit/4dd5372473a42c47aa7ee4555117f20d13a4e494))
* **validate:** Remove local action restoration steps for sync PRs ([3334ac3](https://github.com/Azure/osdu-spi/commit/3334ac3f9c0a0f78d99015d390ac9d57b9fc2ee7))
* **workflow:** Add GITHUB_TOKEN environment variable to merge step ([158f2aa](https://github.com/Azure/osdu-spi/commit/158f2aa14e23656843da5e4ed543ec055d173e3e))
* **workflow:** Plant upstream filter config on resumed runs ([1911f04](https://github.com/Azure/osdu-spi/commit/1911f04ad63af5a139d280506ebb2f44f1a82602))
* **workflows:** Re-enable fork-disabled workflows on adoption ([c603e8c](https://github.com/Azure/osdu-spi/commit/c603e8cae4e7a298c4c7bf2cbb63a91cbea849ba))

## [1.1.0](https://github.com/Azure/osdu-spi/compare/v1.0.2...v1.1.0) (2026-03-03)


### ✨ Features

* **ci:** Add GitHub App private key rotation script ([0ec7fa3](https://github.com/Azure/osdu-spi/commit/0ec7fa347a16b8f9565dd6299229da386db4e8d1))
* **ci:** Add GitHub App private key rotation script ([a01fb57](https://github.com/Azure/osdu-spi/commit/a01fb574fea6bea0e3772faa43c6cf81bd6c32e1))


### 🐛 Bug Fixes

* **ci:** Add proper quoting to git branch validation commands ([abfb36b](https://github.com/Azure/osdu-spi/commit/abfb36bf2f855369d1e2fa525bb36e303fbcbbfa))
* **ci:** Add repository fork check to pull_request_target validation ([92b13ea](https://github.com/Azure/osdu-spi/commit/92b13eaa5b1eb85a93a4944807098998906e384f))
* **ci:** Harden GitHub Actions workflows against supply chain attacks ([e455e26](https://github.com/Azure/osdu-spi/commit/e455e26624a67a0a37c4b26034418d93fbec39c9))
* **ci:** Update Trivy installation URL to use version-specific path ([97c7dd3](https://github.com/Azure/osdu-spi/commit/97c7dd3877ca146573a858a8edd6871842184176))
* **ci:** Upgrade Trivy to v0.69.3 after upstream security incident ([62a7ebd](https://github.com/Azure/osdu-spi/commit/62a7ebd34a3faf454d46f3700eaf778393aa65f6))


### 🔧 Miscellaneous

* **ci:** Pin GitHub Actions to commit SHAs and improve security ([8bff7b3](https://github.com/Azure/osdu-spi/commit/8bff7b3667d488852a5ef20ad87a3f3c61eff420))


### ♻️ Code Refactoring

* **ci:** Improve argument validation and error handling in key rotation script ([20ef855](https://github.com/Azure/osdu-spi/commit/20ef855751c3d9f043b407a29ee5d0b6d8960d3c))
* **ci:** Improve shell variable handling in PR creation action ([67f5893](https://github.com/Azure/osdu-spi/commit/67f5893810e8c7c93085d30b6a825412c8af9351))
* **ci:** Use environment variable for upstream repo URL ([9e1b5d4](https://github.com/Azure/osdu-spi/commit/9e1b5d4c285b93f961ad4415a26769222624e1e4))


### 🔨 Build System

* **ci:** Pin GitHub Actions to commit SHAs for security ([49dce2d](https://github.com/Azure/osdu-spi/commit/49dce2d7f001cafeabbf70b957e2042a0d9dcbdf))
* **ci:** Upgrade Trivy security scanner to v0.69.3 ([5e10f43](https://github.com/Azure/osdu-spi/commit/5e10f43bb48cd770f54df5490acf232be8b60620))

## [1.0.2](https://github.com/Azure/osdu-spi/compare/v1.0.1...v1.0.2) (2026-02-13)


### 🐛 Bug Fixes

* **ci:** Remove bare expression syntax from cascade workflow comments ([a8d2ad8](https://github.com/Azure/osdu-spi/commit/a8d2ad8b5c1b386bd58c9e18fc73943e4654497d))


### 📚 Documentation

* **ci:** Clarify expression substitution terminology in comments ([6447775](https://github.com/Azure/osdu-spi/commit/6447775b0510f0a7e65f3eeab540cc86f35d4525))

## [1.0.1](https://github.com/Azure/osdu-spi/compare/v1.0.0...v1.0.1) (2026-02-13)


### 🐛 Bug Fixes

* **ci:** Prevent shell injection in GitHub workflow issue/PR creation ([ca93968](https://github.com/Azure/osdu-spi/commit/ca9396840e03cab7b70c179e51f58a50ccccbc60))
* **ci:** Prevent shell parsing errors in workflow templates ([8a2f24d](https://github.com/Azure/osdu-spi/commit/8a2f24d4f6ae118cddd0968c463a24a23f092e99))
* **ci:** Replace echo with printf for safer PR body handling ([cf28988](https://github.com/Azure/osdu-spi/commit/cf28988c4fcf4eb21fd2c4f3a809b6c051493cf9))


### 🔨 Build System

* **deps:** Bump urllib3 from 2.6.0 to 2.6.3 in /doc ([149d2de](https://github.com/Azure/osdu-spi/commit/149d2de2ffb0b7eff0faf27db2a8fd324e089715))
* **deps:** Bump urllib3 from 2.6.0 to 2.6.3 in /doc ([9c8d575](https://github.com/Azure/osdu-spi/commit/9c8d575e8cebebbd7bd79f5ae9e087e08d721739))

## 1.0.0 (2025-12-19)


### ✨ Features

* **actions:** Remove label support in pr creation ([22529de](https://github.com/Azure/osdu-spi/commit/22529de1fdce938da3caab1956efa44c7adeeaf5))
* **actions:** Update or add template remote when syncing config ([22529de](https://github.com/Azure/osdu-spi/commit/22529de1fdce938da3caab1956efa44c7adeeaf5))
* Add CodeQL security scanning configuration ([15d5ae1](https://github.com/Azure/osdu-spi/commit/15d5ae1273a9604eaf5e1880e416de7277c5ea5c))
* Add configurable Azure OpenAI model and fix aipr commit authentication ([3085a57](https://github.com/Azure/osdu-spi/commit/3085a570a0e808bc6cd2f485a602c8d486392056))
* **aipr:** Add configurable Azure OpenAI model for PR descriptions ([1753bc6](https://github.com/Azure/osdu-spi/commit/1753bc621d98d8643000aeee0521eecda61d356a))
* **ci:** Add CodeQL summary job for required status checks ([5ebbee7](https://github.com/Azure/osdu-spi/commit/5ebbee7d08712111c883f8c1eedf4a5fed1e2f4d))
* **ci:** Add CodeQL summary job for required status checks ([6daea05](https://github.com/Azure/osdu-spi/commit/6daea05c67bc00d4a8f7a8e759ef561d09f910b5))
* **ci:** Detect label config changes and create human review issues ([b713e65](https://github.com/Azure/osdu-spi/commit/b713e65dd8b3edeadf3d77eb7c2572eb9c10251d))
* **ci:** Implement release-please automation and enhance workflow security ([80640d9](https://github.com/Azure/osdu-spi/commit/80640d96c349bb671ce63c2deb862cb1e4c166b9))
* Implement dual Dependabot configuration architecture ([1748df8](https://github.com/Azure/osdu-spi/commit/1748df8c3c9b8a80a80c71f5a3b2facbb4d27b90))
* **init:** Replace branch protection with repository rulesets ([469e1d4](https://github.com/Azure/osdu-spi/commit/469e1d461b7897218783338b1eefaee128386265))
* **security:** Work to improve OpenSSF Scorecard results ([87e181a](https://github.com/Azure/osdu-spi/commit/87e181a43593d36734c873af9f995d85d6041a0e))
* **template-sync:** Implement duplicate PR prevention for template updates ([dc2e421](https://github.com/Azure/osdu-spi/commit/dc2e4213f36657edc6a7d2cdcbb13e3983e3442b))
* **template:** Enhance template-sync PR handling and actions ([e7ef7ff](https://github.com/Azure/osdu-spi/commit/e7ef7ff4d63c9a1e0e241a2475b77172b21141be))
* **workflows:** Fix template-sync duplicate PRs and fork_integration sync issues ([ce68932](https://github.com/Azure/osdu-spi/commit/ce68932d6fa531e349f1e48b2c8f417413934754))


### 🐛 Bug Fixes

* Add code owners ([18626d6](https://github.com/Azure/osdu-spi/commit/18626d6694378962ef92e0863b96e12e253727b8))
* Add code owners ([cfcbf65](https://github.com/Azure/osdu-spi/commit/cfcbf6595925a2b2f1ec34114dfe3d647cbdbba6))
* Add code owners ([f38fb7f](https://github.com/Azure/osdu-spi/commit/f38fb7fe7483ff0ad58786e870b459328757f746))
* Add CODEOWNERS to cleanup rules during initialization ([55ce2e5](https://github.com/Azure/osdu-spi/commit/55ce2e5fd77852475adf950b078eb8c75cfada9f))
* Add required tools array to MCP server configuration ([5bb507b](https://github.com/Azure/osdu-spi/commit/5bb507b23c45014d5ec2c36422bee9b747562063))
* Add required type property to MCP server configuration ([21e5c52](https://github.com/Azure/osdu-spi/commit/21e5c52955fc8136f7e5c321e95a00f136297d5e))
* Address Copilot PR review comments ([c751f31](https://github.com/Azure/osdu-spi/commit/c751f31185841bea9bdb60c0fd7e9c6873330b2c))
* **aipr:** Use azure/gpt-5-chat model instead of default azure model ([cce0bf1](https://github.com/Azure/osdu-spi/commit/cce0bf1b0b3aa8fd3eeb10107d943951f46cabc9))
* Checkout version ([873b49b](https://github.com/Azure/osdu-spi/commit/873b49b0e1595789671796e0ce93cbeac919bdab))
* **ci:** Add GITHUB_TOKEN to validate workflow and exclude release-please PRs ([508ae5c](https://github.com/Azure/osdu-spi/commit/508ae5c7b31e04fc843d64b788d80a15c25d71de))
* **ci:** Add retry logic and connection timeout for Maven dependency resolution ([3a618e5](https://github.com/Azure/osdu-spi/commit/3a618e50c9944811b2886ef3fc5683dfc90ed570))
* **ci:** Add retry logic and connection timeout for Maven dependency resolution ([f3ed9e7](https://github.com/Azure/osdu-spi/commit/f3ed9e7c7aa4354a8eeea10f5ef6c3e2d6a2f688))
* **ci:** Address review feedback - fix syntax errors and improve error handling ([cd1c8d9](https://github.com/Azure/osdu-spi/commit/cd1c8d978ee37c0b3a602b892ad5f341e9c931f6))
* **ci:** Auto-create template-sync label for brownfield repos ([0f1c239](https://github.com/Azure/osdu-spi/commit/0f1c2396266977112026c3fe050c449881ea1a22))
* **ci:** Correct retry counter increment in Maven dependency resolution ([6a64504](https://github.com/Azure/osdu-spi/commit/6a64504904c0ad4e2db27097f871ec03759c247c))
* **ci:** Detect and fail when CodeQL finds no analyzable languages ([77f15ea](https://github.com/Azure/osdu-spi/commit/77f15ea1a3869c0bb038d4b8fe9ca7faf8f2fcae))
* **ci:** Escape special characters in service name substitution and pin CodeQL action versions ([f30b022](https://github.com/Azure/osdu-spi/commit/f30b0225ddfaad5e447c04dbc30bdd86d2256002))
* **ci:** Improve ruleset creation error handling and API compatibility ([873a778](https://github.com/Azure/osdu-spi/commit/873a77854962c0fdf353c1abd5b5cd712ac5e7c4))
* **ci:** Improve shell variable quoting and regex pattern in codeql workflow ([0b4d145](https://github.com/Azure/osdu-spi/commit/0b4d145280ee7ee177013acbe23cf4cc3414bde1))
* **ci:** Improve workflow deployment error handling and logging ([aa21e37](https://github.com/Azure/osdu-spi/commit/aa21e372057de99b0bc2751dac91421f460fdc15))
* **ci:** Initialize RULESET_FAILED flag in create_ruleset function ([d033a85](https://github.com/Azure/osdu-spi/commit/d033a853180d0afd2ddb56c3b3a530d342b216f4))
* **ci:** Preserve setup scripts before cleanup in init workflow ([5c831df](https://github.com/Azure/osdu-spi/commit/5c831dfce61dfb3bf6684209e766c4cce5faffc9))
* **ci:** Preserve template files before cleanup in initialization workflow ([3817121](https://github.com/Azure/osdu-spi/commit/3817121ee4dba62fe83c36dc2324ac161f29aa12))
* **ci:** Remove incorrect RULESET_FAILED assignment in error handling ([c67ef47](https://github.com/Azure/osdu-spi/commit/c67ef470f4406beca0a93039f4818b442218585e))
* **ci:** Remove pip/doc dependabot config to prevent fork caching issues ([5223583](https://github.com/Azure/osdu-spi/commit/52235833047e2144229d9ba95bda4f7b357789f7))
* **ci:** Remove pip/doc ecosystem from dependabot to prevent fork caching issues ([57a8866](https://github.com/Azure/osdu-spi/commit/57a886642bb4dad3b9aa1104f7d90fad6c6d2285))
* **ci:** Remove update restriction from default branch ruleset ([2be9b58](https://github.com/Azure/osdu-spi/commit/2be9b58d3760a1d014103a7644ee21116e71c8f5))
* **ci:** Resolve dependabot sync conflicts and improve copilot setup resilience ([d81e48e](https://github.com/Azure/osdu-spi/commit/d81e48e049d8889f8bd3103a63644d45d32b75d9))
* **ci:** Resolve dependabot validation errors and add service name detection ([6e209d3](https://github.com/Azure/osdu-spi/commit/6e209d34be39593b2e3e97ae937c726ae5cffa8e))
* **ci:** Resolve workflow deployment timing and authentication issues ([7a4619a](https://github.com/Azure/osdu-spi/commit/7a4619acab1cd3b6b1fa5a335477f1af7f4e4333))
* **ci:** Resolve workflow push authentication with GH_TOKEN ([e4d9bae](https://github.com/Azure/osdu-spi/commit/e4d9bae3519920350122a03d2078b9d9d2d94980))
* **ci:** Restore template-sync duplicate PR prevention ([8c56c75](https://github.com/Azure/osdu-spi/commit/8c56c75317a5470dc91fe757bcbc268867edfc37))
* **ci:** Use GitHub App token in sync workflow ([73f6c45](https://github.com/Azure/osdu-spi/commit/73f6c455eac50e1119125b838f999ac7fb656634))
* **codeql:** Use build-mode none for all languages ([160964a](https://github.com/Azure/osdu-spi/commit/160964a57c164ac3af3dc5ef8fa9f819ed161903))
* **codeql:** Use compact JSON output to fix language detection failures ([a59b3e6](https://github.com/Azure/osdu-spi/commit/a59b3e6e2f08c3c0d014511ca7dc200fb46bc5bf))
* **codeql:** Use compact JSON output to fix language detection failures ([04b1c82](https://github.com/Azure/osdu-spi/commit/04b1c82744de053aec83180a9944175479262c42))
* **codeql:** Use manual build for multi-module Maven projects ([b61bba0](https://github.com/Azure/osdu-spi/commit/b61bba07d8a154c7330cf595dab45e337d30d251))
* Correct aipr command syntax and add installation to sync-template workflow ([2224ccf](https://github.com/Azure/osdu-spi/commit/2224ccf456d67e7a8e14a5e5a8753119af8f0e6e))
* Correct GitHub App token action SHA ([83277f0](https://github.com/Azure/osdu-spi/commit/83277f041419d65ea42a83aae92e1745213d9c73))
* Enable release automation via GitHub App ([de52be3](https://github.com/Azure/osdu-spi/commit/de52be31362c58091399f57ac1251314ae4347a6))
* Ensuring the proper model is used ([bf9efa7](https://github.com/Azure/osdu-spi/commit/bf9efa7be2ff4b37823da2f65cfec8d93d0f9da4))
* Ensuring the proper model is used ([60aab63](https://github.com/Azure/osdu-spi/commit/60aab63deac5bb8bfe3c077c946e960f32a8b0c4))
* Pin pip dependencies by hash for supply chain security ([178b86d](https://github.com/Azure/osdu-spi/commit/178b86d4d189b8c3478b612c1b1eadee040590bb))
* Redesign sync-config-applier to work with private template repos ([fe347f8](https://github.com/Azure/osdu-spi/commit/fe347f8331b894758e841d0c3ccc89b67c2537d7))
* Remove invalid GitHub Advanced Security status check from ruleset ([ebb0790](https://github.com/Azure/osdu-spi/commit/ebb079086de6588d1f79c981c41730d4bdde0555))
* Remove Python from template CodeQL scan ([59fc79e](https://github.com/Azure/osdu-spi/commit/59fc79ec84264d3dd22af1e1db3a4df3179bc029))
* Replace PAT authentication with GitHub App tokens in template workflows ([c7e1e2d](https://github.com/Azure/osdu-spi/commit/c7e1e2d8b32a29e7beb2474d9f47d060443e39ea))
* Restore local actions before sync-config-applier ([536c841](https://github.com/Azure/osdu-spi/commit/536c841b39a143e3adc38e3307bed8f808679675))
* Restore local actions before sync-config-applier ([ed88979](https://github.com/Azure/osdu-spi/commit/ed889795cfa106448bebfb1e4b6cb310c43c11b8))
* **review:** Address PR review comments ([34b1ff7](https://github.com/Azure/osdu-spi/commit/34b1ff7ae13495a54784bab6f1af7cc4f1e2ddb2))
* **scorecard:** Use approved codeql-action v3.30.6 for workflow verification ([3a74022](https://github.com/Azure/osdu-spi/commit/3a7402204d5a7a8ff3c0fa6598fa1a37bb13bb67))
* **sync:** Add dependabot and release-please config to template sync ([6cd7f68](https://github.com/Azure/osdu-spi/commit/6cd7f68e3322bb9771c0b5a203689a5edb37e71b))
* **sync:** Improve error detection to prevent aipr error messages in PR descriptions ([cad0c50](https://github.com/Azure/osdu-spi/commit/cad0c50ecb588fd122ef96993a857e7dfaf2b14c))
* Use correct version tag for create-github-app-token action ([b4d4b57](https://github.com/Azure/osdu-spi/commit/b4d4b57a93dc0048314cf6cb48b6b9e1f2c0159a))
* **validate:** Replace deprecated ebiny action with amannn/action-semantic-pull-request ([eb93d0a](https://github.com/Azure/osdu-spi/commit/eb93d0a963597896bfb9ba968948f78a44a0ffc6))
* **validate:** Skip java-build for sync PRs targeting fork_upstream ([7d82191](https://github.com/Azure/osdu-spi/commit/7d8219140f04ec9d5a4e92cc4c7789e5cdaf8ca8))


### ⚡ Performance Improvements

* **codeql:** Add path filters to skip non-code changes ([f7ca158](https://github.com/Azure/osdu-spi/commit/f7ca1584f5dd714018003d6fcd473a42fe7dec2e))
* **codeql:** Add path filters to skip non-code changes ([e0d2fb8](https://github.com/Azure/osdu-spi/commit/e0d2fb835441a55033388901b99f779e5daa5463))


### 📚 Documentation

* Add clarifying comments for Copilot review suggestions ([573376c](https://github.com/Azure/osdu-spi/commit/573376c401d55e5b918e1dbf0e32894ff898ae60))
* **adr:** Add CodeQL summary job pattern for required status checks ([9b986d1](https://github.com/Azure/osdu-spi/commit/9b986d189ceeb656d40acb4769533a6a5183630f))
* **adr:** Add GitHub App authentication strategy decision ([aa04584](https://github.com/Azure/osdu-spi/commit/aa0458409af1b9fc36190b0cba9852ebfa2970ee))
* **ci:** Clarify template repository usage and local actions restoration ([1036be1](https://github.com/Azure/osdu-spi/commit/1036be1a100a4c861061c82a5236d54da47f8f6e))
* **ci:** Document dependabot schedule strategy and sync design ([49d4e09](https://github.com/Azure/osdu-spi/commit/49d4e09b057a1f8792492b414def0662852fec08))
* **ci:** Remove redundant workflow deployment comment ([d51cf8f](https://github.com/Azure/osdu-spi/commit/d51cf8fcd08dcbd20dfce09ec5e05640bfef113f))
* **ci:** Simplify workflow comments for clarity ([712401f](https://github.com/Azure/osdu-spi/commit/712401f2b966534bd1ea6b460ae7fbbd0cfe0a9e))
* **ci:** Update template_repo_url description for clarity ([06f23f4](https://github.com/Azure/osdu-spi/commit/06f23f4905e74f294978cdc4583d139b557d72f0))
* **dependabot:** Switch schedule to daily for faster rebasing ([5ac82ed](https://github.com/Azure/osdu-spi/commit/5ac82ed3443ab2e988a21f988f603be010821f13))
* Fix grammar and hyphenation in documentation ([e11bf62](https://github.com/Azure/osdu-spi/commit/e11bf62ecc471690e4549566e83da7d97690ffe7))
* Remove OPENAI_API_KEY references from initialization workflow ([3ed53ff](https://github.com/Azure/osdu-spi/commit/3ed53ff72c3866d529027bbb711251a5870f0dc3))
* Reorganize and align documentation structure ([136692e](https://github.com/Azure/osdu-spi/commit/136692e07352b5654861e824f697d03ad7f4baa6))
* Simplify MCP server configuration and improve ADR formatting ([fafa34c](https://github.com/Azure/osdu-spi/commit/fafa34c0965dba28fa09f562206732983caa14f2))
* Simplify MCP server configuration and improve ADR formatting ([21c70de](https://github.com/Azure/osdu-spi/commit/21c70dedf23ccecb224287138383f175bc7f33e1))
* **structure:** Reorganize documentation into product and source directories ([566db3e](https://github.com/Azure/osdu-spi/commit/566db3e6211c7513f1e2a754417d59c43b532b1e))
* **terminology:** Update Azure OpenAI references to Azure Foundry ([704563a](https://github.com/Azure/osdu-spi/commit/704563a28a5262970efc4f4dfcd8965645674f2e))
* Update AI documentation to reflect Azure-only approach ([091c844](https://github.com/Azure/osdu-spi/commit/091c8440da812e70b2df63390a2fc11a5a7c7cca))
* **workflows:** Add inline comments explaining token usage and permissions ([b30364a](https://github.com/Azure/osdu-spi/commit/b30364a39e1261cf724a2a949518eb6cf01086c4))


### 💎 Styles

* **ci:** Remove emoji characters from workflow output messages ([9f40fde](https://github.com/Azure/osdu-spi/commit/9f40fde5135d215ee090dac8712dac81b3310620))


### 🔧 Miscellaneous

* **ci:** Enhance dependabot coverage and upgrade to daily syncs ([e3aec82](https://github.com/Azure/osdu-spi/commit/e3aec8278d9fccef17cdff1fa9fe0ebda0218fef))
* **ci:** Remove CodeQL code scanning requirement from branch ruleset ([d3945c9](https://github.com/Azure/osdu-spi/commit/d3945c94b3a9162cb3287d2f5d938684d96967c0))
* **ci:** Remove dependabot ignore patterns for testing directories ([62027e1](https://github.com/Azure/osdu-spi/commit/62027e1266062b5b05797277e20a3149c02bc008))
* **ci:** Remove update rule from default branch ruleset ([0189667](https://github.com/Azure/osdu-spi/commit/01896679398dd8032165883c67f9c95a6a56708c))
* **ci:** Simplify dependabot config and add service name detection ([f8ae112](https://github.com/Azure/osdu-spi/commit/f8ae112f531282337dc345394b9c88b55ee61d84))
* **ci:** Update release-please-action to latest version ([8d880dd](https://github.com/Azure/osdu-spi/commit/8d880dd50b33080cb120139c438699eb14efc9e3))
* **ci:** Update release-please-action to latest version ([4f026e3](https://github.com/Azure/osdu-spi/commit/4f026e376cf97ff829d5e87746803ae27c111bdf))
* **config:** Exclude CODEOWNERS from fork sync ([5dc2a0d](https://github.com/Azure/osdu-spi/commit/5dc2a0dcefe3691b1c846ba8e8a8f11332cd3a53))
* **config:** Move CODEOWNERS to exclusions list ([92c5c7b](https://github.com/Azure/osdu-spi/commit/92c5c7b6c8447eadb00fbc3e3b176de2ba4635d4))
* **dependabot:** Add exclude-paths to skip non-Azure providers ([41f4588](https://github.com/Azure/osdu-spi/commit/41f4588670f13c83b4eebb65bc20d9affa7e8926))
* **dependabot:** Exclude provider-* and test paths from updates ([0952b12](https://github.com/Azure/osdu-spi/commit/0952b126fa3f53e05bc53210fc29ecd1a3c3180e))
* **deps:** Separate dependabot concerns between template and forks ([4c24e61](https://github.com/Azure/osdu-spi/commit/4c24e61d0e20e87e80de63593a061f10f0208b8a))
* Merge main with init workflow refactoring ([713aad0](https://github.com/Azure/osdu-spi/commit/713aad037c7fa28ed6f3289755f36d8f3235682a))
* **release-please:** Switch release-type to simple in config ([47d2cd1](https://github.com/Azure/osdu-spi/commit/47d2cd18f6a93b2024cedd9cedb455054c253542))
* Remove custom CodeQL workflow in favor of GitHub Advanced Security ([6bb61fd](https://github.com/Azure/osdu-spi/commit/6bb61fdd6c1055873a9f2344ed038636e6c62b37))
* **sync:** Exclude CODEOWNERS from template synchronization ([fe4cf3d](https://github.com/Azure/osdu-spi/commit/fe4cf3d0cbbcb4d7b5363952515dbf223b938bd4))


### ♻️ Code Refactoring

* **ai:** Remove meta-commit strategy and update to gpt-5-chat ([15015ef](https://github.com/Azure/osdu-spi/commit/15015ef24d982d8b13128df4a9d4f5322c02172d))
* **ai:** Standardize on Azure OpenAI ([919fb80](https://github.com/Azure/osdu-spi/commit/919fb80123620ab7d7d85ccc43adcf439efc7f4f))
* **ai:** Standardize on Azure OpenAI, document sync.yml extraction constraint ([c5e1236](https://github.com/Azure/osdu-spi/commit/c5e12365d2c91fb2450280e9b5ff3f0a1cde0ae4))
* **ci:** Defer workflow deployment to post-merge step ([6fb3322](https://github.com/Azure/osdu-spi/commit/6fb332293c5ae3fc807bcdf54209594141326def))
* **ci:** Extract ruleset creation into reusable function ([4ce14e2](https://github.com/Azure/osdu-spi/commit/4ce14e2372b24cd0b4585081aa7ec123a5fb9026))
* **ci:** Reorder workflow steps for logical security setup sequence ([4881115](https://github.com/Azure/osdu-spi/commit/4881115c67c08e4e3eafc4fc023611a33fb42dbd))
* **ci:** Separate dependabot concerns between template and forks ([73e91df](https://github.com/Azure/osdu-spi/commit/73e91df85a72172a80a1cc25a81bdb4656c132b5))
* **codeql:** Use build-mode none for Java to avoid duplicate builds ([fdff5a9](https://github.com/Azure/osdu-spi/commit/fdff5a9f4f9b91699f2439bc9628b0ac785ca8dd))
* Extract workflow scripts into testable composite actions ([ff38662](https://github.com/Azure/osdu-spi/commit/ff3866252a6ef39a0707da698ded2acb8abcccc6))
* Extract workflow scripts into testable composite actions ([be15da2](https://github.com/Azure/osdu-spi/commit/be15da2d4a3a24ef1b3d5635fed9caabd7762033))
* Init workflows ([8fd7eb6](https://github.com/Azure/osdu-spi/commit/8fd7eb6dce33237f0e8b33a852bb7c759544a226))


### 🔨 Build System

* **ci:** Bump github/codeql-action from 3.30.6 to 4.30.9 ([158e750](https://github.com/Azure/osdu-spi/commit/158e750aceab69b92e01124b0c3f915e90df7be2))
* **ci:** Downgrade codeql-action from v4 to v3.30.6 ([94a8b6b](https://github.com/Azure/osdu-spi/commit/94a8b6b4811c14d07c430ac41c0a77573ceea542))
* **ci:** Update codeql-action to v4.30.9 ([d1ae9dc](https://github.com/Azure/osdu-spi/commit/d1ae9dcd82878737f586995e390acdd403f7470b))
* **ci:** Update create-github-app-token action to v2.1.4 ([6a8c3e4](https://github.com/Azure/osdu-spi/commit/6a8c3e4dcf47f8cbc81aa14a4aa259fee4ea49d8))
* **ci:** Upgrade actions/setup-node from v5 to v6 ([e9c9330](https://github.com/Azure/osdu-spi/commit/e9c9330b6d7a623ddfa59b9abd2b11d5e4de2a50))
* **ci:** Upgrade actions/setup-node from v5 to v6 ([1125ac1](https://github.com/Azure/osdu-spi/commit/1125ac1d6e19328daee821fa97e1aa7041a30c24))
* **ci:** Upgrade actions/upload-artifact to v5.0.0 with SHA pinning ([64ff002](https://github.com/Azure/osdu-spi/commit/64ff002b508f1fa8bc7efb5a55ae953755543bcd))
* **ci:** Upgrade CodeQL action from v3 to v4 ([56cb846](https://github.com/Azure/osdu-spi/commit/56cb846e52f02001e4db786ba9e5594a41232a52))
* **deps:** Bump actions/checkout from 4 to 5 ([f3666c0](https://github.com/Azure/osdu-spi/commit/f3666c025322a9655416b1e5645f4a229ad6d7ce))
* **deps:** Bump actions/checkout from 4 to 5 ([0b2c1f7](https://github.com/Azure/osdu-spi/commit/0b2c1f7484150eb1df12c5cfc5a4aa2b71d97d08))
* **deps:** Bump actions/setup-node from 4 to 5 ([a3fb99d](https://github.com/Azure/osdu-spi/commit/a3fb99d8f8a24438270da39121f599f19b2e8d88))
* **deps:** Bump actions/setup-node from 4 to 5 ([40dce5d](https://github.com/Azure/osdu-spi/commit/40dce5d909bd25dcf4f94f8554440ef13b14e47b))
* **deps:** Bump actions/setup-node from 4.1.0 to 5.0.0 ([cb37cca](https://github.com/Azure/osdu-spi/commit/cb37ccaf41bdbe486f311763cb3abf1a6a4fbb8c))
* **deps:** Bump actions/setup-node from 4.1.0 to 5.0.0 ([aff30b9](https://github.com/Azure/osdu-spi/commit/aff30b9c220a0f5f319f7acf97b5ea99d504ce69))
* **deps:** Bump actions/setup-node from 5.0.0 to 6.0.0 ([28102f8](https://github.com/Azure/osdu-spi/commit/28102f8cad2c56fb8858c19478f98b9ac34c2107))
* **deps:** Bump actions/setup-node from 5.0.0 to 6.0.0 ([b267aba](https://github.com/Azure/osdu-spi/commit/b267aba6be01e7a4570207454848926ece9d09c9))
* **deps:** Bump actions/setup-python from 5 to 6 ([1191967](https://github.com/Azure/osdu-spi/commit/1191967eaa1466498cdf9ceb64fb69e6dc34ffc2))
* **deps:** Bump actions/setup-python from 5 to 6 ([5977c95](https://github.com/Azure/osdu-spi/commit/5977c95e50804174019934540a75b6114fb663ab))
* **deps:** Bump github/codeql-action from 4.30.9 to 4.31.0 in the github-actions group ([56e8e28](https://github.com/Azure/osdu-spi/commit/56e8e28fc652d8d8b742bc704142abbfd7ee0b29))
* **deps:** Bump github/codeql-action in the github-actions group ([79d8d7d](https://github.com/Azure/osdu-spi/commit/79d8d7dea093527fdb0f8a80287687401cc57428))
* **deps:** Bump the mkdocs group in /doc with 2 updates ([3d9b857](https://github.com/Azure/osdu-spi/commit/3d9b8578f2625e892553705363df976ad7ada1bc))
* **deps:** Bump the mkdocs group in /doc with 2 updates ([f80505b](https://github.com/Azure/osdu-spi/commit/f80505b98e4cb1c4497e8533945e9b7b31177c2c))
* **deps:** Bump urllib3 from 2.5.0 to 2.6.0 in /doc ([7cb8bfd](https://github.com/Azure/osdu-spi/commit/7cb8bfdb6bae4d2c8b8def23c7e04c33ec439d76))
* **deps:** Bump urllib3 from 2.5.0 to 2.6.0 in /doc ([fcf7d53](https://github.com/Azure/osdu-spi/commit/fcf7d53382a49875907b346bf57cb276315c2d0e))
* **docs:** Add pinned dependencies with hash verification ([3d688d7](https://github.com/Azure/osdu-spi/commit/3d688d7ecff9456362e2fc280893febcf2d0acd7))


### ⚙️ Continuous Integration

* **create-enhanced-pr:** Pass PR_LABELS to gh pr create ([c239fb5](https://github.com/Azure/osdu-spi/commit/c239fb56557e1761b2e835424e345fa2bb2d8494))
* **dependabot:** Configure patch-only updates and group rules ([da9b295](https://github.com/Azure/osdu-spi/commit/da9b29559abdccf36ef3be82f3085124a48e155b))
* **dependabot:** Patch-only updates with grouped dependencies ([7e384b5](https://github.com/Azure/osdu-spi/commit/7e384b5833c2207a2e975567e30d153d925a9942))
* **dependabot:** Switch maven schedule from weekly to daily ([8ba69b3](https://github.com/Azure/osdu-spi/commit/8ba69b370f853e0a590e9dc0e896c64f6f244b6f))
* **dependabot:** Switch schedule to daily ([b6998a3](https://github.com/Azure/osdu-spi/commit/b6998a37626c2e1bef9251e93de9e831534540dd))
* Fix CodeQL auto-trigger for template-sync and release PRs ([509311b](https://github.com/Azure/osdu-spi/commit/509311b52b03c66ec5bceb304662486a7c0e55d2))
* **github:** Enforce code owner and last push approval requirements ([845f987](https://github.com/Azure/osdu-spi/commit/845f987bb8fc19832b18a40b652c20929bdce229))
* Improve OSSF token permissions security ([d14dcc9](https://github.com/Azure/osdu-spi/commit/d14dcc9b312a55ba81f7b90394a9269833471823))
* **release:** Add GitHub App token generation for release workflow ([ed3623f](https://github.com/Azure/osdu-spi/commit/ed3623fc73e33ef3d72f4b5548878dcbc675e029))
* **release:** Use GitHub App token for release-please authentication ([5e950e5](https://github.com/Azure/osdu-spi/commit/5e950e5069398d2394468b3121c7e6064225b57b))
* **rulesets:** Remove GitHub Advanced Security status check requirement ([93da459](https://github.com/Azure/osdu-spi/commit/93da45991df0f30081ef4bb97cf45fa1b836dbee))
* **scorecard:** Pin upload-artifact action to commit hash for security ([fb3872a](https://github.com/Azure/osdu-spi/commit/fb3872a2d2f95b2454a5eb9c7c34bef0b288868a))
* **security:** Add OpenSSF Scorecard workflow ([50b779a](https://github.com/Azure/osdu-spi/commit/50b779afe05746eaf223db7eaeb38558eb762900))
* **security:** Add OpenSSF Scorecard workflow for security analysis ([924b775](https://github.com/Azure/osdu-spi/commit/924b775582881ecf0e4dfebd932bed1feea210ea))
* Update sync template to process dependabot and release config ([7ee692b](https://github.com/Azure/osdu-spi/commit/7ee692bf9b5a400b5e8a05caa2acd978e26956d6))
* Use GitHub App token for release-please to trigger workflows ([7bff199](https://github.com/Azure/osdu-spi/commit/7bff199bdeee7ec819e0b947be6e45a4b47cca29))
* **validate:** Adjust java-build to skip dependabot and fork_upstream sync prs ([fb62224](https://github.com/Azure/osdu-spi/commit/fb622242605b3b069d3f7059ab29ded7f4ee2221))
* **validate:** Enable sync PR validation by restoring local actions ([fe4a1c1](https://github.com/Azure/osdu-spi/commit/fe4a1c190edf45e233456bd913d5fc76ea659495))
* **validate:** Enable sync PR validation by restoring local actions ([e48e9a3](https://github.com/Azure/osdu-spi/commit/e48e9a313b0d4a296c8faac5a24c7605cb52f994))
* **validate:** Remove skip of fork_upstream sync PRs from java-build ([e48e9a3](https://github.com/Azure/osdu-spi/commit/e48e9a313b0d4a296c8faac5a24c7605cb52f994))
* **workflow:** Refine PR gating in validate workflow ([986c589](https://github.com/Azure/osdu-spi/commit/986c589e78c9b2afdbd7a49fe01391e4df7a63fd))
* **workflow:** Reorder branch protection and security setup steps ([4cbd080](https://github.com/Azure/osdu-spi/commit/4cbd08021339d58fe885424ea25e62eabc34feac))
* **workflows:** Add dynamic path filtering to CodeQL workflow ([0f52809](https://github.com/Azure/osdu-spi/commit/0f52809f67e1a6b2b81dd33e7f250dab9676ebc2))
* **workflows:** Align azure openai env vars across templates ([b65404f](https://github.com/Azure/osdu-spi/commit/b65404f7db9b2cb8927edf9a63aaa4c9016ae1a9))
* **workflows:** Improve error handling in copilot setup workflow ([5f3ca82](https://github.com/Azure/osdu-spi/commit/5f3ca8289e060fad86e22264e4e86d65f2723a6e))
* **workflows:** Move permissions to job level for security best practices ([39d7c9f](https://github.com/Azure/osdu-spi/commit/39d7c9f4245ec8affec74f0ce996ac5b96a7dd1d))
* **workflows:** Pin GitHub App token action to commit SHA ([5c9e015](https://github.com/Azure/osdu-spi/commit/5c9e0151d024921afba635eaca445d09a24d7522))
* **workflows:** Replace GH_TOKEN with GitHub App authentication ([b244458](https://github.com/Azure/osdu-spi/commit/b244458de1dd866303290892f66402c2b86b3646))
* **workflows:** Replace PAT authentication with GitHub App tokens ([5d05234](https://github.com/Azure/osdu-spi/commit/5d05234370b47ef5259a7708cd94641be76e9618))
* **workflows:** Update template-sync workflows and docs ([f40c2f8](https://github.com/Azure/osdu-spi/commit/f40c2f80d2e27e51b506185d46234e2adba20da0))
* **workflow:** Switch to github app token for sync workflow ([29dba85](https://github.com/Azure/osdu-spi/commit/29dba855e697bd88451c40b2fa3cfde536da073d))
