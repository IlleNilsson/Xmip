# Xmip Observer Architecture

Status: Frozen architectural baseline

## Purpose

`xmip-observer` provides a near-real-time, navigable view of traffic and health across the current Xmip Installation.

Its primary purpose is twofold:

1. Understand how the Xmip Installation is structured and how traffic flows through it.
2. Find red conditions so they can be solved and yellow conditions so they can be corrected before becoming red.

## Navigable graph

The graph presents these primary navigable elements:

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

Processes and Journeys may appear when drilling into traffic and execution, but they are not top-level organizational anchors of the graph.

The graph must remain navigable for all health states. Green is not merely the absence of failure; it is the working structure of the Xmip Installation.

## Traffic information

The graph shows, for the selected recent time window:

```text
From
To
How many Messages and Journeys
How much Stream data
Current rate
Latency
Outcome
```

Large Streams are never copied into Observer. Observer receives identifiers, size, references, known content type, timing, source, destination and outcome metadata.

## Health states

```text
Green
    Healthy and operating as configured.

Yellow
    Degraded, retrying, delayed, approaching a configured threshold or requiring attention.

Red
    Failed, unavailable, blocked or unable to perform a configured responsibility.

Grey
    Disabled, inactive, unknown or not currently observed.
```

The reason must always accompany the colour. Colour alone is not sufficient.

## Worst-state propagation

Operational health propagates upward using the worst active state:

```text
Any Red
    -> Parent is Red
    -> Cluster is Red
    -> Xmip Installation is Red

Any Yellow and no Red
    -> Parent is Yellow
    -> Cluster is Yellow
    -> Xmip Installation is Yellow

All observed elements Green
    -> Parent is Green
```

A successful delivery does not hide an unhealthy configured path.

Example:

```text
Send Port delivery: Succeeded
Send Location 1: Failed
Send Location 2: Succeeded

Operational health: Red
```

Send Locations are an ordered list of attempts, not primary and secondary destinations. The first Send Location that succeeds completes the Send Port, while earlier failures remain visible and keep operational health red until corrected.

## Green navigation

Green elements support the same drill-down as yellow and red. Navigating green lets Operations understand:

- the structure of the Xmip Installation;
- which Parties communicate through which Endpoints;
- which Clusters and Nodes carry traffic;
- where Messages come from and go to;
- how many Messages and Journeys are moving;
- how much Stream data is moving;
- which configured paths are healthy;
- which healthy elements are currently idle.

## Drill-down

The graph supports navigation from broad scope to exact cause:

```text
Xmip Installation
    -> Cluster
    -> Node
    -> Endpoint
    -> Journey
    -> Message and Stream metadata
```

Selecting a red or yellow element exposes:

```text
Cause
Affected traffic
Started at
Duration
Current impact
Related Journeys
Related Events
Suggested troubleshooting action
Responsible Module or Endpoint
```

Selecting a green element exposes the same structure and traffic information without requiring an exception.

## Time windows and filters

Near-real-time views may include:

```text
Now
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
```

## Observer and Reporter

```text
Observer
    Navigable near-real-time traffic and current operational health.

Reporter
    Persisted design, operational and troubleshooting reports.
```

Observer may hand a selected view to Reporter for export or historical analysis.

## Frozen principles

> Xmip Observer presents the Xmip Installation, Clusters, Nodes, Parties and Endpoints as a navigable near-real-time traffic and health graph.

> Find the red so it can be solved. Find the yellow so it can be corrected before it becomes red.

> Green explains how the Xmip Installation is structured and how it works.

> Xmip Observer reports the worst active health state upward. Successful delivery never hides a failing configured path.
