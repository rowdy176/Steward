--!strict

--[=[
	@class Debug
	
	Utility functions for debugging purposes.
	
	Not intended for direct use, please refrain from directly using this module,
	instead use the `Steward.Dump`, `Steward.Diff` and `Steward.Snapshot` functions.
]=]

--========== Dependencies ==========--
const Types = require(script.Parent.Types)

--========== Primary Types ==========--
type ResourceCounts = Types.ResourceCounts
type SnapshotNode   = Types.SnapshotNode
type Snapshot       = Types.Snapshot

--========== Module ==========--
const Debug = {}

--========== Public API ==========--

--[=[
@within Debug
@method NewCounts

Creates a new resource count table.

@return ResourceCounts
]=]
function Debug.NewCounts(): ResourceCounts
	return {
		Connections = 0,
		Threads = 0,
		Tweens = 0,
		Instances = 0,
		Destroyables = 0,
		Disconnectables = 0,
		Functions = 0,
	}
end

--[=[
@within Debug

Creates a new snapshot node.

@param ID number -- Unique identifier
@param name string -- Name of the node
@param counts ResourceCounts -- Resource counts
@param children {SnapshotNode} -- Children nodes
@return SnapshotNode
]=]
function Debug.BuildNode(ID: number, name: string, counts: ResourceCounts, children: {SnapshotNode}): SnapshotNode
	return {
		Id = ID,
		Name = name,
		Counts = counts,
		Children = children,
	}
end

--[=[
@within Debug

Creates a new snapshot.

@param root SnapshotNode -- Root node of the snapshot
@return Snapshot
]=]
function Debug.BuildSnapshot(root: SnapshotNode): Snapshot
	return {
		Root = root,
		TakenAt = os.clock(),
	}
end

--[=[
@private
@function Arrow
@within Debug
]=]
const function Arrow(Depth: number): string
	if Depth <= 0 then
		return ""
	end
	
	return string.rep("-", Depth) .. "> "
end

--[=[
@private
@function NameLine
@within Debug
]=]
const function NameLine(Depth: number, Label: string): string
	if Depth <= 0 then
		return Label
	end
	
	return Arrow(Depth) .. Label
end


--[=[
@private
@function AppendCountLine
@within Debug
]=]
const function AppendCountLine(Lines: {string}, Depth: number, Count: number, Singular: string, Plural: string): ()
	if Count == 0 then
		return
	end
	
	const Label: string = if Count == 1 then Singular else Plural
	
	table.insert(Lines, Arrow(Depth) .. tostring(Count) .. " " .. Label)
end

--[=[
@private
@function AppendSignedCountLine
@within Debug
]=]
const function AppendSignedCountLine(Lines: {string}, Depth: number, Delta: number, Singular: string, Plural: string): ()
	if Delta == 0 then
		return
	end
	
	const Magnitude: number = if Delta < 0 then -Delta else Delta
	const Label: string = if Magnitude == 1 then Singular else Plural
	const Sign: string = if Delta > 0 then "+" else "-"
	
	table.insert(Lines, Arrow(Depth) .. Sign .. tostring(Magnitude) .. " " .. Label)
end

--[=[
@private
@function AppendCounts
@within Debug
]=]
const function AppendCounts(Lines: {string}, Depth: number, Counts: ResourceCounts, Signed: boolean): ()
	const resourceDepth: number = Depth + 1
	if Signed then
		AppendSignedCountLine(Lines, resourceDepth, Counts.Connections, "Connection", "Connections")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Threads, "Thread", "Threads")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Tweens, "Tween", "Tweens")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Instances, "Instance", "Instances")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Destroyables, "Destroyable", "Destroyables")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Disconnectables, "Disconnectable", "Disconnectables")
		AppendSignedCountLine(Lines, resourceDepth, Counts.Functions, "Function", "Functions")
	else
		AppendCountLine(Lines, resourceDepth, Counts.Connections, "Connection", "Connections")
		AppendCountLine(Lines, resourceDepth, Counts.Threads, "Thread", "Threads")
		AppendCountLine(Lines, resourceDepth, Counts.Tweens, "Tween", "Tweens")
		AppendCountLine(Lines, resourceDepth, Counts.Instances, "Instance", "Instances")
		AppendCountLine(Lines, resourceDepth, Counts.Destroyables, "Destroyable", "Destroyables")
		AppendCountLine(Lines, resourceDepth, Counts.Disconnectables, "Disconnectable", "Disconnectables")
		AppendCountLine(Lines, resourceDepth, Counts.Functions, "Function", "Functions")
	end
end

--[=[
@private
@function DumpNode
@within Debug
]=]
const function DumpNode(Node: SnapshotNode, Depth: number, Lines: {string}): ()
	table.insert(Lines, NameLine(Depth, Node.Name))
	AppendCounts(Lines, Depth, Node.Counts, false)
	
	const Children = Node.Children
	
	for i = 1, #Children do
		DumpNode(Children[i], Depth + 1, Lines)
	end
end

--[=[
@within Debug

This function dumps the snapshot to a string for debugging purposes

@param Root SnapshotNode
@return string
]=]
function Debug.Dump(Root: SnapshotNode): string
	const Lines: {string} = {}
	
	DumpNode(Root, 0, Lines)
	
	return table.concat(Lines, "\n")
end

--[=[
@private
@function CountsDelta
@within Debug
]=]
const function CountsDelta(a: ResourceCounts, b: ResourceCounts): ResourceCounts
	return {
		Connections = b.Connections - a.Connections,
		Threads = b.Threads - a.Threads,
		Tweens = b.Tweens - a.Tweens,
		Instances = b.Instances - a.Instances,
		Destroyables = b.Destroyables - a.Destroyables,
		Disconnectables = b.Disconnectables - a.Disconnectables,
		Functions = b.Functions - a.Functions,
	}
end

--[=[
@private
@function CountsHaveChange
@within Debug
]=]
const function CountsHaveChange(counts: ResourceCounts): boolean
	return counts.Connections ~= 0
		or counts.Threads ~= 0
		or counts.Tweens ~= 0
		or counts.Instances ~= 0
		or counts.Destroyables ~= 0
		or counts.Disconnectables ~= 0
		or counts.Functions ~= 0
end

--[=[
@private
@function FindChildById
@within Debug
]=]
const function FindChildById(children: {SnapshotNode}, id: number): SnapshotNode?
	for i = 1, #children do
		if children[i].Id == id then
			return children[i]
		end
	end
	
	return nil
end

--[=[
@private
@function DiffNode
@within Debug
]=]
const function DiffNode(aNode: SnapshotNode?, bNode: SnapshotNode?, depth: number, lines: {string}): boolean
	if aNode ~= nil and bNode ~= nil then
		const delta = CountsDelta(aNode.Counts, bNode.Counts)
		const selfChanged = CountsHaveChange(delta)
		
		const childLines: {string} = {}
		local anyChildChanged = false
		
		const bChildren = bNode.Children
		for i = 1, #bChildren do
			const bChild = bChildren[i]
			const aChild = FindChildById(aNode.Children, bChild.Id)
			
			if DiffNode(aChild, bChild, depth + 1, childLines) then
				anyChildChanged = true
			end
		end
		
		const aChildren = aNode.Children
		for i = 1, #aChildren do
			const aChild = aChildren[i]
			
			if FindChildById(bChildren, aChild.Id) == nil then
				if DiffNode(aChild, nil, depth + 1, childLines) then
					anyChildChanged = true
				end
			end
		end
		
		if not selfChanged and not anyChildChanged then
			return false
		end
		
		table.insert(lines, NameLine(depth, bNode.Name))
		AppendCounts(lines, depth, delta, true)
		
		for i = 1, #childLines do
			table.insert(lines, childLines[i])
		end
		
		return true
	elseif aNode ~= nil then
		const delta = CountsDelta(aNode.Counts, Debug.NewCounts())
		
		const childLines: {string} = {}
		const aChildren = aNode.Children
		
		for i = 1, #aChildren do
			DiffNode(aChildren[i], nil, depth + 1, childLines)
		end
		
		table.insert(lines, NameLine(depth, aNode.Name .. " (removed)"))
		AppendCounts(lines, depth, delta, true)
		
		for i = 1, #childLines do
			table.insert(lines, childLines[i])
		end
		
		return true
	elseif bNode ~= nil then
		const delta = CountsDelta(Debug.NewCounts(), bNode.Counts)
		
		const childLines: {string} = {}
		const bChildren = bNode.Children
		
		for i = 1, #bChildren do
			DiffNode(nil, bChildren[i], depth + 1, childLines)
		end
		
		table.insert(lines, NameLine(depth, bNode.Name .. " (added)"))
		AppendCounts(lines, depth, delta, true)
		
		for i = 1, #childLines do
			table.insert(lines, childLines[i])
		end
		
		return true
	else
		return false
	end
end

--[=[
@within Debug

Returns a snapshot of the tree with the differences between two snapshots

@param a Snapshot
@param b Snapshot
@return string
]=]
function Debug.Diff(a: Snapshot, b: Snapshot): string
	const lines: {string} = {}
	const changed = DiffNode(a.Root, b.Root, 0, lines)
	
	if not changed then
		return b.Root.Name .. "\n(no changes)"
	end
	
	return table.concat(lines, "\n")
end

--========== Return ==========--
return Debug