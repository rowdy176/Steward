--!strict

--[=[
	@class Types
	
	Shared type definitions for Steward.
]=]

--========== Export Types ==========--
--[=[
	A plain callback registered via Steward:AddCleanup(). Takes no
	arguments and returns nothing. Anything it needs should be captured
	by the closure itself
	
	@type CleanupFn () -> ()
	@within Types
]=]
export type CleanupFn = () -> ()

--[=[
	Any class (Roblox Instance excluded, those go through AdoptInstance)
	that owns its own teardown via a Destroy method
	
	@type Destroyable {Destroy: (self: Destroyable) -> ()}
	@within Types
]=]
export type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

--[=[
	Same idea as Destroyable, for classes that expose Disconnect instead
	
	@type Disconnectable {Disconnect: (self: Disconnectable) -> ()}
	@within Types
]=]
export type Disconnectable = {
	Disconnect: (self: Disconnectable) -> (),
}

--[=[
	Absolute resource counts for a single Steward node, used by both
	Dump() and Diff() (as a delta between two of these)
	
	@type ResourceCounts {
		Connections: number,
		Threads: number,
		Tweens: number,
		Instances: number,
		Destroyables: number,
		Disconnectables: number,
		Functions: number,
	}
	@within Types
]=]
export type ResourceCounts = {
	Connections: number,
	Threads: number,
	Tweens: number,
	Instances: number,
	Destroyables: number,
	Disconnectables: number,
	Functions: number,
}

--[=[
	One node in a Snapshot tree. Mirrors the live Steward hierarchy at the
	moment the snapshot was taken, but holds only counts and identity,
	never the actual resources, so a Snapshot can be kept around for
	comparison without holding anything alive or leaking internals.
	
	@type SnapshotNode {
		Id: number,
		Name: string,
		Counts: ResourceCounts,
		Children: {SnapshotNode},
	}
	@within Types
]=]
export type SnapshotNode = {
	Id: number,
	Name: string,
	Counts: ResourceCounts,
	Children: {SnapshotNode},
}

--[=[
	A snapshot of the Steward hierarchy at a given moment in time.
	
	@type Snapshot {
		Root: SnapshotNode,
		TakenAt: number,
	}
	@within Types
]=]
export type Snapshot = {
	Root: SnapshotNode,
	TakenAt: number,
}

--========== Return ==========--
return {}