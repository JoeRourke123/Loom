# ADR-025: Concurrency via batch primitives, not deferred promises

Date: 2026-08-17
Status: accepted

## Context

Every `Loom.*` async method is serial, and not by accident. `LoomBridge.makePromise` (and the
identical copies in `NetworkBridge`, `AIBridge`, `DatabaseBridge`) fires its executor, blocks the
script thread on a `DispatchSemaphore`, and then returns an **already-settled** promise built by
`__loomResolve` / `__loomReject`:

```swift
let sema = DispatchSemaphore(value: 0)
executor({ val in resolvedVal = val; sema.signal() },
         { msg in rejectMsg = msg; sema.signal() })
sema.wait()
return ctx.objectForKeyedSubscript("__loomResolve")?.call(withArguments: [v])
```

The consequence is not "parallelism is slow", it is that **parallelism is unreachable from JS**:

```js
const [a, b] = await Promise.all([Loom.network.fetch(x), Loom.network.fetch(y)]);
```

`fetch(x)` runs to completion before `fetch(y)` is even constructed, and `Promise.all` then
receives two finished promises. The docs have said "bridge calls don't run concurrently" for a
while; this ADR records why that is structural and what we did instead.

Measured on a real workload (the Daily Poem project, which writes a seven-section researched
article per day, against `gpt-oss:120b` on ollama.com):

| | sequential | concurrent |
|---|---|---|
| 7 section-writing completions | 67s | 20.0s |
| 6 web searches | 5.6s | ~1.5s |
| 7 Wikipedia image lookups | 3.8s (14 requests) | 0.19s (1 batched request) |

The provider genuinely serves concurrent requests — 7 simultaneous completions all returned 200
with full bodies. So the ceiling is ours, not theirs, and it costs roughly **70s → 28s** on a
workload a user waits on.

## Decision

Add two batch primitives that fan out internally and block **once**:

```ts
Loom.network.fetchAll(requests: {url, method?, headers?, body?}[]): Promise<Response[]>
Loom.ai.completeAll(prompts: string[], opts?): Promise<{text: string, error: string}[]>
```

Both keep the existing blocking `makePromise` exactly as it is. One `sema.wait()` covers the whole
batch; the concurrency lives in a `DispatchGroup` (network) and a throttled `TaskGroup` (AI), both
of which already run off the script thread.

Results are **positional and never partial-throw**. A failed element carries its own error rather
than rejecting the batch, because the interesting failure mode is "five of seven succeeded" and a
rejecting batch would throw that work away.

## Why not real deferred promises

The obvious "correct" fix is to return a genuinely pending promise, resolve it from the script
thread via `CFRunLoopPerformBlock`, and have `ScriptRunner` spin `CFRunLoopRun()` until the result
sentinel is set. `ScriptRunner` already builds a `CFRunLoop` and hands it to `LoomBridge`, so the
skeleton exists. It was rejected for now, on four counts:

1. **It changes the execution model for every existing script**, not just the ones that opt in.
   Anything relying on incidental serialisation of side effects can reorder.
2. **`ScriptRunner` does not currently run that run loop.** Completion is detected by
   `evaluateScript(";")` plus `Thread.sleep(0.005)`, five times over (`ScriptRunner.swift:106-112`).
   A pending promise would never settle, so this is a rewrite of run completion, not an addition.
3. **The no-timeout guard (ADR-002) stops being safe.** A semaphore that never signals blocks one
   call; a run loop waiting on a promise that never settles hangs the run with no way out.
4. **`Loom.ui.web`'s serve loop assumes serial delivery** (ADR-014 — a JS `while(true)` pulling one
   request at a time precisely because JSC only drains microtasks when the outermost entry
   unwinds). Interleaved resolution needs that reasoning redone.

The batch primitives get the measured win with none of that. If a future workload needs genuine
`Promise.all` semantics across *different* namespaces — a fetch and a DB read overlapping — that is
when the deferred-promise model earns its risk, and it should get its own ADR.

## Consequences

- Two ways to make an HTTP request. `fetchAll` is documented as "use when you have N independent
  requests"; `fetch` stays the default for one.
- Parallelism is **opt-in per call site**. A script written with `fetch` in a loop gets no faster
  on its own, which is the honest trade for zero risk to existing projects.
- `fetchAll` results carry an `error` field that `fetch` results do not.
- In-flight work is capped (8 concurrent, 64 per batch) so a script cannot fan out unboundedly
  against a provider or the device's socket budget.
- Batch calls are **one unit of work for resumability purposes**. A caller that persists progress
  between steps now persists in coarser increments, and should record per-element success so a
  retry re-runs only the failures.
