# Changelog

## 1.0.0 (2025-10-30)


### ✨ Features

* Add CodeQL security scanning configuration ([15d5ae1](https://github.com/Azure/osdu-spi/commit/15d5ae1273a9604eaf5e1880e416de7277c5ea5c))
* Add configurable Azure OpenAI model and fix aipr commit authentication ([3085a57](https://github.com/Azure/osdu-spi/commit/3085a570a0e808bc6cd2f485a602c8d486392056))
* **aipr:** Add configurable Azure OpenAI model for PR descriptions ([1753bc6](https://github.com/Azure/osdu-spi/commit/1753bc621d98d8643000aeee0521eecda61d356a))
* **ci:** Add CodeQL summary job for required status checks ([5ebbee7](https://github.com/Azure/osdu-spi/commit/5ebbee7d08712111c883f8c1eedf4a5fed1e2f4d))
* **ci:** Add CodeQL summary job for required status checks ([6daea05](https://github.com/Azure/osdu-spi/commit/6daea05c67bc00d4a8f7a8e759ef561d09f910b5))
* **ci:** Implement release-please automation and enhance workflow security ([80640d9](https://github.com/Azure/osdu-spi/commit/80640d96c349bb671ce63c2deb862cb1e4c166b9))
* Implement dual Dependabot configuration architecture ([1748df8](https://github.com/Azure/osdu-spi/commit/1748df8c3c9b8a80a80c71f5a3b2facbb4d27b90))
* **init:** Replace branch protection with repository rulesets ([469e1d4](https://github.com/Azure/osdu-spi/commit/469e1d461b7897218783338b1eefaee128386265))
* **security:** Work to improve OpenSSF Scorecard results ([87e181a](https://github.com/Azure/osdu-spi/commit/87e181a43593d36734c873af9f995d85d6041a0e))


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
* **ci:** Add retry logic and connection timeout for Maven dependency resolution ([3a618e5](https://github.com/Azure/osdu-spi/commit/3a618e50c9944811b2886ef3fc5683dfc90ed570))
* **ci:** Add retry logic and connection timeout for Maven dependency resolution ([f3ed9e7](https://github.com/Azure/osdu-spi/commit/f3ed9e7c7aa4354a8eeea10f5ef6c3e2d6a2f688))
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
* **scorecard:** Use approved codeql-action v3.30.6 for workflow verification ([3a74022](https://github.com/Azure/osdu-spi/commit/3a7402204d5a7a8ff3c0fa6598fa1a37bb13bb67))
* **sync:** Improve error detection to prevent aipr error messages in PR descriptions ([cad0c50](https://github.com/Azure/osdu-spi/commit/cad0c50ecb588fd122ef96993a857e7dfaf2b14c))
* Use correct version tag for create-github-app-token action ([b4d4b57](https://github.com/Azure/osdu-spi/commit/b4d4b57a93dc0048314cf6cb48b6b9e1f2c0159a))
* **validate:** Replace deprecated ebiny action with amannn/action-semantic-pull-request ([eb93d0a](https://github.com/Azure/osdu-spi/commit/eb93d0a963597896bfb9ba968948f78a44a0ffc6))


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
* **deps:** Separate dependabot concerns between template and forks ([4c24e61](https://github.com/Azure/osdu-spi/commit/4c24e61d0e20e87e80de63593a061f10f0208b8a))
* Merge main with init workflow refactoring ([713aad0](https://github.com/Azure/osdu-spi/commit/713aad037c7fa28ed6f3289755f36d8f3235682a))
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
* **docs:** Add pinned dependencies with hash verification ([3d688d7](https://github.com/Azure/osdu-spi/commit/3d688d7ecff9456362e2fc280893febcf2d0acd7))


### ⚙️ Continuous Integration

* Fix CodeQL auto-trigger for template-sync and release PRs ([509311b](https://github.com/Azure/osdu-spi/commit/509311b52b03c66ec5bceb304662486a7c0e55d2))
* **github:** Enforce code owner and last push approval requirements ([845f987](https://github.com/Azure/osdu-spi/commit/845f987bb8fc19832b18a40b652c20929bdce229))
* Improve OSSF token permissions security ([d14dcc9](https://github.com/Azure/osdu-spi/commit/d14dcc9b312a55ba81f7b90394a9269833471823))
* **release:** Add GitHub App token generation for release workflow ([ed3623f](https://github.com/Azure/osdu-spi/commit/ed3623fc73e33ef3d72f4b5548878dcbc675e029))
* **release:** Use GitHub App token for release-please authentication ([5e950e5](https://github.com/Azure/osdu-spi/commit/5e950e5069398d2394468b3121c7e6064225b57b))
* **rulesets:** Remove GitHub Advanced Security status check requirement ([93da459](https://github.com/Azure/osdu-spi/commit/93da45991df0f30081ef4bb97cf45fa1b836dbee))
* **scorecard:** Pin upload-artifact action to commit hash for security ([fb3872a](https://github.com/Azure/osdu-spi/commit/fb3872a2d2f95b2454a5eb9c7c34bef0b288868a))
* **security:** Add OpenSSF Scorecard workflow ([50b779a](https://github.com/Azure/osdu-spi/commit/50b779afe05746eaf223db7eaeb38558eb762900))
* **security:** Add OpenSSF Scorecard workflow for security analysis ([924b775](https://github.com/Azure/osdu-spi/commit/924b775582881ecf0e4dfebd932bed1feea210ea))
* Use GitHub App token for release-please to trigger workflows ([7bff199](https://github.com/Azure/osdu-spi/commit/7bff199bdeee7ec819e0b947be6e45a4b47cca29))
* **workflow:** Reorder branch protection and security setup steps ([4cbd080](https://github.com/Azure/osdu-spi/commit/4cbd08021339d58fe885424ea25e62eabc34feac))
* **workflows:** Add dynamic path filtering to CodeQL workflow ([0f52809](https://github.com/Azure/osdu-spi/commit/0f52809f67e1a6b2b81dd33e7f250dab9676ebc2))
* **workflows:** Align azure openai env vars across templates ([b65404f](https://github.com/Azure/osdu-spi/commit/b65404f7db9b2cb8927edf9a63aaa4c9016ae1a9))
* **workflows:** Improve error handling in copilot setup workflow ([5f3ca82](https://github.com/Azure/osdu-spi/commit/5f3ca8289e060fad86e22264e4e86d65f2723a6e))
* **workflows:** Move permissions to job level for security best practices ([39d7c9f](https://github.com/Azure/osdu-spi/commit/39d7c9f4245ec8affec74f0ce996ac5b96a7dd1d))
* **workflows:** Pin GitHub App token action to commit SHA ([5c9e015](https://github.com/Azure/osdu-spi/commit/5c9e0151d024921afba635eaca445d09a24d7522))
* **workflows:** Replace GH_TOKEN with GitHub App authentication ([b244458](https://github.com/Azure/osdu-spi/commit/b244458de1dd866303290892f66402c2b86b3646))
* **workflows:** Replace PAT authentication with GitHub App tokens ([5d05234](https://github.com/Azure/osdu-spi/commit/5d05234370b47ef5259a7708cd94641be76e9618))
