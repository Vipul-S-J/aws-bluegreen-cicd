# GitLab CI/CD Setup

Configuration performed in the GitLab UI and on the runner host, in addition to the pipeline defined in [`.gitlab-ci.yml`](../.gitlab-ci.yml). These steps wire up the environments, credentials, and runners that the pipeline depends on.

All real values (access keys, IPs, tokens) below are shown as placeholders — fill them in from your own account and never commit them.

## 1. Create CI/CD Environments

Environments let you track deployments per target (e.g. staging, production).

**GitLab → Settings → Operate → Environments → New environment**

Create the environments referenced by the pipeline, for example:

| Environment | Purpose |
|---|---|
| `production` | Live production fleet |
| `quality_assurance` | QA / staging validation |

The `environment:` block in a pipeline job (see `st-codedeploy-upload` in `.gitlab-ci.yml`) maps the job to one of these environments and its health-check URL.

## 2. Add S3 (AWS) Credentials as CI/CD Variables

The pipeline authenticates to AWS using credentials stored as GitLab CI/CD variables, so no secrets live in the repository.

**GitLab → Settings → CI/CD → Variables → Add variable**

Add the AWS credentials the `aws deploy push` / `aws` CLI steps need:

| Key | Value | Protected | Masked |
|---|---|---|---|
| `AWS_ACCESS_KEY_ID` | `<access-key-id>` | ✓ | ✓ |
| `AWS_SECRET_ACCESS_KEY` | `<secret-access-key>` | ✓ | ✓ |

Recommendations:
- **Masked** — hides the value in job logs.
- **Protected** — only exposes the variable to pipelines on protected branches/tags.
- Scope variables to specific environments where possible, rather than `All (default)`.
- Prefer short-lived credentials or an IAM role with least-privilege (only the S3 bucket and CodeDeploy actions the pipeline requires).

## 3. Create & Register Project Runners on EC2

The pipeline runs on a self-managed GitLab Runner hosted on an EC2 instance.

### Create the runner in GitLab

**GitLab → Settings → CI/CD → Runners → New project runner**

- Allow the runner to run untagged jobs (or tag jobs and the runner consistently).
- Lock the runner to this project if it should not be shared.
- GitLab provides a registration/authentication token — copy it for the next step.

### Register the runner on the EC2 host

Install GitLab Runner on the EC2 instance, then register it against your GitLab instance using the token from above (follow the registration prompts for URL, token, executor, etc.).

### Runner configuration (`config.toml`)

Example global settings used for a single-concurrency project runner:

```toml
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800
```

| Setting | Meaning |
|---|---|
| `concurrent = 1` | Run one job at a time on this runner |
| `check_interval = 0` | Use the default polling interval for new jobs |
| `shutdown_timeout = 0` | Use the default graceful-shutdown timeout |
| `session_server.session_timeout = 1800` | Interactive session timeout, in seconds (30 min) |

After registration, confirm the runner shows **online** and is picking up jobs under **Settings → CI/CD → Runners** (verify platform `linux`, architecture `amd64`, and recent "last contact").

## Notes

- Keep AWS keys, runner tokens, and instance details out of the repository — store them only as masked/protected CI/CD variables or in a secrets manager.
- The pipeline job definitions themselves live in [`.gitlab-ci.yml`](../.gitlab-ci.yml).
