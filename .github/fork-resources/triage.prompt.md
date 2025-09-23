# Maven Dependency Triage Analysis Prompt 🔍

**Purpose:** Comprehensive Maven dependency analysis and vulnerability triage for enterprise applications

**Usage:** Reference this prompt when performing dependency analysis on forked repositories. This workflow creates enterprise-grade vulnerability triage reports with full traceability.

---

## Triage Analysis Workflow

When performing dependency triage analysis, follow this structured workflow to ensure comprehensive coverage and actionable results.

### Phase 1: Project Discovery
**Objective:** Map the Maven project structure and dependency landscape

**Tasks:**
1. **POM Hierarchy Analysis**
   - Find all POM files: `find . -name "pom.xml" -type f`
   - Map parent-child relationships and inheritance
   - Identify multi-module structure and dependency management
   - Focus on main modules (exclude test/sample projects)
   - Document version property usage

2. **Dependency Extraction**
   - Extract all `<dependency>` declarations from each POM
   - Identify managed dependencies from parent POMs  
   - Note version variables and properties
   - Map dependencies to their declaring modules

**Commands to run:**
```bash
# Find all POMs
find . -name "pom.xml" -type f | head -20

# Extract dependencies from main POM
mvn dependency:list -DoutputFile=dependencies.txt

# Show dependency tree
mvn dependency:tree > dependency-tree.txt
```

### Phase 2: Version Analysis  
**Objective:** Assess current state vs available updates

**Tasks:**
3. **Version Checking**
   - Check for available updates: `mvn versions:display-dependency-updates`
   - Categorize updates: MAJOR/MINOR/PATCH
   - Calculate age of current versions
   - Identify stale dependencies (>1 year old)

4. **Version Compatibility Assessment**
   - Research release notes for critical dependencies
   - Check for breaking changes in major version updates
   - Identify version compatibility constraints

**Commands to run:**
```bash
# Check for dependency updates
mvn versions:display-dependency-updates > version-updates.txt

# Check for plugin updates
mvn versions:display-plugin-updates > plugin-updates.txt

# Display properties that could be updated
mvn versions:display-property-updates > property-updates.txt
```

### Phase 3: Security Assessment
**Objective:** Identify and prioritize security vulnerabilities

**Tasks:**
5. **Vulnerability Scanning**
   - Run OWASP dependency check: `mvn org.owasp:dependency-check-maven:check`
   - Review generated reports for CVE information
   - Cross-reference with version analysis results

6. **Risk Prioritization**
   - Correlate CVE data with dependency versions
   - Assess exploitability and impact (CVSS scores)
   - Map vulnerabilities to available fix versions

**Commands to run:**
```bash
# OWASP Dependency Check
mvn org.owasp:dependency-check-maven:check

# Alternative: Use GitHub Security Advisories
gh api repos/:owner/:repo/vulnerability-alerts

# Check for known vulnerabilities in dependencies
mvn com.github.spotbugs:spotbugs-maven-plugin:spotbugs
```

### Phase 4: Triage Report Generation
**Objective:** Create comprehensive triage report for planning phase

## Required Report Template

```markdown
# [SERVICE_NAME] Service — Dependency Triage Report 🔍

**Report ID:** [service-name]-triage-[YYYY-MM-DD]
**Analysis Date:** [ISO timestamp]
**Workspace:** [repository path]

## Executive Summary
- **Total Dependencies:** [count]
- **Vulnerabilities Found:** [count] (Critical: X, High: Y, Medium: Z)
- **Outdated Dependencies:** [count]/[total] ([percentage]%)
- **Recommended Actions:** [count] (Immediate: X, This Sprint: Y, Next Sprint: Z)

## Critical Findings (Action Required)

### Security Vulnerabilities
| CVE ID | Severity | Dependency | Current | Fix Version | CVSS | Description |
|--------|----------|------------|---------|-------------|------|-------------|
| CVE-XXXX-YYYY | CRITICAL | log4j-core | 2.14.1 | 2.17.1+ | 9.0 | Remote code execution |

### Severely Outdated Dependencies
| Dependency | Current | Latest | Age | Update Type | Risk Level |
|------------|---------|--------|-----|-------------|------------|
| spring-core | 4.3.30 | 6.1.2 | 3.2 years | MAJOR | HIGH |

## Standard Findings (Planned Updates)

### Version Updates Available
| Dependency | Current | Latest Stable | Update Type | Module Location |
|------------|---------|---------------|-------------|-----------------|
| jackson-databind | 2.13.0 | 2.16.1 | MINOR | parent-pom.xml |

### Dependencies Analysis Summary
- **Up to Date:** [count] dependencies
- **Minor Updates:** [count] dependencies  
- **Major Updates:** [count] dependencies
- **Security Updates:** [count] dependencies

## Project Structure Analysis

### POM Hierarchy
```
parent-pom.xml (defines versions)
├── core-module/pom.xml
├── api-module/pom.xml
└── service-module/pom.xml
```

### Dependency Management Strategy
- Version management: [Centralized/Distributed]
- Property usage: [Property names for major deps]
- BOM usage: [Spring Boot BOM, etc.]

## Recommended Update Strategy

### Phase 1: Critical Security (Immediate)
**Priority:** CRITICAL - Deploy within 24-48 hours
**Risk:** LOW - Well-tested security patches

1. **CVE-XXXX-YYYY: log4j-core 2.14.1 → 2.17.1**
   - **Fix Location:** parent-pom.xml line 42
   - **Change:** `<log4j.version>2.17.1</log4j.version>`
   - **Impact:** Security vulnerability resolution
   - **Testing:** Smoke tests + security scan verification

### Phase 2: High Priority Updates (This Sprint)
**Priority:** HIGH - Complete within current sprint
**Risk:** MEDIUM - May require integration testing

[List specific updates with details]

### Phase 3: Maintenance Updates (Next Sprint)
**Priority:** MEDIUM - Complete in next maintenance window
**Risk:** LOW - Standard version bumps

[List remaining updates]

## Implementation Artifacts

### Files Requiring Updates
- `parent-pom.xml` (line references for each change)
- `core-module/pom.xml` (specific dependency overrides)
- [Additional POM files as needed]

### Version Control Strategy
**Recommended Branch:** `feature/security-updates-[service-name]`
**Commit Pattern:** `fix(deps): update [dependency] to [version] for [CVE/reason]`
**PR Template:** Include security scan results and test evidence

## Testing Requirements
- [ ] All unit tests pass
- [ ] Integration tests complete successfully
- [ ] Security scan shows resolved vulnerabilities
- [ ] No new vulnerabilities introduced
- [ ] Application startup verification
- [ ] Smoke tests for critical paths

## Success Criteria
- All CRITICAL and HIGH vulnerabilities resolved
- No build failures or test regressions
- Security scan passes with acceptable risk level
- Dependencies updated to secure, stable versions
- Documentation updated with changes

---
**Next Step:** Create implementation plan based on this triage report
```

### Phase 5: Documentation and Handoff
**Objective:** Prepare analysis results for implementation planning

**Tasks:**
7. **Report Finalization**
   - Complete all sections of the triage report
   - Validate accuracy of version information and CVE details
   - Ensure all findings include specific file locations
   - Add implementation timeline recommendations

8. **Implementation Preparation**
   - Create branch for dependency updates
   - Document testing strategy for each update phase
   - Prepare rollback plan for critical updates
   - Set up monitoring for post-update validation

## Critical Success Factors

### Completeness Checklist
- [ ] All POM files analyzed for dependencies
- [ ] All vulnerabilities captured with CVE IDs and severity
- [ ] All outdated dependencies identified with versions
- [ ] All recommendations include specific file locations
- [ ] Implementation timeline aligns with risk levels

### Quality Standards
- All vulnerabilities must include CVE IDs and fix versions
- All dependencies must include current version and latest available
- All recommendations must include specific file locations and line numbers
- All findings must be categorized by priority and risk level
- Report must be actionable for immediate implementation

### Implementation Guidelines

**Analysis Commands Sequence:**
```bash
# 1. Project structure discovery
find . -name "pom.xml" -type f
mvn dependency:tree > dependency-tree.txt

# 2. Version analysis
mvn versions:display-dependency-updates > version-updates.txt
mvn versions:display-plugin-updates > plugin-updates.txt

# 3. Security scanning
mvn org.owasp:dependency-check-maven:check
gh api repos/:owner/:repo/vulnerability-alerts

# 4. Generate reports
cat target/dependency-check-report.html # Review in browser
cat version-updates.txt # Analyze available updates
```

**Data Collection Requirements:**
- Extract complete dependency list with versions and POM locations
- Capture vulnerability data with CVE IDs, CVSS scores, and affected versions
- Document POM inheritance structure and version property usage
- Identify all version management patterns (BOMs, properties, direct versions)

**Risk Assessment Matrix:**
- **CRITICAL:** Active exploits, RCE vulnerabilities, auth bypasses
- **HIGH:** Data exposure, privilege escalation, major security flaws  
- **MEDIUM:** Information disclosure, DoS vulnerabilities, outdated dependencies (>2 years)
- **LOW:** Minor security issues, maintenance updates, performance improvements

## Workflow Integration

This triage analysis integrates with the fork management workflow:

1. **Trigger:** Run before major upstream merges or quarterly maintenance
2. **Dependencies:** Requires Maven project with accessible POMs
3. **Outputs:** Structured triage report for implementation planning
4. **Follow-up:** Use report to create prioritized update implementation plan

**Begin comprehensive triage analysis now. The quality of this analysis directly impacts the effectiveness of dependency update planning and security posture maintenance.**