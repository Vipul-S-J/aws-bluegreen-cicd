# AWS Blue/Green CI/CD Automation

Infrastructure and deployment automation for a production web application on AWS, built around **AWS CodeDeploy blue/green deployments**, an **Auto Scaling Group with mixed instances (Graviton + x86, On-Demand + Spot)**, and a **GitLab CI → S3 → CodeDeploy** artifact pipeline.

> All environment-specific identifiers (account IDs, bucket names, load balancer names, instance IDs) have been replaced with generic placeholders.

## Architecture Overview

```mermaid
flowchart LR
    Dev["👩‍💻 Developer<br/>git push"]

    subgraph GLCI["🦊 GitLab CI/CD"]
        direction TB
        Build["Stage: build<br/>sbt dist"]
        Upload["Stage: upload<br/>aws deploy push"]
        Build --> Upload
    end

    Dev --> GLCI

    subgraph AWS["☁️ AWS Cloud · Region"]
        direction TB

        S3["🪣 Amazon S3<br/>Artifacts Bucket<br/>app-srv-&lt;build&gt;-&lt;ts&gt;.zip"]
        CD["🚀 AWS CodeDeploy<br/>Blue/Green · AllAtOnce"]

        subgraph VPC["🔒 VPC"]
            direction TB
            ALB["⚖️ Application<br/>Load Balancer"]

            subgraph MULTIAZ["Auto Scaling Group · Multi-AZ (1a / 1b / 1c)"]
                direction LR
                subgraph GREEN["🟢 Green Fleet (new)"]
                    direction TB
                    GInstances["Mixed Instances<br/>Graviton: c7g c6g c8g m6g m7g m8g<br/>x86: c5 c6i c7i m5 m6i m7i<br/>On-Demand base + 30% · rest Spot"]
                end
                subgraph BLUE["🔵 Blue Fleet (old)"]
                    direction TB
                    BInstances["Previous instances<br/>terminated after success<br/>(0-min wait)"]
                end
            end

            CW["📈 CloudWatch<br/>Target Tracking<br/>~1,900 req/target"]
        end

        Upload -->|"upload zip"| S3
        S3 -->|"pulls artifact"| CD
        CD -->|"provision green<br/>(copy ASG)"| GREEN
        ALB -->|"shift traffic"| GREEN
        ALB -.->|"drain + terminate"| BLUE
        CW -.->|"scale in / out"| MULTIAZ
    end

    classDef aws fill:#ff9900,stroke:#232f3e,color:#232f3e,stroke-width:1px;
    classDef gitlab fill:#fc6d26,stroke:#232f3e,color:#fff;
    classDef green fill:#d5f5e3,stroke:#1e8449,color:#145a32;
    classDef blue fill:#d6eaf8,stroke:#2471a3,color:#1a5276;
    class S3,CD,ALB,CW aws;
    class Build,Upload gitlab;
    class GInstances green;
    class BInstances blue;
```

## CI/CD Pipeline

The pipeline does **not** use CodeDeploy's native Git integration. Instead it follows an S3-based pattern:

1. **GitLab CI** builds the application artifact.
2. The artifact is zipped and uploaded to an S3 bucket (`<artifacts-bucket>`).
3. **CodeDeploy** pulls the artifact from S3 and runs the deployment.

**Artifact naming convention:**

```
app-srv-<build_number>-<timestamp>.zip
```

## Deployment Strategy — CodeDeploy Blue/Green

- **Deployment config:** `CodeDeployDefault.AllAtOnce`
- **Traffic control:** Application Load Balancer (ALB) shifts traffic from the blue fleet to the green fleet.
- **Green fleet provisioning:** created by copying the existing Auto Scaling Group.
- **Blue fleet termination:** terminated immediately after a successful deployment (0-minute wait).

## Auto Scaling Group — Mixed Instances + Spot

A mixed-instances ASG spread across all three Availability Zones (`1a`, `1b`, `1c`).

| Setting | Value |
|---|---|
| Max capacity | 18 instances |
| Spot allocation strategy | `price-capacity-optimized` |
| On-Demand base capacity | 1 instance |
| On-Demand above base | 30% |
| Remaining capacity | Spot |

**Spot allocation strategy:** `price-capacity-optimized` — AWS selects the capacity pool with the most available capacity at the best price, reducing interruption risk.

### Instance mix

The fleet combines **Graviton (ARM)** and **x86** instance families for cost efficiency and capacity diversity:

- **Graviton:** `c7g.2xlarge`
- **x86:** `c5`, `c4`, `c7i`, `m5a` families

Diversifying across many instance types widens the Spot capacity pools AWS can draw from, improving availability and reducing interruptions.

## Scaling Policy — Target Tracking

Scaling is driven by a **Target Tracking** policy:

- **Metric:** ALB requests per target
- **Target value:** ~1,900 requests per target
- **Target resource:** application load balancer (`<app-load-balancer>`)

The ASG scales out when average requests per target exceed the target, and scales in when demand drops.

## Repository Structure

```
cicd-automation/
├── README.md                        # This document
├── appspec.yml                      # CodeDeploy lifecycle hook mapping
├── Asg-mixed-instance-policy.json   # ASG mixed-instances policy (Graviton + x86, Spot)
├── .gitlab-ci.yml                   # GitLab CI/CD pipeline (build → upload → deploy)
├── docs/
│   ├── codedeploy-setup.md          # AWS CodeDeploy blue/green configuration
│   └── gitlab-setup.md              # GitLab environments, CI/CD variables & runner setup
└── aws-cd/                          # CodeDeploy deployment lifecycle scripts
    ├── after_install.sh
    ├── application_start.sh
    ├── validate_service.sh
    ├── after_block_traffic.sh
    └── update_lifecycle_hook.sh
```

## Documentation

- [CodeDeploy Setup](docs/codedeploy-setup.md) — blue/green application, service role, and deployment group configuration.
- [GitLab Setup](docs/gitlab-setup.md) — environments, CI/CD variables (S3 credentials), and project runner registration on EC2.
- [GitLab Pipeline](.gitlab-ci.yml) — the CI/CD pipeline definition: build, upload, and deploy stages, including the `aws deploy push` to S3.

## Notes

- Keep account IDs, real bucket/ALB names, instance IDs, and credentials out of this repository.
- Store secrets in a secrets manager or CI/CD protected variables, never in source control.
