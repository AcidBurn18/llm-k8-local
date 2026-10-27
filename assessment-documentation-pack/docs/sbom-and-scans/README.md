# SBOM and vulnerability scan evidence

These files were generated from the four local application images used for the dev Kind release. They are evidence from the local assessment run, not a promise that later builds have the same contents.

## Images and files

| Image | Syft SBOM | Trivy report |
|---|---|---|
| `gateway:v1` | [gateway-sbom.json](gateway-sbom.json) | [gateway-trivy.txt](gateway-trivy.txt) |
| `catalog:v1` | [catalog-sbom.json](catalog-sbom.json) | [catalog-trivy.txt](catalog-trivy.txt) |
| `assistant:v1` | [assistant-sbom.json](assistant-sbom.json) | [assistant-trivy.txt](assistant-trivy.txt) |
| `llm:v1` | [llm-sbom.json](llm-sbom.json) | [llm-trivy.txt](llm-trivy.txt) |

## Tools and format

- **SBOM generator:** Syft `1.55.0`; output format: SPDX JSON `2.3`.
- **Vulnerability scanner:** Trivy `0.69.3`; the recorded vulnerability database was updated on 2026-10-26.
- **Image tag:** `v1` for each application image.
- **Base image:** `python:3.11-slim@sha256:b7a9e5f6a93d6d4a31f129bbd4bdee69efccb6ded0fb230d78aafaf37af98377`.

The Makefile's `sbom` and `scan` targets regenerate these outputs from local images. `make check` runs both targets after building the images.

## Findings and release decision

The reports contain HIGH vulnerability findings in OS and Python packages, and the LLM report includes a CRITICAL finding. The latest release was run with `ALLOW_HIGH_VULNS=true`; that explicitly let the release pass the severity gate while preserving the scanner output. It did not remediate the findings. Review the individual entries and patch or otherwise accept each finding before using these images outside the local exercise.

Trivy prints a summary for more than one package source/layer in a report. Do not add those summary totals together and describe the result as unique CVEs; review the full report and match each finding to the affected package and image layer.

## Reproduce locally

After building the local `v1` images, run:

```bash
make sbom
make scan
```

By default, `make scan` fails when it finds HIGH or CRITICAL findings. To deliberately permit the scan gate for a local assessment release, use:

```bash
make release ENV=dev ALLOW_HIGH_VULNS=true
```

Keep the reports with the same release they describe. If image contents or tags change, regenerate both the SBOMs and scan reports so they remain aligned.
