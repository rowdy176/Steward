# Introduction

You've probably written code like this:

```
Match
├── Team A
│   ├── Player
│   │   ├── Character
│   │   ├── Connections
│   │   ├── UI
│   │   └── Threads
│   └── ...
└── ...
```

Now ask yourself:

- When the Player leaves, what gets cleaned up?
- When the Team is removed, what gets cleaned up?
- When the Match ends, what gets cleaned up?

Most cleanup libraries don't answer that question.

They answer a different one:
> "How do I clean up this collection of resources?"

Instead, consider a different question:
> "Who owns these resources and is responsible for their lifetime?"

Because once ownership is explicit, cleanup becomes predictable.

# Steward

Steward is a hierarchical lifetime ownership framework.

I want to be clear about that phrase because it's not just yap to sound professional.
Steward quite literally is a hierarchical lifetime ownership framework, that cleans children when the owner is dismissed.
This is not another cleanup library. Cleanup is not the feature. Ownership
is the feature, and it's hierarchical, meaning a Steward can own other
Stewards, not just connections and instances. Cleanup just happens to fall
out of that for free.

## Why the name?

A steward is responsible for managing something on behalf of another. 
In the same way, every Steward is responsible for the lifetime of the resources it owns.
That's pretty much why, since that's basically what my library is, so yeah.

## Table of Contents

- [Why this exists](#why-this-exists)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [How it actually works](#how-it-actually-works)
  - [Ownership, not cleanup](#ownership-not-cleanup)
  - [Nesting](#nesting)
  - [Adoption](#adoption)
  - [Dismissal](#dismissal)
  - [Attaching to an Instance](#attaching-to-an-instance)
- [API Reference](#api-reference)
- [Debugging a Hierarchy](#debugging-a-hierarchy)
- [Good & Bad Practices](#good--bad-practices)
- [Safety Notes](#safety-notes)

## Why this exists

Most Roblox cleanup libraries give you a
bag. You throw connections and instances into the bag, and when the bag
dies, everything in it dies too. That's fine for one object, but it doesn't
really model anything. It's just a flat list.

Your game isn't flat though. A Match has Teams. Teams have Players. Players
have Characters, connections, UI, whatever. That's a tree, whether you
write it down or not. Steward just lets you write it down. You build a
Steward tree that mirrors your actual game state, and when a branch of your
game ends (a player leaves, a round ends, a match ends), you call
`Dismiss()` once on the right node and the whole branch, connections,
instances, child Stewards, all of it, goes down in order.

Sounds simple, because it is.

Plus, you get very simple debugging tools to see the entire Steward tree as you wish to see **WHY** your game is leaking memory.
Isn't that amazing? I think it is!

## Installation

Steward ships as three ModuleScripts, with Types and Debug living under the
main Steward script:

```
Steward (ModuleScript)
├── Types (ModuleScript)
└── Debug (ModuleScript)
```

Drop the folder wherever you keep your modules and require the init:

```luau
const Steward = require(ReplicatedStorage.Packages.Steward.init)
```

You never need or should touch Types or Debug directly. Types just holds type
definitions and Debug is explicitly internal, it even says so in its own
doc comment. Use `Steward:Dump()`, `Steward:Snapshot()`, and
`Steward.Diff()` instead.

## Quick Start

```luau
const Steward = require(ReplicatedStorage.Packages.Steward)

const Match = Steward.new("Match")

const TeamA = Match:Nest("TeamA")
const Player = TeamA:Nest("Player_" .. userId)

Player:AdoptInstance(characterModel)
Player:AdoptConnection(humanoid.Died:Connect(onDeath))
Player:AddCleanup(function()
	print(userId, "left the match")
end)

--// Basically, Match and everything under it is fully removed, disconnected or destroyed
Match:Dismiss()
```

That's it. No separate teardown function to maintain, no forgetting to
disconnect something that you forgot exists

## How it actually works

### Ownership, not cleanup

Every Steward is a node. A node can hold resources (connections, threads,
tweens, instances, arbitrary destroyable or disconnectable objects, plain
functions) and it can hold other Stewards as children. Something is owned
the second it's adopted, and it stays owned by exactly one Steward until
either that Steward dismisses or the resource gets moved elsewhere.

### Nesting

```lua
Parent:Nest(nameOrChild?)
```

This is how you actually build the tree. Pass a name or nothing and you
get a fresh child Steward back. Pass an existing Steward and it gets
reparented under the caller, automatically detached from wherever it was
before.

A couple things it guards against:

- **Cycles.** Nesting a Steward under itself or one of its own descendants
  gets refused with a warning. The tree can't fold in on itself.
- **Nesting into a dead branch.** If the parent is already dismissed, the
  child gets dismissed immediately too. You can't attach fresh state to a
  branch that's already gone.

### Adoption

Adoption is how a resource that isn't a Steward gets pulled into the tree.
There's a specific method per kind, plus a generic `Adopt` that figures out
what you handed it:

| Method | Takes | On dismissal |
|---|---|---|
| `AdoptConnection` | `RBXScriptConnection` | Disconnected |
| `AdoptThread` | `thread` | Cancelled |
| `AdoptTween` | `Tween` | Cancelled, then destroyed |
| `AdoptInstance` | any other `Instance` | Destroyed |
| `AdoptDestroyable` | table with `:Destroy()` | `:Destroy()` called |
| `AdoptDisconnectable` | table with `:Disconnect()` | `:Disconnect()` called |
| `AddCleanup` | plain `function` | called |
| `Nest` | another `Steward` | dismissed as a child |

`Adopt` checks the type of whatever you hand it and routes it to the right
method above. It's convenient for generic code paths where you don't
statically know what you're getting. If you already know, use the specific
method, it's more explicit and skips the type sniffing.

Adopting into a Steward that's already dismissed doesn't get quietly
dropped, it gets torn down right there on the spot, same as if it had been
owned the whole time and the parent just dismissed. Ownership rules hold
even at the edges.

### Dismissal

```lua
Steward:Dismiss()
```

This is where ownership turns into action. Calling it tears things down in
this order:

1. Connections from `AttachTo`
2. Adopted connections
3. Adopted threads
4. Adopted tweens
5. Every child Steward, recursively, running this same order
6. Adopted instances
7. Adopted destroyables
8. Adopted disconnectables
9. Adopted cleanup functions

After that it removes itself from its own parent's child list, so nothing
above it keeps a dangling pointer to a dead node.

`Dismiss()` is idempotent, calling it again does nothing. There's no other
concept of "cleanup" beyond this. You dismiss a node because its part of
the tree is over, and whatever it owned goes with it.

Incase you are wondering how it really looks like in action, here is an example:

```
Root
-> Match
--> TeamA
---> Player_1
----> Character
-----> 1 Connection
-----> 1 Thread
```

Call `Dismiss()` once on TeamA. Let's see what that does:

```
Root
-> Match
```

Dang, see that? TeamA and everything underneath is GONE.

### Attaching to an Instance

```lua
Steward:AttachTo(instance)
```

Sometimes you want a Steward's life tied to something outside the tree
entirely, like a Player object or a spawned Model. `AttachTo` hooks the
Instance's `Destroying` event and calls `Dismiss()` when it fires, so you
don't have to remember to do it by hand.

## API Reference

- **`Steward.new(name: string?) -> Steward`**
Makes a new, unparented Steward. No name given, it gets one auto-generated
so it's still identifiable later in a Dump.
- **`Steward:AdoptConnection(connection) -> RBXScriptConnection`**
- **`Steward:AdoptThread(thread) -> thread`**
- **`Steward:AdoptTween(tween) -> Tween`**
- **`Steward:AdoptInstance(instance) -> Instance`**
- **`Steward:AdoptDestroyable(object) -> object`**
Warns and hands the object back untouched if it has no `Destroy` method.
- **`Steward:AdoptDisconnectable(object) -> object`**
Same deal but for `Disconnect`.
- **`Steward:AddCleanup(fn) -> fn`**
- **`Steward:Adopt(resource) -> resource`**
Auto-detects and routes to whichever method above fits, including nesting
if you hand it a Steward. Warns if it genuinely doesn't recognize the type.
- **`Steward:Nest(nameOrChild: (string | Steward)?) -> Steward`**
Builds or reparents into the tree.
- **`Steward:AttachTo(instance: Instance) -> Steward`**
Ties dismissal to an Instance's `Destroying` event. Returns self so you can
chain it.
- **`Steward:Dismiss() -> ()`**
Tears the node and its whole branch down.
- **`Steward:Snapshot() -> Snapshot`**
- **`Steward:Dump() -> string`**
- **`Steward.Diff(a: Snapshot, b: Snapshot) -> string`**
Covered below.

## Debugging a Hierarchy

Because the tree actually mirrors your game state, it doubles as a
diagnostic tool without any extra setup. `Snapshot()` grabs the shape of a
branch, names and resource counts, recursively, without holding onto the
actual resources. Keeping a snapshot around never keeps anything alive.

```luau
const before = Match:Snapshot()

--// Stuff happens, connections, threads and all that blah blah blah

const after = Match:Snapshot()

print(Steward.Diff(before, after))
```

`Dump()` prints (and returns) a readable indented tree of a branch right
now:

```
Match
->TeamA
--> 2 Connections
--> Player_1
---> 1 Connection
---> 1 Instance
```

`Diff()` only reports what changed between two snapshots, added nodes,
removed nodes, and per-node count deltas. Good for catching a branch that's
quietly piling up connections it was never supposed to keep.

## Good & Bad Practices
Since Steward is pretty new, a Good & Bad Practices section would be nice I thought.

✅ **Good: organize long lived root Stewards.**

If you have Stewards that are expected to live for the lifetime of the
server or client (for example a root Steward or a player root), keeping
them in a shared registry is perfectly reasonable. It gives the rest of
your codebase a well known entry point into the ownership tree.

Avoid putting temporary Stewards into the registry. The ownership tree
itself should describe what currently exists. The registry should only
hold long lived roots into that tree.

✅ **Good: name your Stewards.**

`Dump()` and `Diff()` lean on names to make output readable. Leave
everything unnamed and you'll be staring at a dump full of `Steward#42`
and `Steward#87` trying to guess what is what. Name things after what they represent (`"Match"`,
`"Player_" .. userId`) and future you will thank you.

✅ **Good: build the tree to match your actual game structure.**

The whole point is that one `Dismiss()` call on the right node tears down
a meaningful chunk of state. If you shove everything under one giant root
Steward for the entire server lifetime, you lose the ability to tear down
just a round or just a player, you're back to manually tracking what
belongs to what. On the flip side, don't leave a bunch of `Steward.new()`
calls floating around unnested either, an orphaned Steward with no parent
never gets dismissed unless you remember to dismiss it yourself, which is
exactly the manual bookkeeping this whole thing exists to avoid.

✅ **Good: let `AddCleanup` closures capture their own state.**

The type doc for `CleanupFn` says it straight up, it takes no arguments,
so anything it needs should be captured by the closure. Don't write a
cleanup function that reaches out to some external variable that might
already be nil or already torn down by the time dismissal actually runs.

✅ **Good: use `Snapshot()` and `Diff()` at natural checkpoints.**

Round start, round end, player join, player leave, whatever your game's
natural boundaries are. Snapshotting there and diffing against the last one
is a much faster way to catch a leak than manually auditing counts, and it
costs you basically nothing since snapshots don't hold resources alive.

❌ **Bad: assuming your `AddCleanup` function runs before your children or
your own instances are gone.**

Look at the dismissal order again. Children get dismissed at step 5.
Your own instances, destroyables, disconnectables, and cleanup functions
run after, at steps 6 through 9. If your cleanup function needs a child
Steward's state to still be intact, it won't be. Cleanup functions run
dead last.

❌ **Bad: mistaking a warning for a hard failure.**

`AdoptDestroyable` and `AdoptDisconnectable` don't error if you hand them
something without the right method, they warn and just hand the object
back, unowned. If you don't check your output for warnings, you can end
up thinking something's tracked when it never actually got adopted. Same
thing with `Nest` refusing a cycle, it warns and returns the child
untouched, it doesn't throw. Keep an eye on your warnings, this library
uses them as a real signal, not decoration.

❌ **Bad: calling `AdoptInstance` directly on a Tween.**

Tweens are technically Roblox Instances, which is why `Adopt()` specifically
checks `IsA("Tween")` before deciding which bucket to put it in. If you
bypass that and call `AdoptInstance` on a Tween yourself, it only gets
`:Destroy()` called on it, it never gets `:Cancel()`'d first. Use `Adopt()`
or `AdoptTween()` directly for tweens and let the library make that call.

❌ **Bad: relying on a failed cleanup to bubble up as an error.**

Every single teardown call, connections, instances, destroyables, cleanup
functions, all of it, is wrapped in `pcall`. If one of them throws, you get
a warning in the output and the rest of dismissal just keeps going. That's
a good thing for reliability, one broken resource can't wreck a whole
branch's teardown, but it also means you can't catch a cleanup failure the
normal way. If something in your cleanup absolutely must be verified, do
that check somewhere other than inside the cleanup function itself.

## Safety Notes

- Every teardown call is pcall wrapped. One bad `:Destroy()` won't stop the
  rest of a branch from tearing down.
- `Dismiss()` is idempotent. Call it twice, nothing bad happens.
- The tree can't be corrupted into a cycle, `Nest` checks ancestry first.
- Adopting into an already dismissed Steward tears the resource down right
  away instead of quietly holding onto it.
