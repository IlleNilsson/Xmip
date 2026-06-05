# Xmip Business Process Runtime

A BusinessProcess supports the organization's workflow and exceptions.

A Process Definition defines what organizational workflow work should be performed.

A Process Instance is the runtime execution of a Process Definition.

A Process Instance is normally started because a Subscription Definition matched an accepted Xmip Message and created a Subscription Instance.

Xmip uses ExecutionScope to describe execution semantics:

- None
- Transactional
- BusinessProcess

ExecutionScope applies regardless of whether the execution happens in a process or in a publish/subscribe situation.

Audit is always available.

Failures are always audited and failure audit records are always persisted.

Tracing and Tracking are configurable per host, contract, and artifact.

A BusinessProcess may use other Xmip Artifacts to gather or send information.

A BusinessProcess may publish Xmip Messages.

A BusinessProcess may wait for responses to previous requests, future messages, timers, or decisions.

A waiting BusinessProcess Instance is not a long-running thread.

A waiting BusinessProcess Instance is persisted runtime truth that may later be resumed.

Persisted runtime truth may include process identity, current execution state, wait conditions, correlation rules, outstanding requests, expected responses, message references, timeout information, audit references, correlation references, and recovery metadata.

A future accepted Xmip Message may be published into Xmip.

A Subscription Instance may correlate the message to a waiting BusinessProcess Instance.

If the correlation and wait condition match, Xmip may resume the BusinessProcess Instance from persisted runtime truth.

A Subscription decides when work starts.

A Correlation Rule decides when waiting work resumes.

When an ExecutionScope ends, Xmip must produce an explicit output or outcome.

The output or outcome may be a published Xmip Message, a sent Xmip Message, completed work, a failure, or placement into the Xmip DMQ.

The end of an ExecutionScope is always auditable.

Compiled code provides behavior.

Configuration defines startup intent and binding.

The database stores runtime truth.
