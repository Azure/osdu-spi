# Setup Maven Action

Installs the template-pinned Apache Maven and puts it first on `PATH`, so a runner image update can't change the Maven version or its default plugin versions under a fork's build.

## How It Fits

Every Maven build the template runs calls this action before Maven: `java-build` (validation, Dependabot validation and the push build), the coverage job in `build.yml`, the cascade's integration build in `cascade.yml`, and `copilot-setup-steps.yml`.

## Behavior

- Downloads `apache-maven-<version>-bin.tar.gz` from Maven Central and verifies it against the pinned SHA-512 before extracting. A mismatch fails the step.
- Installs into the runner tool cache (`$RUNNER_TOOL_CACHE/maven/<version>/x64`) and skips the download when that version is already there.
- Prepends its `bin` to `GITHUB_PATH`, sets `M2_HOME`, and prints `mvn -v` so the build log records the version used.

The action takes no inputs. The version is a template constant, not a per-fork setting, so `BUILD_ENV` refuses `M2_HOME` and `MAVEN_HOME`.

## Updating the Pin

`MAVEN_VERSION` and `MAVEN_SHA512` sit together in `action.yml`. To move the pin:

1. Take the new version's SHA-512 from the `.sha512` file Apache publishes beside the archive on Maven Central (`https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/<version>/apache-maven-<version>-bin.tar.gz.sha512`).
2. Update both values in one commit.
3. Prove the change on a service lane before release. A minor version (3.9 to 3.10) can change default plugin versions and with them the packaged service.
