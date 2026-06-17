# Must remember

When the user asks `what is next`, use this list as the default source.

## Critical missing work

1. Actual sub-repositories
   - Planned only, not real GitHub repos/submodules yet.
   - `.gitmodules.planned` exists, but target repositories must be created before real submodules can be activated.

2. Module loading
   - No real ModuleLoader yet.
   - No dynamic handler loading yet.
   - No HandlerRegistry implementation yet.

3. Distributed runtime
   - No real node/cluster coordination yet.
   - No inter-node protocol implementation yet.
   - No cluster ownership or failover execution yet.

4. Persistence completeness
   - RocksDB and SQLite started.
   - Replay model not implemented end-to-end.
   - Interchange history not fully queryable or replayable yet.

5. Configuration model
   - TOML config exists in concept and scripts.
   - No full typed config loader and validator yet.

6. Process runtime
   - Process and HumanProcess concepts discussed.
   - No full long-running process or correlation runtime yet.

7. Management plane
   - SQLite management store skeleton exists.
   - No management API, CLI, or UX yet.

8. Security model
   - Handler security mentioned.
   - No full identity, authentication, or authorization implementation yet.

9. Installer and package manager
   - Local scripts exist.
   - No real package manager packages yet.

## Partially done

- Stream-first runtime direction.
- Subscription to Process or SendPort.
- SendPort and SendLocation rules.
- Handler terminology cleanup.
- RocksDB runtime store start.
- SQLite management store start.
- DSC and Ansible skeleton.
- Repository and submodule plan.
- Rust runtime guidelines.
- Xmip defined as distributed platform system.

## Biggest architectural gap

Xmip is now documented as a distributed integration platform system, but the code still behaves like an early single-node prototype.

## Next default build target

`xmip-runtime`:

- ModuleLoader,
- HandlerRegistry,
- typed TOML node configuration,
- cluster and node identity model,
- runtime persistence and replay contract.
