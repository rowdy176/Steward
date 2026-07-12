--!strict

--[=[
	@class Steward
	
	A hierarchical lifetime-ownership framework.
	
	Connections, threads, tweens, Instances, and arbitrary classes with a
	Destroy/Disconnect method are adopted by a Steward, which owns them
	until it is dismissed. Stewards can nest inside each other, so an
	entire branch of ownership, a Match owning Teams owning Players
	owning Characters, comes down with a single Dismiss() call at the
	root of that branch.
]=]

--========== Constants ==========--
const Ownership: {[any]: {Owner: Steward, Kind: string}} = setmetatable({}, {__mode = "k"}) :: any

--========== Dependencies ==========--
const Types = require(script.Types)
const Debug = require(script.Debug)

--========== Primary Types ==========--
type CleanupFn      = Types.CleanupFn
type Destroyable    = Types.Destroyable
type Disconnectable = Types.Disconnectable
type ResourceCounts = Types.ResourceCounts
type SnapshotNode   = Types.SnapshotNode
type Snapshot       = Types.Snapshot

--========== Module ==========--
const Steward = {}
Steward.__index = Steward

--========== Export Types ==========--
export type Steward = {
	Name: string,
	Dismissed: boolean,
	_id: number,
	_parent: Steward?,
	_children: {Steward},
	_connections: {RBXScriptConnection},
	_threads: {thread},
	_tweens: {Tween},
	_instances: {Instance},
	_destroyables: {Destroyable},
	_disconnectables: {Disconnectable},
	_functions: {CleanupFn},
	_attachConnections: {RBXScriptConnection},
	
	AdoptConnection: (self: Steward, Connection: RBXScriptConnection) -> RBXScriptConnection,
	AdoptThread: (self: Steward, Thread: thread) -> thread,
	AdoptTween: (self: Steward, Tween: Tween) -> Tween,
	AdoptInstance: (self: Steward, Instance: Instance) -> Instance,
	AdoptDestroyable: (self: Steward, Object: any) -> any,
	AdoptDisconnectable: (self: Steward, Object: any) -> any,
	AddCleanup: (self: Steward, fn: CleanupFn) -> CleanupFn,
	Adopt: (self: Steward, Resource: any) -> any,
	Nest: (self: Steward, NameOrChild: (string | Steward)?) -> Steward,
	AttachTo: (self: Steward, Instance: Instance) -> Steward,
	Dismiss: (self: Steward) -> (),
	Snapshot: (self: Steward) -> Snapshot,
	Dump: (self: Steward) -> string,
	Diff: (a: Snapshot, b: Snapshot) -> string,
	_snapshotNode: (self: Steward) -> SnapshotNode,
}

--========== Helpers ==========--

--[=[
@private
@function ClaimOwnership
@within Steward
]=]
const function ClaimOwnership(self: Steward, Resource: any, Kind: string, List: {any}): ()
	const Existing = Ownership[Resource]
	
	if Existing ~= nil then
		const PrevList = (Existing.Owner :: any)[Existing.Kind]
		for i = 1, #PrevList do
			if PrevList[i] == Resource then
				table.remove(PrevList, i)
				break
			end
		end
	end
	
	Ownership[Resource] = {Owner = self, Kind = Kind}
	table.insert(List, Resource)
end

--[=[
@private
@function SafeDisconnect
@within Steward
]=]
const function SafeDisconnect(Connection: RBXScriptConnection): ()
	const ok, err = pcall(function()
		Connection:Disconnect()
	end)
	
	if not ok then
		warn("[Steward] connection cleanup failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeCancelThread
@within Steward
]=]
const function SafeCancelThread(Thread: thread): ()
	const ok, err = pcall(function()
		task.cancel(Thread)
	end)
	
	if not ok then
		warn("[Steward] thread cancellation failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeCancelTween
@within Steward
]=]
const function SafeCancelTween(Tween: Tween): ()
	const ok, err = pcall(function()
		Tween:Cancel()
		Tween:Destroy()
	end)
	
	if not ok then
		warn("[Steward] tween cleanup failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeDestroyInstance
@within Steward
]=]
const function SafeDestroyInstance(Instance: Instance): ()
	const ok, err = pcall(function()
		Instance:Destroy()
	end)
	
	if not ok then
		warn("[Steward] instance cleanup failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeDestroy
@within Steward
]=]
const function SafeDestroy(Object: Destroyable): ()
	const ok, err = pcall(function()
		Object:Destroy()
	end)
	
	if not ok then
		warn("[Steward] destroyable cleanup failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeDisconnectObject
@within Steward
]=]
const function SafeDisconnectObject(Object: Disconnectable): ()
	const ok, err = pcall(function()
		Object:Disconnect()
	end)
	
	if not ok then
		warn("[Steward] disconnectable cleanup failed: " .. tostring(err))
	end
end

--[=[
@private
@function SafeCallCleanup
@within Steward
]=]
const function SafeCallCleanup(fn: CleanupFn): ()
	const ok, err = pcall(function()
		fn()
	end)
	
	if not ok then
		warn("[Steward] cleanup function failed: " .. tostring(err))
	end
end

--[=[
@private
@function IsAncestorOf
@within Steward
]=]
const function IsAncestorOf(Candidate: Steward, Node: Steward): boolean
	local Current: Steward? = Node._parent
	
	while Current ~= nil do
		if Current == Candidate then
			return true
		end
		Current = Current._parent
	end
	
	return false
end

--========== Constructor ==========--
local nextId: number = 1

--[=[
@within Steward

Constructs a new Steward object. If a name is not provided, it will be replaced by an ID.

@param name string? -- Optional name for the Steward object
@return Steward
]=]
function Steward.new(name: string?): Steward
	const id: number = nextId
	nextId += 1
	
	const self = setmetatable({
		Name = name or ("Steward#" .. tostring(id)),
		Dismissed = false,
		_id = id,
		_parent = nil,
		_children = {},
		_connections = {},
		_threads = {},
		_tweens = {},
		_instances = {},
		_destroyables = {},
		_disconnectables = {},
		_functions = {},
		_attachConnections = {},
	}, Steward) :: any
	
	return (self :: any) :: Steward
end

--========== Public API ==========--

--[=[
@within Steward
@method AdoptConnection

Adopts a connection to a Steward object.

@param Connection RBXScriptConnection -- Connection to adopt
@return RBXScriptConnection
]=]
function Steward.AdoptConnection(self: Steward, Connection: RBXScriptConnection): RBXScriptConnection
	if self.Dismissed then
		SafeDisconnect(Connection)
		return Connection
	end
	
	ClaimOwnership(self, Connection, "_connections", self._connections)
	
	return Connection
end

--[=[
@within Steward
@method AdoptThread

Adopts a thread to a Steward object.

@param Thread thread -- Thread to adopt
@return thread
]=]
function Steward.AdoptThread(self: Steward, Thread: thread): thread
	if self.Dismissed then
		SafeCancelThread(Thread)
		return Thread
	end
	
	ClaimOwnership(self, Thread, "_threads", self._threads)
	
	return Thread
end

--[=[
@within Steward
@method AdoptTween

Adopts a tween to a Steward object.

@param Tween Tween -- Tween to adopt
@return Tween
]=]
function Steward.AdoptTween(self: Steward, Tween: Tween): Tween
	if self.Dismissed then
		SafeCancelTween(Tween)
		return Tween
	end
	
	ClaimOwnership(self, Tween, "_tweens", self._tweens)
	
	return Tween
end

--[=[
@within Steward
@method AdoptInstance

Adopts an instance to a Steward object

@param instance Instance
@return Instance
]=]
function Steward.AdoptInstance(self: Steward, instance: Instance): Instance
	if self.Dismissed then
		SafeDestroyInstance(instance)
		return instance
	end
	
	ClaimOwnership(self, instance, "_instances", self._instances)
	
	return instance
end

--[=[
@within Steward
@method AdoptDestroyable

Adopts a destroyable object to a Steward object

@param Object T -- Object to adopt
@return T
]=]
function Steward.AdoptDestroyable<T>(self: Steward, Object: T): T
	const Dynamic: any = Object
	
	if typeof(Dynamic) ~= "table" or typeof(Dynamic.Destroy) ~= "function" then
		warn("[Steward] AdoptDestroyable() was given a value with no Destroy method. Ignoring.")
		return Object
	end
	
	if self.Dismissed then
		SafeDestroy(Dynamic :: Destroyable)
		return Object
	end
	
	ClaimOwnership(self, Dynamic, "_destroyables", self._destroyables)
	
	return Object
end

--[=[
@within Steward
@method AdoptDisconnectable

Adopts a disconnectable object to a Steward object

@param Object T -- Object to adopt
@return T
]=]
function Steward.AdoptDisconnectable<T>(self: Steward, Object: T): T
	const Dynamic: any = Object
	
	if typeof(Dynamic) ~= "table" or typeof(Dynamic.Disconnect) ~= "function" then
		warn("[Steward] AdoptDisconnectable() was given a value with no Disconnect method. Ignoring.")
		return Object
	end
	
	if self.Dismissed then
		SafeDisconnectObject(Dynamic :: Disconnectable)
		return Object
	end
	
	ClaimOwnership(self, Dynamic, "_disconnectables", self._disconnectables)
	
	return Object
end

--[=[
@within Steward
@method AddCleanup

Adds a cleanup function to the Steward object

@param fn CleanupFn -- Function to call at cleanup
@return CleanupFn
]=]
function Steward.AddCleanup(self: Steward, fn: CleanupFn): CleanupFn
	if self.Dismissed then
		SafeCallCleanup(fn)
		return fn
	end
	
	ClaimOwnership(self, fn, "_functions", self._functions)
	
	return fn
end

--[=[
@within Steward
@method Adopt

Adopts a resource to a Steward object

@param Resource T -- Resource to adopt
@return T
]=]
function Steward.Adopt<T>(self: Steward, Resource: T): T
	const Dynamic: any = Resource
	const Kind: string = typeof(Dynamic)
	
	if Kind == "RBXScriptConnection" then
		self:AdoptConnection(Dynamic :: RBXScriptConnection)
	elseif Kind == "thread" then
		self:AdoptThread(Dynamic :: thread)
	elseif Kind == "Instance" then
		if (Dynamic :: Instance):IsA("Tween") then
			self:AdoptTween(Dynamic :: Tween)
		else
			self:AdoptInstance(Dynamic :: Instance)
		end
	elseif Kind == "function" then
		self:AddCleanup(Dynamic :: CleanupFn)
	elseif Kind == "table" and getmetatable(Dynamic) == Steward then
		self:Nest(Dynamic :: Steward)
	elseif Kind == "table" and typeof(Dynamic.Destroy) == "function" then
		self:AdoptDestroyable(Dynamic :: Destroyable)
	elseif Kind == "table" and typeof(Dynamic.Disconnect) == "function" then
		self:AdoptDisconnectable(Dynamic :: Disconnectable)
	else
		warn("[Steward] Adopt() received an unsupported resource type: " .. Kind)
	end
	
	return Resource
end

--[=[
@within Steward
@method Nest

Nests a Steward object as a child of this one.

@param NameOrChild (string | Steward)? -- Name of the child, or the child itself
@return Steward
]=]
function Steward.Nest(self: Steward, NameOrChild: (string | Steward)?): Steward
	local Child: Steward
	
	if NameOrChild == nil then
		Child = Steward.new(nil)
	elseif typeof(NameOrChild) == "string" then
		Child = Steward.new(NameOrChild)
	else
		Child = NameOrChild
	end
	
	if Child == self or IsAncestorOf(Child, self) then
		warn("[Steward] nesting this Steward here would create an ownership cycle. Ignoring.")
		return Child
	end
	
	const oldParent = Child._parent
	if oldParent ~= nil then
		const oldSiblings = oldParent._children
		for i = 1, #oldSiblings do
			if oldSiblings[i] == Child then
				table.remove(oldSiblings, i)
				break
			end
		end
	end
	
	if self.Dismissed then
		warn("[Steward] nesting into a dismissed Steward, immediately dismissing the child instead.");
		(Child :: any)._parent = nil
		Child:Dismiss()
		return Child
	end
	
	(Child :: any)._parent = (self :: any)
	table.insert((self :: any)._children, Child)
	
	return Child
end

--[=[
@within Steward
@method AttachTo

Attaches a Steward to an Instance.

@param instance Instance -- Instance to attach to
@return Steward
]=]
function Steward.AttachTo(self: Steward, instance: Instance): Steward
	if instance.Parent == game then
		warn("[Steward] AttachTo() was called on a Service. If you are trying to make an ever-lasting Steward, create a root Steward that never gets dismissed instead.")
		return self
	end
	
	if self.Dismissed then
		return self
	end
	
	const IsAlreadyDestroyed = not pcall(function()
		instance.Parent = instance.Parent
	end)
	
	if IsAlreadyDestroyed then
		self:Dismiss()
		return self
	end
	
	const Connection = instance.Destroying:Connect(function()
		self:Dismiss()
	end)
	
	table.insert(self._attachConnections, Connection)
	
	return self
end

--[=[
@within Steward
@method Dismiss

Dismisses the Steward, cleaning up all resources it owns

@return void
]=]
function Steward.Dismiss(self: Steward): ()
	if self.Dismissed then
		return
	end
	
	self.Dismissed = true
	
	const attachConnections = self._attachConnections
	for i = 1, #attachConnections do
		SafeDisconnect(attachConnections[i])
		attachConnections[i] = nil
	end
	
	const Connections = self._connections
	for i = 1, #Connections do
		SafeDisconnect(Connections[i])
		Connections[i] = nil
	end
	
	const Threads = self._threads
	for i = 1, #Threads do
		SafeCancelThread(Threads[i])
		Threads[i] = nil
	end
	
	const Tweens = self._tweens
	for i = 1, #Tweens do
		SafeCancelTween(Tweens[i])
		Tweens[i] = nil
	end
	
	const Children = self._children
	for i = 1, #Children do
		Children[i]:Dismiss()
		Children[i] = nil
	end
	
	const Instances = self._instances
	for i = 1, #Instances do
		SafeDestroyInstance(Instances[i])
		Instances[i] = nil
	end
	
	const Destroyables = self._destroyables
	for i = 1, #Destroyables do
		SafeDestroy(Destroyables[i])
		Destroyables[i] = nil
	end
	
	const Disconnectables = self._disconnectables
	for i = 1, #Disconnectables do
		SafeDisconnectObject(Disconnectables[i])
		Disconnectables[i] = nil
	end
	
	const Functions = self._functions
	for i = 1, #Functions do
		SafeCallCleanup(Functions[i])
		Functions[i] = nil
	end
	
	const Parent = self._parent
	if Parent ~= nil and not Parent.Dismissed then
		const Siblings = Parent._children
		for i = 1, #Siblings do
			if Siblings[i] == self then
				table.remove(Siblings, i)
				break
			end
		end
	end
	
	(self :: any)._parent = nil
end

--[=[
@within Steward
@method _snapshotNode

Creates a snapshot node

@private
@return SnapshotNode
]=]
function Steward._snapshotNode(self: Steward): SnapshotNode
	const Children = self._children
	const childNodes: {SnapshotNode} = {}
	
	for i = 1, #Children do
		table.insert(childNodes, Children[i]:_snapshotNode())
	end
	
	const Counts: ResourceCounts = {
		Connections = #self._connections,
		Threads = #self._threads,
		Tweens = #self._tweens,
		Instances = #self._instances,
		Destroyables = #self._destroyables,
		Disconnectables = #self._disconnectables,
		Functions = #self._functions,
	}
	
	return Debug.BuildNode(self._id, self.Name, Counts, childNodes)
end

--[=[
@within Steward
@method Snapshot

Takes a snapshot of the current state of the Steward hierarchy

@return Snapshot
]=]
function Steward.Snapshot(self: Steward): Snapshot
	return Debug.BuildSnapshot(self:_snapshotNode())
end

--[=[
@within Steward
@method Dump

Dumps the current state of the Steward hierarchy to the debug console

@return string
]=]
function Steward.Dump(self: Steward): string
	const text = Debug.Dump(self:_snapshotNode())
	
	print("\n" .. text)
	
	return text
end

--[=[
@within Steward

Dumps the difference between two Steward snapshots to the debug console

@param a Snapshot -- First snapshot
@param b Snapshot -- Second snapshot
@return string
]=]
function Steward.Diff(a: Snapshot, b: Snapshot): string
	const text = Debug.Diff(a, b)
	
	print("\n" .. text)
	
	return text
end

--========== Return ==========--
return Steward