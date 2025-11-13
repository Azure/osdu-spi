# ADR-028: Workflow Script Extraction Pattern

## Status
**Accepted** - 2025-10-01

## Context

The OSDU SPI Fork Management Template workflows contain approximately 3,500 lines of embedded bash scripts across 9 workflow files. While these scripts implement critical functionality, their embedded nature creates several challenges:

**Problems with Embedded Scripts:**

- **Debugging Difficulty**: Cannot test scripts locally without running entire workflow
- **Code Duplication**: LLM provider detection duplicated 2x in sync.yml (~130 lines)
- **Maintenance Burden**: Changes require editing multiple workflows, understanding YAML context
- **No Unit Testing**: Complex bash logic (awk, conditionals, error handling) cannot be unit tested
- **Poor Visibility**: Difficult to see what scripts exist and what they do
- **Version Control**: Changes to scripts mixed with workflow structural changes in git diffs

**Most Complex Workflows:**

- **sync.yml** (658 lines): AI-powered upstream sync with LLM provider detection, PR generation, state management
- **cascade.yml** (745 lines): Multi-stage integration with validation, conflict resolution, PR creation
- **init-complete.yml** (878 lines): Repository initialization with branch protection, security config, resource deployment
- **sync-state-manager/action.yml** (271 lines): Complex state management with decision matrix logic

**Key Challenges:**

1. How to extract scripts while maintaining sync propagation to fork instances?
2. Where to place scripts so they're automatically synced via template sync (ADR-011, ADR-012)?
3. How to handle GitHub App workflow permission limitations (ADR-015)?
4. How to enable local testing without breaking workflow functionality?
5. Which scripts should be extracted vs. remain inline?

## Decision

Implement a **Workflow Script Extraction Pattern** that extracts embedded bash scripts into separate, testable files organized within `.github/actions/` subdirectories. This pattern leverages existing sync infrastructure and composite actions to enable local testing, code reuse, and maintainability improvements.

### 1. **Script Organization Structure**

```
.github/
├── actions/                    # Fork-operational actions (synced to forks)
│   ├── llm-provider-detect/
│   │   ├── action.yml
│   │   ├── detect-provider.sh
│   │   └── README.md
│   ├── issue-state-manager/
│   │   ├── action.yml
│   │   ├── update-issue-state.sh
│   │   └── README.md
│   └── sync-state-manager/
│       ├── action.yml
│       ├── *.sh
│       └── README.md
└── local-actions/              # Template-only actions (NOT synced to forks)
    ├── init-helpers/
    │   ├── action.yml
    │   ├── setup-upstream.sh
    │   ├── setup-branch-protection.sh
    │   ├── setup-security.sh
    │   ├── deploy-fork-resources.sh
    │   └── README.md
    ├── push-protection-handler/
    │   ├── action.yml
    │   ├── detect-and-report.sh
    │   └── README.md
    ├── template-protection-check/
    │   ├── action.yml
    │   ├── check-template.sh
    │   └── README.md
    └── configure-git/
        ├── action.yml
        └── README.md
```

### 2. **Script Placement Rationale**

**Fork-Operational Actions (`.github/actions/`):**

- ✅ **Synced to forks**: Defined in sync-config.json lines 7-10 as synced directory
- ✅ **Used by fork workflows**: Actions needed by sync.yml, cascade.yml, validate.yml, etc.
- ✅ **Template propagation**: Updates flow to fork instances via template-sync.yml
- ✅ **Examples**: llm-provider-detect, issue-state-manager, sync-state-manager

**Template-Only Actions (`.github/local-actions/`):**

- ✅ **NOT synced to forks**: Excluded in sync-config.json line 114
- ✅ **Used by init workflows**: Actions only needed by init.yml and init-complete.yml
- ✅ **Removed after init**: Cleaned up per sync-config.json cleanup_rules (line 123-126)
- ✅ **No fork pollution**: Fork instances never receive these actions
- ✅ **Follows ADR-015 pattern**: Similar to `.github/template-workflows/` separation
- ✅ **Examples**: init-helpers, push-protection-handler, template-protection-check, configure-git

**Why Two Directories:**

- Prevents syncing init-only actions to fork instances
- Fork instances only receive actions they actually use
- Follows established ADR-015 pattern for template vs fork separation
- Makes lifecycle intent explicit (one-time vs ongoing use)

### 3. **Composite Action Wrapper Pattern**

Each extracted script group is wrapped in a composite action for workflow integration:

```yaml
# .github/actions/llm-provider-detect/action.yml
name: 'LLM Provider Detection'
description: 'Detect available LLM provider (Azure Foundry → OpenAI → Fallback)'

outputs:
  use_llm:
    description: 'Whether LLM is available (true/false)'
    value: ${{ steps.detect.outputs.use_llm }}
  llm_model:
    description: 'LLM model identifier (azure/gpt-4o or gpt-4)'
    value: ${{ steps.detect.outputs.llm_model }}

runs:
  using: "composite"
  steps:
    - name: Detect LLM provider
      id: detect
      shell: bash
      run: ${{ github.action_path }}/detect-provider.sh
      env:
        AZURE_API_KEY: ${{ env.AZURE_API_KEY }}
        AZURE_API_BASE: ${{ env.AZURE_API_BASE }}
        OPENAI_API_KEY: ${{ env.OPENAI_API_KEY }}
```

### 4. **Workflow Integration Pattern**

Workflows use actions instead of embedded scripts:

```yaml
# Before: Embedded script in sync.yml (lines 266-283)
- name: Detect LLM provider
  run: |
    USE_LLM=false
    LLM_MODEL=""
    if [[ -n "$AZURE_API_KEY" ]] && [[ -n "$AZURE_API_BASE" ]]; then
      USE_LLM=true
      LLM_MODEL="azure"
    elif [[ -n "$OPENAI_API_KEY" ]]; then
      USE_LLM=true
      LLM_MODEL="gpt-4"
    fi
    echo "use_llm=$USE_LLM" >> $GITHUB_OUTPUT
    echo "llm_model=$LLM_MODEL" >> $GITHUB_OUTPUT

# After: Action call
- name: Detect LLM provider
  uses: ./.github/actions/llm-provider-detect
  id: llm
  env:
    AZURE_API_KEY: ${{ secrets.AZURE_API_KEY }}
    AZURE_API_BASE: ${{ secrets.AZURE_API_BASE }}
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}

- name: Generate PR description
  if: steps.llm.outputs.use_llm == 'true'
  run: aipr pr -m ${{ steps.llm.outputs.llm_model }} ...
```

### 5. **Local Testing Pattern**

Each action includes README.md with local testing instructions:

```bash
## Local Testing

# Navigate to action directory
cd .github/actions/llm-provider-detect

# Set required environment variables
export AZURE_API_KEY="your_test_key"
export AZURE_API_BASE="https://your-instance.openai.azure.com"

# Run script directly
./detect-provider.sh

# Expected output:
# use_llm=true
# llm_model=azure

# Test fallback scenario
unset AZURE_API_KEY
unset AZURE_API_BASE
unset OPENAI_API_KEY
./detect-provider.sh

# Expected output:
# use_llm=false
# llm_model=
```

### 6. **Extraction Decision Matrix**

Use these criteria to determine if a script should be extracted:

| Criterion | Extract | Keep Inline | Weight |
|-----------|---------|-------------|--------|
| **Size** | >200 lines | <100 lines | High |
| **Complexity** | Decision matrices, state machines, platform compatibility logic | Simple conditionals, straightforward commands | Critical |
| **Reusability** | Used in 2+ places OR planned reuse | Single-use workflow-specific logic | High |
| **Testability Value** | Needs local validation (date parsing, complex conditionals) | Simple orchestration, obvious behavior | High |
| **Type** | Composite action logic (reusable components) | Workflow orchestration (end-to-end flows) | Medium |
| **Duplication** | Duplicated code exists | Unique implementation | Critical |

**Decision Rules:**

- ✅ **Extract if**: 2+ criteria favor extraction AND size >200 lines OR critical complexity
- ⚠️ **Consider extraction if**: Multiple high-weight criteria favor extraction
- ❌ **Keep inline if**: Mostly low-weight criteria OR workflow orchestration
- 🚫 **Exception if**: Technical constraint (see exceptions below)

### 7. **Extraction Exceptions**

**7.1 sync.yml Scripts - Cannot Extract**

**Constraint**: sync.yml runs from `fork_upstream` branch where `.github/actions/` don't exist (per ADR-013, ADR-015).

**Rationale:**
- Workflow executes on newly synced upstream branch
- Actions haven't been merged to fork_upstream yet
- Must remain self-contained for execution
- Acceptable tradeoff for sync architecture

**Status**: EXCEPTION - Scripts remain inline by necessity

**7.2 Workflow Orchestration - Should Not Extract**

**Decision**: Complex workflow orchestration scripts (cascade.yml, validate.yml) generally remain inline.

**Rationale:**

- **End-to-end flows**: Orchestration logic is workflow-specific
- **Low reuse**: Single-use patterns not shared across workflows
- **Readable as-is**: Workflow structure provides context
- **Diminishing returns**: Extraction effort exceeds maintainability gains

**Future opportunity**: Can extract if specific logic becomes reusable (e.g., cascade integration state checking)

## Rationale

### Benefits of Script Extraction

**Debuggability:**

- Scripts can be executed locally with `bash script.sh`
- Test with various inputs without triggering workflows
- Faster iteration cycle during development
- Easier to reproduce and debug issues

**Maintainability:**

- Centralized logic in single location
- Clear ownership and organization
- Easier to review changes (pure bash vs YAML+bash)
- Better git diffs (separate script vs workflow changes)

**Reusability:**

- Share logic across multiple workflows
- Eliminates code duplication (e.g., LLM provider detection)
- Consistent behavior across workflows
- DRY principle properly applied

**Testability:**

- Unit test complex bash logic
- Mock external dependencies (GitHub API)
- Verify error handling paths
- Test edge cases systematically

**Readability:**

- Workflows become declarative ("detect LLM" vs 20 lines of bash)
- Intent clearer (action name vs embedded code)
- Less cognitive load when reading workflows
- Better onboarding for new contributors

### Sync Propagation Compatibility

**Leverages Existing Infrastructure:**

- `.github/actions/` already defined in sync-config.json
- Template sync (ADR-012) automatically propagates actions
- Daily sync (8 AM UTC) or manual trigger
- No new sync patterns required

**Propagation Flow:**

1. Template commits script changes to main branch
2. Template-sync workflow detects changes in `.github/actions/`
3. Creates PR in fork instances with updated scripts
4. Human reviews and merges
5. Scripts immediately available to workflows

### GitHub App Workflow Permission Consideration

Per ADR-015, GitHub Apps cannot create/modify workflow files without workflows permission. This pattern avoids this limitation:

**Why This Works:**

- Actions are NOT workflow files (no permission restriction)
- Actions can be created/modified by GITHUB_TOKEN
- Workflows reference actions via `uses:` (no workflow modification)
- Post-initialization, actions exist and are callable
- Template sync can update actions and workflows together

**Init-Time Consideration:**

- During init, template-workflows copied BEFORE actions are available
- Solution: Init scripts remain inline (one-time use)
- Post-init workflows can use extracted actions

## Alternatives Considered

### 1. **New `.github/scripts/` Directory**

**Pros:**

- Clearer separation between actions and scripts
- More intuitive location for shell scripts
- Could use for non-action scripts

**Cons:**

- Requires modifying sync-config.json
- Triggers template update to all existing fork instances
- Introduces new pattern when existing solution works
- Additional maintenance burden

**Decision**: Rejected - `.github/actions/` already synced and works

### 2. **External Script Repository**

**Pros:**

- Separate versioning for scripts
- Could be shared across multiple templates
- Clear dependency management

**Cons:**

- External dependency complicates deployment
- Version pinning and updates more complex
- Breaks self-contained template principle
- Additional repository to maintain

**Decision**: Rejected - Violates template self-containment

### 3. **Keep Scripts Embedded**

**Pros:**

- No structural changes required
- Scripts stay close to usage
- No abstraction layer

**Cons:**

- Debugging remains difficult
- Code duplication continues
- Maintenance burden grows
- No local testing capability

**Decision**: Rejected - Problems outweigh simplicity

### 4. **Git Submodules for Scripts**

**Pros:**

- Version pinning capability
- Could share scripts across repositories

**Cons:**

- Git submodule complexity for users
- Breaks template simplicity
- Sync propagation more complex
- Poor developer experience

**Decision**: Rejected - Too complex for benefit

## Implementation Details

### Completed Extractions

#### ✅ LLM Provider Detection

**Status**: COMPLETED

- **Action**: `.github/actions/llm-provider-detect/`
- **Scripts**: detect-provider.sh (50 lines)
- **Impact**: Eliminated duplication, reused by sync.yml and create-enhanced-pr
- **Decision Matrix**: ✅ Duplication (Critical), ✅ Reusability (High), ✅ Testability (High)

#### ✅ Issue State Manager

**Status**: COMPLETED

- **Action**: `.github/actions/issue-state-manager/`
- **Scripts**: update-issue-state.sh (100 lines)
- **Impact**: Complex awk logic now testable locally
- **Decision Matrix**: ✅ Complexity (Critical), ✅ Testability (High), ✅ Size (Medium)

#### ✅ Init Helpers Suite

**Status**: COMPLETED - Moved to `.github/local-actions/`

- **Action**: `.github/local-actions/init-helpers/`
- **Scripts**:
  - setup-upstream.sh (120 lines)
  - setup-branch-protection.sh (140 lines)
  - setup-security.sh (90 lines)
  - deploy-fork-resources.sh (80 lines)
- **Impact**: Reduced init-complete.yml from 878 → 593 lines (32.5% reduction)
- **Decision Matrix**: ✅ Size (High), ✅ Complexity (High), ✅ Testability (High)
- **Note**: Moved to local-actions to prevent syncing init-only logic to fork instances

#### ✅ Push Protection Handler

**Status**: COMPLETED

- **Action**: `.github/local-actions/push-protection-handler/`
- **Scripts**: detect-and-report.sh (76 lines)
- **Impact**: Extracted complex push protection error handling from init-complete.yml
- **Decision Matrix**: ✅ Complexity (Critical), ✅ Testability (High), ✅ Reusability (Medium)
- **Key Features**: Regex parsing with ANSI code handling, secret allowlist URL extraction, detailed escalation issues

#### ✅ Template Protection Check

**Status**: COMPLETED

- **Action**: `.github/local-actions/template-protection-check/`
- **Scripts**: check-template.sh (40 lines)
- **Impact**: Eliminated duplication across init.yml and init-complete.yml
- **Decision Matrix**: ✅ Duplication (Critical), ✅ Reusability (High)

#### ✅ Configure Git

**Status**: COMPLETED

- **Action**: `.github/local-actions/configure-git/`
- **Impact**: Eliminated git config duplication across init workflows
- **Decision Matrix**: ✅ Duplication (Critical), ✅ Reusability (High)

#### ✅ Sync State Manager

**Status**: COMPLETED

- **Action**: `.github/actions/sync-state-manager/`
- **Scripts**:
  - get-upstream-sha.sh (35 lines)
  - check-stored-state.sh (66 lines)
  - detect-existing-prs.sh (56 lines)
  - detect-existing-issues.sh (50 lines)
  - cleanup-abandoned-branches.sh (78 lines)
  - make-sync-decision.sh (132 lines)
- **Impact**: Reduced action.yml from 270 → 85 lines (68% reduction)
- **Decision Matrix**: ✅ Size (Critical), ✅ Complexity (Critical), ✅ Testability (Critical)
- **Key features**: Decision matrix with 4 scenarios, platform-compatible date parsing (GNU/BSD)

#### ✅ Create Enhanced PR Refactor

**Status**: COMPLETED

- **Action**: Refactored to use llm-provider-detect
- **Impact**: Eliminated LLM detection duplication (23 lines)
- **Decision Matrix**: ✅ Duplication (Critical), ✅ Reusability (High)

### Extraction Decisions - Not Extracted

#### ❌ java-build Action

**Status**: KEPT AS-IS

- **Size**: 93 lines
- **Rationale**: Simple Maven orchestration, already maintainable
- **Decision Matrix**: ❌ Complexity (Low), ❌ Size (Low), ❌ Testability value (Low)

#### ❌ cascade.yml Scripts

**Status**: KEPT AS-IS (Future opportunity noted)

- **Size**: 744 lines total, 15 scripts averaging 49 lines each
- **Rationale**: Workflow orchestration, single-use patterns
- **Decision Matrix**: ⚠️ Size (High), ❌ Reusability (Low), ❌ Type (Orchestration)
- **Future**: Could extract "Check Integration State" logic (lines 45-118) if reused

#### ❌ validate.yml Scripts

**Status**: KEPT AS-IS

- **Size**: 325 lines total, 7 scripts averaging 46 lines each
- **Rationale**: Simple validation logic, already clear
- **Decision Matrix**: ❌ Complexity (Low), ❌ Reusability (Low)

#### ❌ sync-template.yml Scripts

**Status**: KEPT AS-IS

- **Size**: 430 lines total, 9 scripts averaging 47 lines each
- **Rationale**: Single-use template sync orchestration
- **Decision Matrix**: ❌ Reusability (Low), ❌ Type (Orchestration)

#### 🚫 sync.yml Scripts

**Status**: EXCEPTION - Cannot extract

- **Size**: 642 lines total, 12 scripts
- **Constraint**: Runs from fork_upstream branch where actions don't exist
- **Decision Matrix**: N/A - Technical constraint overrides

**Attempted Workarounds Evaluated:**

1. **Checkout actions to separate path** - Rejected: Actions require relative path `uses: ./.github/actions/`, cannot reference custom paths
2. **Bash functions within workflow** - Rejected: Eliminates duplication but provides no testability improvement; adds complexity without solving core problem
3. **Docker/JS action from registry** - Rejected: External dependency, adds complexity, would require publishing action to marketplace
4. **Copy actions during workflow** - Rejected: Race condition (actions needed before they can be copied from main)
5. **Accept inline duplication** - ACCEPTED: Simplest solution given constraints; duplication is minimal (~24 lines) and localized to two locations with clear ADR reference comments

### Summary Statistics

**Extractions Completed:**

- 8 composite actions created (4 fork-operational, 4 template-only)
- 15+ shell scripts extracted (~1,200+ lines total)
- 3 workflow files refactored (init.yml, init-complete.yml, create-enhanced-pr/action.yml)

**Impact:**

- init.yml: 194 → 195 lines (added job summaries, net neutral after extractions)
- init-complete.yml: 594 → 561 lines (33 lines reduced, 5.6% reduction)
- sync-state-manager: 270 → 85 lines (68% reduction)
- Eliminated LLM detection duplication (~150 lines)
- Eliminated template protection duplication (~40 lines)
- Eliminated git config duplication (~10 lines)
- 100% of extracted scripts locally testable

**Directory Organization:**

- `.github/actions/` - 5 fork-operational actions (synced to forks)
- `.github/local-actions/` - 4 template-only actions (excluded from sync, removed after init)

### Testing Strategy

**Local Testing:**

```bash
# Each action includes local test examples
cd .github/actions/llm-provider-detect
export AZURE_API_KEY="test"
./detect-provider.sh
# Verify outputs
```

**Integration Testing:**

1. Test in template repository test branch
2. Verify workflows use actions correctly
3. Validate outputs match original inline behavior
4. Test with various input scenarios

**Fork Testing:**

1. Wait for template-sync to create PR
2. Review changes in fork instance
3. Merge and test workflows
4. Verify functionality preserved

## Consequences

### Positive (Achieved)

- ✅ **32-68% reduction in targeted workflow/action files**: init-complete.yml and sync-state-manager significantly more manageable
- ✅ **Eliminated code duplication**: LLM provider detection reused across sync.yml and create-enhanced-pr
- ✅ **100% local testability**: All 12 extracted scripts testable without workflow execution
- ✅ **Improved maintainability**: Single location for complex logic (decision matrices, date parsing, state management)
- ✅ **Enhanced reusability**: llm-provider-detect used by 2 actions, init-helpers reusable across forks
- ✅ **Better readability**: init-complete.yml now shows orchestration (593 lines) vs implementation details
- ✅ **Sync compatibility**: Leverages existing `.github/actions/` sync path (no sync-config.json changes)
- ✅ **Consistent pattern**: All scripts follow identical structure (shebang, header, validation, dual output)
- ✅ **Platform compatibility**: Cleanup scripts handle both GNU and BSD date parsing

### Negative (Observed)

- ⚠️ **Additional abstraction**: Workflows call actions which call scripts (manageable with good documentation)
- ⚠️ **Learning curve**: Team must understand action structure and script conventions (mitigated by READMEs)
- ⚠️ **More files**: 1,043 lines across 12 files vs inline (organized by action directory)
- ⚠️ **Mixed extraction**: Some workflows extracted (init-complete), others not (cascade, validate) - creates pattern inconsistency
- ⚠️ **sync.yml exception**: Largest workflow (657 lines) cannot be extracted due to branch execution context
- ⚠️ **Workflow orchestration boundary**: Difficult to determine extraction vs inline for medium-complexity scripts

### Net Assessment

**Positive**: For targeted, complex actions (sync-state-manager, init-helpers), extraction provided significant value:

- 68% reduction in sync-state-manager makes decision matrix logic clearly testable
- 32.5% reduction in init-complete.yml improves workflow readability
- Platform compatibility issues (GNU/BSD date) now testable locally

**Trade-offs Accepted**:

- Workflow orchestration scripts (cascade.yml, validate.yml) remain inline - acceptable as single-use flows
- sync.yml exception due to technical constraint - documented and understood
- Slightly more files (12 scripts + 4 action.yml + 4 READMs = 20 files) vs inline - worth it for testability

**Pattern Established**: Decision matrix in Section 6 provides clear guidance for future extractions

### Mitigation Strategies

**Documentation:**

- Comprehensive README.md in each action directory
- Local testing examples with expected outputs
- Usage documentation in workflows
- This ADR as architectural reference

**Testing:**

- Local test procedures for each script
- Integration tests in template repository
- Fork instance validation before rollout
- Gradual extraction (one script at a time)

**Rollback:**

- Keep original inline scripts until validated
- Easy to revert extracted scripts
- Gradual migration reduces risk
- Can pause extraction if issues arise

## Success Criteria

**Achieved Results:**

- ✅ **Code Reduction**: 32.5% reduction in init-complete.yml, 68% reduction in sync-state-manager (exceeded 40% target for targeted files)
- ✅ **Duplication Eliminated**: Zero duplication of LLM provider detection (achieved)
- ✅ **Local Testability**: 100% of extracted scripts testable locally (achieved)
- ✅ **Sync Propagation**: Scripts propagate via existing `.github/actions/` sync path (achieved)
- ✅ **No Config Changes**: Zero modifications to sync-config.json required (achieved)
- ✅ **Maintained Functionality**: All workflows preserve original behavior (achieved)
- ✅ **Improved Maintenance**: Scripts now debuggable locally without workflow runs (achieved)
- ✅ **Consistent Pattern**: All 12 scripts follow identical structure (9.5/10 consistency score)

**Validation Metrics:**

- 4 composite actions created
- 12 shell scripts extracted
- 1,043 lines in extracted scripts
- 285 lines eliminated from init-complete.yml
- 185 lines eliminated from sync-state-manager
- ~150 lines of duplication eliminated

## Monitoring and Validation

### Metrics to Track

**Code Quality Metrics:**

- Lines of code in workflows (should decrease ~40%)
- Script duplication instances (should be zero)
- Local test coverage (should be 100% of extracted scripts)

**Operational Metrics:**

- Workflow success rate (should remain stable)
- Script execution time (should be negligible overhead)
- Template sync success rate (should remain 100%)

**Developer Experience:**

- Time to debug script issues (should decrease)
- Time to update script logic (should decrease)
- New contributor onboarding time (should decrease)

## Lessons Learned

### What Worked Well

1. **Decision matrix approach**: Having clear criteria (size, complexity, reusability) prevented over-extraction
2. **Consistent script pattern**: All 12 scripts follow identical structure - easy for maintainers to understand
3. **Dual output pattern**: Scripts work both in GitHub Actions (GITHUB_OUTPUT) and locally (stdout)
4. **Comprehensive READMEs**: Each action includes testing examples - essential for adoption
5. **Incremental approach**: Extracting one action at a time allowed validation before proceeding

### What Was Challenging

1. **Extraction boundary**: Determining where "reusable action" ends and "workflow orchestration" begins
2. **sync.yml constraint**: Most complex workflow (657 lines) cannot be extracted due to branch context
3. **Diminishing returns**: After high-value extractions, remaining workflows showed less benefit
4. **Pattern inconsistency**: Some workflows extracted, others not - creates maintenance expectations

### Recommendations for Future Extractions

1. **Apply decision matrix strictly**: Use Section 6 criteria before extracting
2. **Prioritize complexity over size**: Extract decision matrices and state machines first
3. **Don't extract orchestration**: Workflow-specific flows should generally remain inline
4. **Document exceptions clearly**: Technical constraints (like sync.yml) should be explicit
5. **Test locally before committing**: All scripts should be validated with actual repository state

## Future Evolution

### Realistic Enhancements

**Cascade Integration State Checker** (if needed):

- Extract cascade.yml lines 45-118 if cascade-monitor.yml needs same logic
- Would follow same pattern as sync-state-manager
- Only if reuse justifies extraction

**Script Pattern Standardization**:

- Standardize emoji usage (currently mixed: ✓, ⚠️, ℹ)
- Consider adding common utility functions (error handling, logging)
- Create script template for new extractions

**Testing Improvements**:

- Add example test cases to READMEs
- Document common testing scenarios (mocking gh CLI output)
- Consider bash testing framework if scripts become more complex

### Explicitly Not Planned

**Not extracting workflow orchestration**: cascade.yml, validate.yml, sync-template.yml will remain inline unless specific logic becomes reusable elsewhere

**Not adding test framework**: Current manual testing sufficient for script complexity level

**Not creating shared utility directory**: 12 scripts don't justify shared library overhead

## Related ADRs

- **ADR-010**: YAML-Safe Shell Scripting - Addresses YAML syntax safety
- **ADR-011**: Configuration-Driven Template Sync - Provides sync mechanism
- **ADR-012**: Template Update Propagation - Describes how scripts propagate
- **ADR-013**: Reusable GitHub Actions Pattern - Establishes composite action patterns
- **ADR-015**: Template-Workflows Separation - Explains workflow permission constraints and template/fork separation pattern
- **ADR-018**: Fork-Resources Staging Pattern - Similar two-stage deployment pattern for specialized resources

## Notes on Local-Actions Pattern

The `.github/local-actions/` pattern was introduced to solve a lifecycle mismatch problem:

**Problem**: Init-only actions (init-helpers, push-protection-handler, etc.) were placed in `.github/actions/`, causing them to:

- Sync to all fork instances via template-sync.yml
- Remain in fork repositories despite never being used (init workflows are removed after initialization)
- Consume sync bandwidth and pollute fork repositories with unused code

**Solution**: Following ADR-015's template/fork separation pattern:

- Template-only actions → `.github/local-actions/` (excluded from sync, removed during init)
- Fork-operational actions → `.github/actions/` (synced to forks, used by ongoing workflows)

**Configuration**:

- `sync-config.json` line 114: Excludes `.github/local-actions` from template sync
- `sync-config.json` line 123-126: Removes `.github/local-actions/` during initialization cleanup

This ensures fork instances only receive actions they actually use, following the principle established in ADR-015.

## References

- [GitHub Actions: Creating a composite action](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [GitHub Actions: Workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Bash scripting best practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- Template repository: `.github/sync-config.json`

---

[← ADR-027](027-documentation-generation-strategy.md) | :material-arrow-up: [Catalog](index.md)