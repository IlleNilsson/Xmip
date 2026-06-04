# Xmip Service Identities

## Purpose

Xmip needs a platform-neutral concept for non-human runtime identities.

Windows Managed Service Accounts and group Managed Service Accounts are useful models, but Xmip must also run across Linux, containers, Kubernetes, cloud platforms, edge devices, and other deployment targets.

The Xmip architecture therefore uses the term Service Identity.

## Service Identity

A Service Identity is a non-human identity used by Xmip runtime components, modules, Artifact Instances, services, jobs, or deployment agents.

A Service Identity answers:

```text
What identity is this Xmip runtime component running as?
```

and:

```text
What is this runtime component allowed to access?
```

## Platform-native realization

Xmip should not force one operating-system account model across all platforms.

Each platform should realize Service Identity using its native administration model.

Examples:

### Windows

- Managed Service Account,
- group Managed Service Account,
- domain service account,
- local service account.

### Linux

- dedicated service user,
- systemd service user,
- LDAP-backed service identity,
- Kerberos principal where appropriate.

### Containers and Kubernetes

- container runtime identity,
- Kubernetes service account,
- workload identity,
- mounted identity token where appropriate.

### Cloud platforms

- managed identity,
- service principal,
- IAM role,
- workload identity.

### Edge and embedded deployments

- local service identity,
- device-bound identity,
- provisioned workload identity,
- platform-specific secure identity where available.

## Administration requirement

Service Identity must be easy to administer on each supported platform.

Xmip should prefer the platform-native identity mechanism rather than inventing a parallel identity system.

The operator or administrator should be able to understand, assign, rotate, revoke, and audit the identity using familiar platform tools where possible.

## Desired properties

Service Identity should support:

- non-human runtime execution,
- least privilege,
- explicit permissions,
- credential rotation where the platform supports it,
- revocation,
- auditability,
- clear ownership,
- deployment-scoped access,
- compatibility with Xmip runtime roles,
- compatibility with isolation and trust boundaries.

## Relationship to runtime roles

Runtime roles describe what a runtime component may do.

Service Identity describes who or what the runtime component runs as.

They are different axes.

Example:

```text
Runtime role: Executor
Service Identity: xmip-edge-executor
Isolation boundary: edge device process boundary
```

Another example:

```text
Runtime role: Reader
Service Identity: xmip-monitor-reader
Isolation boundary: monitoring service boundary
```

## Relationship to human roles

Service Identity is separate from human/user roles.

Human roles include:

- Monitorer,
- Operator,
- Developer,
- Administrator,
- Architect.

A human Administrator may assign or manage Service Identities.

A runtime component uses a Service Identity to operate without being tied to a human user account.

## Rule

Do not model Windows MSA or gMSA directly as the universal Xmip abstraction.

Model Xmip Service Identity.

Then realize that Service Identity through the appropriate platform-native identity mechanism.
