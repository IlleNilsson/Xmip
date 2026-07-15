# Xmip Observer Architecture

Status: Frozen architectural baseline

## Purpose

`xmip-observer` produces near-real-time, navigable operational data about traffic and health across the current Xmip Installation.

Its primary purpose is threefold:

1. Understand how the Xmip Installation is structured and how traffic flows through it.
2. Find red conditions so they can be solved and yellow conditions so they can be corrected before becoming red.
3. Identify prolonged inactivity that may justify review or decommissioning.

Observer produces observable data. It does not make Xmip a GUI or dashboard platform.

## Navigable structure

Observer exposes these primary navigable elements:

```text
Xmip Installation
Clusters
Nodes
Parties
Endpoints
```

Endpoints include:

```text
Receive Port
Receive Location
Send Port Group
Send Port
Send Location
```

Processes and Journeys may appear when drilling into traffic and execution, but they are not top-level organizational anchors.

All states remain navigable. Green is the working structure of the Xmip Installation, not merely the absence of failure.

## Traffic information

For a selected recent observation window, Observer produces:

```text
From
To
How many Messages and Journeys
How much Stream data
Rate
Latency
Outcome
```

Large Streams are never copied into Observer. Observer receives identifiers, size, durable references, known content type, timing, source, destination and outcome metadata.

## Health states

```text
Green
    Healthy and active.

Grey
    Healthy and configured, but no traffic is present in the selected observation window.

Yellow
    Degraded, retrying, delayed, approaching a configured threshold or requiring attention.

Red
    Failed, unavailable, blocked or unable to perform a configured responsibility.

Black
    Healthy and configured, but no meaningful activity has occurred for a stakeholder-defined inactivity period.
    The integration path should be reviewed for continued need or decommissioning.
```

The reason and supporting evidence must always accompany the state. A colour name alone is not sufficient.

Grey is a temporary observation state. Black is prolonged inactivity determined by stakeholder-defined thresholds.

For Grey and Black, Observer may expose:

```text
Last Message
Last Journey
Last Event
Last Configuration Change
Inactive Since
Selected Observation Window
Configured Inactivity Threshold
```

## Worst-state propagation

Operational health propagates upward using the worst active health state:

```text
Any Red
    -> Parent is Red
    -> Cluster is Red
    -> Xmip Installation is Red

Any Yellow and no Red
    -> Parent is Yellow
    -> Cluster is Yellow
    -> Xmip Installation is Yellow
```

Green, Grey and Black remain independently navigable and reportable. They describe activity and lifecycle conditions rather than hiding structure.

A successful delivery does not hide an unhealthy configured path.

Example:

```text
Send Port delivery: Succeeded
Send Location 1: Failed
Send Location 2: Succeeded

Operational health: Red
```

Send Locations are an ordered list of attempts, not primary and secondary destinations. The first Send Location that succeeds completes the Send Port, while earlier failures remain visible and keep operational health red until corrected.

## Navigation

Every state supports drill-down from broad scope to supporting evidence:

```text
Xmip Installation
    -> Cluster
    -> Node
    -> Party or Endpoint
    -> Journey
    -> Message and Stream metadata
```

Selecting an element may expose:

```text
State
Reason
Affected traffic
Started at
Duration
Current impact
Related Journeys
Related Events
Suggested operational action
Responsible Module or Endpoint
```

Green navigation explains how the installation is structured and working.
Grey navigation explains healthy inactivity in the selected window.
Yellow navigation identifies degradation.
Red navigation identifies failures requiring timely action.
Black navigation identifies prolonged inactivity and possible technical debt.

## Near-real-time, not real-time

Observer is deliberately near real-time rather than synchronous real-time.

Core Receive, Process and Send execution must not wait for Observer. Observer consumes lightweight operational measurements, snapshots and persisted outcomes asynchronously.

Observation windows and refresh intervals are configurable. They may be expressed in milliseconds or seconds according to stakeholder needs, but Xmip does not promise zero-delay observation.

The execution priority is:

```text
1. Receive
2. Process
3. Send
4. Required durable persistence
5. Observation
6. Reporting
```

Observation and Reporting must not materially reduce integration throughput or increase execution latency.

If Observer or Reporting is unavailable, core integration execution continues. Missing observation data is itself reportable when service resumes.

## Time windows and filters

Near-real-time views may include:

```text
Current recent window
Last minute
Last 5 minutes
Last 15 minutes
Last hour
Custom recent window
```

Filters may include:

```text
Party
Cluster
Node
Endpoint
Process
Contract
Message type
Journey state
Outcome
Transfer, Light or Context handling
Health state
```

## Observer and Reporting

```text
Observer
    Produces near-real-time observable traffic and health data.

Reporting
    Aggregates, correlates and transforms observable and historical information into reportable data.

External consumers
    Present reportable data as reports, graphs, alerts or other views.
```

Xmip defines and produces the health state and supporting evidence. Consumers decide how to present it.

## Frozen principles

> Xmip Observer produces navigable near-real-time traffic and health data for the Xmip Installation, Clusters, Nodes, Parties and Endpoints.

> Find the red so it can be solved. Find the yellow so it can be corrected before it becomes red.

> Green explains how the Xmip Installation is structured and how it works. Grey shows healthy inactivity in the selected window. Black shows prolonged inactivity that may warrant review or decommissioning.

> Xmip Observer reports the worst active health state upward. Successful delivery never hides a failing configured path.

> Observation and Reporting are asynchronous consumers of operational data and must never materially affect Message throughput or execution latency.