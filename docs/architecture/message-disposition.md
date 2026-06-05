# Xmip Message Disposition

Xmip Receive accepts or rejects a received stream.

Reject means Xmip does not take ownership and no Xmip Message is created. The rejection is audited.

Accept means Xmip takes ownership and creates a Xmip Message.

An accepted Xmip Message must match one or more Subscription Definitions.

If no Subscription Definition matches, the Xmip Message is placed in the Xmip DMQ.

The Xmip DMQ is the final disposition for accepted Xmip Messages that cannot be routed by Subscription Definitions.

The Xmip DMQ preserves the Xmip Message with available metadata, including receive context, validation results, correlation references, trace references, audit references, failure reason, timestamps, artifact identities, and subscription evaluation metadata.

An accepted Xmip Message shall never disappear.

After Accept, Xmip owns the Xmip Message until final disposition.
