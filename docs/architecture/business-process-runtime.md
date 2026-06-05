# Xmip Business Process Runtime

A BusinessProcess supports the organization's workflow and exceptions.

A Process Definition defines what organizational workflow work should be performed.

A Process Instance is the runtime execution of a Process Definition.

A Process Instance is normally started because a Subscription Definition matched an accepted Xmip Message and created a Subscription Instance.

Xmip uses ExecutionScope to describe execution semantics:

- None
- Transactional
- BusinessProcess

ExecutionScope = BusinessProcess means runtime state may be persisted and resumed.

A BusinessProcess may use other Xmip Artifacts to gather or send information.

A BusinessProcess may publish Xmip Messages.

A BusinessProcess may wait for responses to previous requests, future messages, timers, or decisions.

A waiting BusinessProcess Instance is not a long-running thread.

A waiting BusinessProcess Instance is persisted runtime truth that may later be resumed.

Persisted runtime truth may include process identity, current execution state, wait conditions, correlation rules, outstanding requests, expected responses, message references, timeout information, audit references, correlation references, and recovery metadata.

A future accepted Xmip Message may be published into Xmip.

A Subscription Instance may correlate the message to a waiting BusinessProcess Instance.

If the correlation and wait condition match, Xmip may resume the BusinessProcess Instance from persisted runtime truth.

Compiled code provides behavior.

Configuration defines startup intent and binding.

The database stores runtime truth.
