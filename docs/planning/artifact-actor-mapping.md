# Artifact Actor Mapping

Xmip artifact semantics remain explicit. Actor semantics are additive.

```text
Receive Location -> Actor reporting to Receive Port
Receive Port     -> Actor owning received message until ownership transfer
Process          -> Actor that may orchestrate, assign, transform, publish or subscribe
Send Port Group  -> Actor grouping related send ports
Send Port        -> Actor owning send-side preparation and delivery decisions
Send Location    -> Actor performing actual target delivery
Handler          -> Actor when executing or reporting capabilities
Node             -> Actor inside Cluster
Cluster          -> Actor inside a larger domain
```

## Rule

Do not rename Xmip artifact concepts away.

Use Actor semantics to explain communication, publication, subscription, ownership, reporting, and responsibility transfer.
