---
name: ci-cd
description: >
  CI/CD pipelines for .NET 10 applications on GitHub Actions deploying to AWS.
  Covers build and test workflows, OIDC authentication to AWS (no long-lived keys),
  NuGet pack and push to AWS CodeArtifact, container images to Amazon ECR, and
  deployment to Amazon ECS Fargate with environment approvals. Load this skill when
  setting up continuous integration, automated testing, deployment workflows, or when
  the user mentions "CI/CD", "pipeline", "GitHub Actions", "workflow", "deploy",
  "build pipeline", "publish", "NuGet push", "release", "continuous integration",
  "CodeArtifact", "ECR", "ECS", "Fargate", or "OIDC".
---

# CI/CD

## Core Principles

1. **Build once, promote the artifact** — Build and test one package or image per commit, then deploy that same artifact to staging and production. Never rebuild per environment.
2. **OIDC to AWS, never access keys** — GitHub Actions assumes an IAM role through OpenID Connect and gets short-lived credentials. No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in repository secrets.
3. **Least-privilege role per job** — The CI role can publish to CodeArtifact/ECR; only the deploy role can update ECS. Scope each role's trust policy to the repo, branch, or environment.
4. **Quality gates before merge** — `dotnet build`, `dotnet test`, and `dotnet format --verify-no-changes` must pass on every pull request.
5. **Secrets are read at runtime** — The app loads secrets from AWS Secrets Manager / Parameter Store (see the `configuration` skill). Never bake them into images or workflow environment variables.

## Patterns

### CI Workflow (Pull Requests and master)

```yaml
# .github/workflows/ci.yml
name: ci

on:
  pull_request:
  push:
    branches: [master]

permissions:
  contents: read

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x
          cache: true                                   # needs packages.lock.json
          cache-dependency-path: '**/packages.lock.json'

      - run: dotnet restore --locked-mode
      - run: dotnet format --verify-no-changes --no-restore
      - run: dotnet build -c Release --no-restore
      - run: dotnet test -c Release --no-build --collect:"XPlat Code Coverage" --results-directory ./TestResults

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: ./TestResults
```

Enable lock files with `<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>` in `Directory.Build.props` so caching and `--locked-mode` work.

### OIDC Authentication to AWS

One-time AWS setup: add the IAM OIDC identity provider `token.actions.githubusercontent.com` (audience `sts.amazonaws.com`), then create a role with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:ref:refs/heads/master"
        }
      }
    }
  ]
}
```

A job that uses `environment: production` presents the subject `repo:<org>/<repo>:environment:production` instead of the branch ref — give the deploy role a trust policy with that subject.

```yaml
# In any job that talks to AWS
permissions:
  id-token: write   # required to request the OIDC token
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::<account-id>:role/github-ci
      aws-region: us-east-1
```

### Class Library: Pack and Push to AWS CodeArtifact

```yaml
# .github/workflows/release.yml — runs on version tags
name: release

on:
  push:
    tags: ['v*']

permissions:
  id-token: write
  contents: read

jobs:
  pack-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x

      - run: dotnet test -c Release
      - run: dotnet pack src/MyLibrary -c Release -o ./nupkg -p:Version=${GITHUB_REF_NAME#v}

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-codeartifact-publish
          aws-region: us-east-1

      # Registers the "<domain>/<repository>" NuGet source with a 12-hour token
      - run: >
          aws codeartifact login --tool dotnet
          --domain <domain> --domain-owner <account-id> --repository <repository>

      - run: dotnet nuget push ./nupkg/*.nupkg --source <domain>/<repository> --skip-duplicate
```

The publish role needs `codeartifact:GetAuthorizationToken`, `codeartifact:GetRepositoryEndpoint`, `codeartifact:PublishPackageVersion`, and `sts:GetServiceBearerToken` — nothing more. Public packages go to nuget.org with a `NUGET_API_KEY` secret instead.

### Web API: Image to Amazon ECR

```yaml
# Job in .github/workflows/deploy.yml (on push to master, after CI passes)
  build-image:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    outputs:
      image: ${{ steps.image.outputs.image }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-ecr-push
          aws-region: us-east-1

      - id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      # SDK container publishing — no Dockerfile needed. Tag with the commit SHA.
      - run: >
          dotnet publish src/MyApp.Api -c Release /t:PublishContainer
          -p:ContainerRegistry=${{ steps.ecr.outputs.registry }}
          -p:ContainerRepository=myapp-api
          -p:ContainerImageTag=${{ github.sha }}

      - id: image
        run: echo "image=${{ steps.ecr.outputs.registry }}/myapp-api:${{ github.sha }}" >> "$GITHUB_OUTPUT"
```

Turn on ECR image scanning and set the repository to **immutable tags** so a SHA tag can never be overwritten.

### Deploy to Amazon ECS Fargate (Staging → Production)

```yaml
  deploy-staging:
    needs: build-image
    permissions:          # a reusable workflow can't get more than the caller grants
      id-token: write
      contents: read
    uses: ./.github/workflows/ecs-deploy.yml
    with:
      environment: staging
      image: ${{ needs.build-image.outputs.image }}

  deploy-production:
    needs: [build-image, deploy-staging]
    permissions:
      id-token: write
      contents: read
    uses: ./.github/workflows/ecs-deploy.yml
    with:
      environment: production   # protected environment: required reviewers approve first
      image: ${{ needs.build-image.outputs.image }}
```

```yaml
# .github/workflows/ecs-deploy.yml — reusable deploy job
name: ecs-deploy

on:
  workflow_call:
    inputs:
      environment: { type: string, required: true }
      image: { type: string, required: true }

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}   # per-environment variable
          aws-region: us-east-1

      - id: taskdef
        uses: aws-actions/amazon-ecs-render-task-definition@v1
        with:
          task-definition: deploy/taskdef.${{ inputs.environment }}.json
          container-name: myapp-api
          image: ${{ inputs.image }}

      - uses: aws-actions/amazon-ecs-deploy-task-definition@v2
        with:
          task-definition: ${{ steps.taskdef.outputs.task-definition }}
          cluster: myapp-${{ inputs.environment }}
          service: myapp-api
          wait-for-service-stability: true
```

The task definition's **task role** grants the app access to Secrets Manager / Parameter Store paths at runtime; the **execution role** pulls the image from ECR. The GitHub deploy role only needs `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, and `iam:PassRole` on those two roles.

## Anti-patterns

### Don't Store AWS Access Keys in GitHub Secrets

```yaml
# BAD — long-lived keys that leak, never rotate, and grant standing access
- uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

# GOOD — short-lived credentials through OIDC
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::<account-id>:role/github-ci
    aws-region: us-east-1
```

### Don't Deploy `latest`

```yaml
# BAD — mutable tag: you can't tell what is running or roll back reliably
-p:ContainerImageTag=latest

# GOOD — immutable commit SHA tag; rollback = redeploy an earlier SHA
-p:ContainerImageTag=${{ github.sha }}
```

### Don't Rebuild Per Environment

```yaml
# BAD — staging and production run different binaries
deploy-production:
  steps:
    - run: dotnet publish ... /t:PublishContainer   # second build

# GOOD — production deploys the image output from the single build-image job
deploy-production:
  needs: [build-image, deploy-staging]
  with:
    image: ${{ needs.build-image.outputs.image }}
```

### Don't Use One Admin Role for Everything

```
BAD:  one "github-actions" role with AdministratorAccess, trusted for repo:<org>/*
GOOD: github-ci (read-only / test), github-ecr-push, github-codeartifact-publish,
      and per-environment deploy roles trusted only for
      repo:<org>/<repo>:environment:<name>
```

## Decision Guide

| Scenario                          | Recommendation                                                   |
| --------------------------------- | ---------------------------------------------------------------- |
| CI platform                       | GitHub Actions                                                   |
| Authenticating to AWS             | OIDC + `aws-actions/configure-aws-credentials` with an IAM role  |
| Private NuGet packages            | AWS CodeArtifact (`aws codeartifact login --tool dotnet`)        |
| Public NuGet packages             | nuget.org with an API key secret                                 |
| Container registry                | Amazon ECR, immutable tags, scan on push                         |
| Building images                   | `dotnet publish /t:PublishContainer` (or a Dockerfile)           |
| Running a web API                 | Amazon ECS on Fargate                                            |
| Production approvals              | GitHub protected environments with required reviewers           |
| App secrets                       | Secrets Manager / Parameter Store at runtime (task role)         |
| Rollback                          | Redeploy a previous commit-SHA image                             |
