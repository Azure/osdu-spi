## SPI Separation Fork

### Overview

The SPI Separation Fork Process streamlines the management of long-lived forks specifically for the Open Subsurface Data Universe (OSDU), addressing how and where Cloud Provider Interface (SPI) code is developed and maintained. This process ensures efficient integration of community-defined core code from OSDU, validated and tested against a fully open-source Community Implementation, with proprietary SPI implementations (such as Azure Cloud Provider code) that leverage Azure-specific technologies. It automates synchronization, minimizes manual maintenance, and delivers buildable code to downstream Microsoft offerings, notably Azure Data Manager for Energy (ADME).

### Problem Statement

A critical challenge in maintaining forks of OSDU is effectively managing the development of Cloud Provider-specific implementations separately from the core OSDU community code. Microsoft must clearly separate its Azure Cloud Provider Interface (SPI) implementation from the upstream OSDU core code, which is built, validated, and tested against an open-source Community Implementation. Maintaining this separation ensures efficient integration of upstream core updates, preserves the integrity of proprietary SPI-layer enhancements, and enables consistent, buildable code delivery for downstream consumption by ADME. Failure to maintain clear boundaries between the open-source stack used by OSDU and Microsoft's Azure-specific stack leads to integration inefficiencies, delayed releases, and increased risk of divergence from upstream community standards.

### Objectives

The SPI Separation Fork Process aims to:

* Automate synchronization with upstream OSDU repositories.
* Clearly restrict local development exclusively to the Azure Cloud Provider Interface (SPI) layer.
* Ensure necessary changes to OSDU core code are escalated upstream, maintaining core integrity.
* Provide downstream Microsoft offerings (such as ADME) with stable, buildable SPI-layer code without requiring additional modifications.
* Establish predictable and transparent versioning and code delivery mechanisms for downstream consumption.

### Architecture and Workflow

#### Branch Management Strategy

The process employs a structured three-branch model:

* **fork\_upstream**: Precisely tracks the upstream OSDU core code and interfaces, maintaining an unmodified reference state.
* **fork\_integration**: Serves as the workspace to merge upstream updates, resolve conflicts, and validate compatibility of the Azure SPI implementations with core changes.
* **main**: A stable and protected branch exclusively containing tested Azure SPI-layer code ready for downstream builds.

#### Automated Workflow

The SPI Separation Fork Process incorporates automated workflows designed to streamline essential activities:

* **Scheduled Upstream Synchronization**: Periodically fetches upstream OSDU core changes and interfaces, automatically integrating them into the forked environment.
* **Conflict Management**: Automatically identifies and isolates conflicts during the integration of upstream updates with local Azure SPI-layer code, facilitating efficient manual resolution.
* **Release and Versioning**: Generates consistent and reliable version tags and documentation, providing clear, stable points from which downstream systems like ADME can reliably pull and build code into managed releases.

### Technical Implementation

The process exclusively uses native GitHub capabilities without external dependencies, providing automated validation for commits, merges, and builds. Integrated security scanning ensures compliance and secure delivery of the Azure SPI code. Additionally, intelligent automation powered by AI and GitHub Copilot enhances the workflow by analyzing upstream changes, generating descriptive commit messages and pull request descriptions, and automating structured changelog creation. AI assistance streamlines issue resolution tasks such as simple merge conflict handling, resolving compile issues due to dependency updates, and adapting to small interface changes from upstream.

### Benefits

Adopting this structured approach significantly reduces manual integration efforts and operational disruptions by clearly separating Azure SPI development from OSDU core changes. It enables developers to focus on innovation, accelerating feature delivery, reducing technical debt, and protecting proprietary Azure SPI developments. Moreover, consistent fork management, enhanced compliance, clearly documented processes, and structured code delivery simplify audits and ensure reliable downstream integrations with managed offerings like ADME.

Additionally, separating the Azure SPI code from the core OSDU community implementation resolves a key dependency issue. Under the previous approach, if any Cloud Provider SPI layer failed to compile or test successfully, it blocked merging code into the main branch. This separation eliminates the risk of being blocked by other Cloud Providers' failures or incomplete implementations.

### Risks and Mitigation Strategies

A key risk involves managing frequent contract changes or core code modifications from the upstream OSDU community, potentially requiring significant unplanned development efforts. This dynamic scenario cannot typically be addressed in traditional quarterly planning cycles, creating a need for a more agile approach. To mitigate this, teams will leverage AI to proactively detect changes and streamline immediate adjustments, although some manual intervention will inevitably still be required.

Another risk is managing the complexity of software development workflows—particularly the context switching required between upstream community implementations and proprietary SPI-layer development. Downstream development should be limited to infrastructure and software installation mechanisms (e.g., Helm charts, Infrastructure as Code, and deployment sequencing), while SPI-layer developers need effective inner-loop workflows that integrate seamlessly with Azure-specific tech stacks. Similarly, upstream developers require efficient inner-loop workflows compatible with the open-source Community Implementation running locally. Leveraging creative use of AI, such as MCP Servers, Step Prompts, and agentic assistants, can significantly reduce friction, streamline workflow management, and assist individual developers in efficiently navigating the challenges of context switching between different inner-loop processes.

### Recommended Next Steps

Given the complexity and transformative nature of the SPI Separation Fork Process, a practical next step is to develop a targeted, limited-scope prototype. This prototype should demonstrate specific capabilities—such as automated upstream synchronization, conflict management, and intelligent AI assistance—within a realistic infrastructure and CI/CD pipeline environment. The aim is to quickly validate the feasibility of this approach, assess technological challenges, and determine whether intelligent AI integration can effectively support a streamlined development workflow. This experimental approach allows Microsoft to "fail fast," rapidly adapt the concept, and incrementally expand the implementation into a robust, production-ready system.  After the prototype has been proven then move toward an official implementation effort that can be supported as an open source solution.
