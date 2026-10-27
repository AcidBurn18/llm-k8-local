# AI usage

I used AI assistants while building and reviewing this assessment. Claude was used earlier in the implementation. I later used OpenAI Codex to continue reviewing the repository, troubleshoot the deployment and Makefile, and prepare these submission documents. I reviewed the suggestions, checked them against the project files and deployment results, and made decisions about what to keep. This note describes that assistance honestly; it does not claim AI-generated work as unaided work.

## Where I used assistance

| Work area | How the assistant helped | My review |
|---|---|---|
| FastAPI services and tests | Helped draft and revise service code, error handling, and unit tests. | I reviewed the routes and request flow, then ran Ruff and the service test suite. The last recorded run passed 27 unit tests. |
| Docker and Kubernetes | Helped create or revise Dockerfiles, Deployments, Services, probes, security settings, NetworkPolicies, ingress, HPA, CronJob, and monitoring manifests. | I checked the manifests against the live resources and used the release and smoke checks to verify the main application path. Some controls are present but not fully demonstrated; see [submission status](docs/submission-status.md). |
| Terraform and Makefile | Helped with the Kind and Helm setup, Metrics Server installation, release sequence, scan gate, and explicit Terraform apply prompt. | I reviewed the Terraform plan and approved apply interactively. The release ran through deployment and verification. The environment state-separation gap remains documented. |
| Troubleshooting and learning | Helped explain Makefile targets, image/cache behavior, ingress forwarding, and commands for inspecting pods and logs. | I used the explanation to operate and inspect the local cluster and wrote a practical guide for future debugging. |
| Documentation | Helped organize the deliverables and compare project claims with the assignment and actual files. | I corrected stale or unsupported claims and marked unfinished checks as open instead of presenting them as complete. |

## Representative prompts

These are examples paraphrased from the work, not a complete transcript:

- “Review the assignment requirements and make a list of the required application, infrastructure, security, testing, and documentation deliverables.”
- “Add Metrics Server through Terraform so the gateway HPA and `kubectl top` can use Kubernetes resource metrics.”
- “Keep the ingress allowlist testable from my Mac, including an allowed client address and a blocked address, and explain what the forwarded client IP is doing.”
- “Make Terraform apply wait for an explicit `apply` response, then let Terraform ask for its own final approval.”
- “Analsye the Security Flaws related to Terraform providers version”
- “Create clear docs from the assessment requirements that I can share with the reviewer.”

## What I accepted, changed, or did not claim

- I kept the simple FastAPI service split, local Kind environment, digest-pinned Python base image, model weights on a PVC, and explicit plan/apply workflow.
- I asked for Metrics Server to be managed by Terraform and reviewed the local-only kubelet TLS setting required by this Kind setup.
- I used an explicit `ALLOW_HIGH_VULNS=true` override for the latest release after Trivy reported findings. That allowed deployment to continue, but it did not fix or suppress the findings; the reports are included.
- I did not keep stale documentation that said the model revision was `main`, that all logs went to Loki, or that environment state was isolated. Those statements did not match the code.
- I did not describe NetworkPolicy enforcement, CronJob execution, alert firing, load-driven HPA scaling, browser certificate trust, or bad-release rollback as verified..

## How I checked the work

- Ruff completed with no lint findings, and the last recorded service test run passed 27 tests.
- I reviewed the Terraform plan and approved the dev apply explicitly. The local release built and scanned all four images, generated SBOMs, loaded images into Kind, and applied Kubernetes resources.
- The model downloader Job completed, application deployments became ready, and all six recorded smoke checks passed, including an end-to-end LLM request and allowed/blocked forwarded-IP cases.
- `kubectl top` returned node and app pod metrics after Metrics Server was installed through Terraform.
- I checked the current assignment brief and compared the documentation with the manifests, Makefile, model downloader, and scan reports. The remaining gaps are listed in [submission status](docs/submission-status.md).

## Risks and mitigations

| Risk | How I addressed it |
|---|---|
| Incorrect Kubernetes or Terraform details | Checked resource names and settings against the repository and deployment output. I marked unverified behavior clearly. |
| Security advice that looks complete but is not enforced | Distinguished manifests from tested enforcement. For example, NetworkPolicy objects are present, but a blocked pod-to-pod test is still needed. |
| Vulnerable dependency or base image | Pinned the Python base image by digest and saved Trivy reports. The reports still include HIGH findings and a CRITICAL finding in the LLM image, so those need review before promotion. |
| Model license or artifact provenance | Kept the Hugging Face source, exact repository revision, license, and expected weight checksum in [model delivery](model/README.md). I checked the pinned repository revision and its Apache-2.0 metadata on Hugging Face. |
| AI text sounding authoritative when uncertain | Compared it to the source files and evidence, corrected stale claims, and listed known gaps rather than filling them with assumptions. |

AI use does not replace my responsibility to understand and explain the implementation. I will use the [hands-on guide](docs/hands-on-code-and-deployment.md) to walk through the code, requests, logs, and deployment steps during review.
