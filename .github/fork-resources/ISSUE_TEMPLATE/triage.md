---
name: 🔍 Triage Request
about: Analyze service dependencies and security posture
title: "[TRIAGE] "
labels: triage, needs-review
assignees: []
---

## Task

Analyze this service's dependencies and security posture using available tools, then produce a detailed report. 

## Checklist

- [ ] Document repository structure and list all POM files
- [ ] Analyze POM hierarchy and relationships
- [ ] Audit dependency versions for updates
- [ ] Scan for security vulnerabilities
- [ ] Create tables for outdated dependencies and vulnerabilities
- [ ] Summarize findings and generate triage report


## Instructions

1. Locate and verify the existence of POM files:
   - Search for files matching **/pom.xml in the service directory.
   - List all found POM files and their locations, numbering each one.
   - If no POM files are found, note this issue but continue analyzing the directory structure.

2. Analyze the repository structure, POM hierarchy, and dependency inheritance:
   - List the main POM files found and describe their relationships.
   - Identify the parent POM and any core or provider modules.
   - Check for profiles in the parent Java project.
   - Focus on the parent POM and any configured Maven profiles.
   - Never include any test projects in your analysis.

3. Identify dependency updates:
   - Analyze the dependencies in each relevant POM file.
   - Create a table of version updates available for each POM, including the dependency name, current version, and latest version.
   - Count the total number of outdated dependencies as you add them to the table.
   - Summarize the findings, noting any patterns or particularly outdated dependencies.

4. Identify security vulnerabilities:
   - Analyze the parent POM and, if applicable, core and azure provider modules for known vulnerabilities.
   - Create a table of security CVE vulnerabilities for each POM, including the severity and affected dependency.
   - Count the total number of vulnerabilities as you add them to the table.
   - Summarize the findings, highlighting any critical or high-severity vulnerabilities.

5. Analyze the findings:
   - Create a preliminary table of vulnerabilities, including severity, dependency, current version, recommended version, and CVE/description.
   - Create a preliminary table of outdated dependencies, including dependency name, current version, latest version, update type, and whether it's in a common library.
   - Categorize vulnerabilities by severity.
   - For each vulnerability and outdated dependency:
     - Brainstorm and note down its potential impact on the system.
     - Consider and describe the associated risk.
     - Suggest a priority level for addressing it.
   - Identify high-priority updates and fixes based on this analysis.

## Report

**Severities:**
- CRITICAL: Active exploit / RCE, requires immediate fix
- HIGH: Major vulnerability, fix this sprint
- MEDIUM: Limited exploit, plan for next maintenance
- LOW: Minimal impact, fix opportunistically

**Update types:**
- PATCH: Low risk (e.g., 1.2.3 → 1.2.4)
- MINOR: Medium risk (e.g., 1.2.3 → 1.3.0)
- MAJOR: High risk (e.g., 1.2.3 → 2.0.0)


**Triage Report Template**
```markdown
# Vulnerability Triage Report 🔍

## Executive Summary
<one-paragraph synopsis and severity counts>

## Vulnerability Findings
| Severity | Dependency | Current | Recommended | CVE/Desc |
|----------|------------|---------|-------------|----------|
|          |            |         |             |          |

## Outdated Dependencies
| Dependency | Current | Latest | Update Type | Module           |
|------------|---------|--------|-------------|----------------|
|            |         |        |             |                |

## POM Hierarchy Overview
<explain inheritance & dependency management>

## Recommendations
### High Priority
1. **Update X → Y** — _Impact:_ ... | _Risk:_ ...

### Medium / Low Priority
<items>

## Fix Location
<which POM(s) to edit>
```


## Remember

1. This is an assessment only — do not suggest code edits.
2. Be thorough in your analysis, considering all aspects of the service's security.
3. Provide clear, actionable recommendations in your triage report.
4. Focus only on the parent POM and the core and azure provider profiles.

Your final output should consist only of the markdown-formatted triage report.