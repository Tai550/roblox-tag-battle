-- mockenv: テスト用に Roblox の API（game / Instance / Vector3 など）を真似た最小限の実装
-- 本物のモジュールを Luau CLI で読み込んで、計算だけの関数を検証するために使う。
-- build_tests.py が src の各モジュールの先頭に「このファイルから取り込む前置き」を付ける。

local RT = {}

---------------------------------------------------------------------
-- Vector3 / Color3 / CFrame
---------------------------------------------------------------------

local Vector3MT = {}
Vector3MT.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	if key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	if key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return RT.Vector3.new(0, 0, 0)
		end
		return RT.Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end
Vector3MT.__add = function(a, b)
	return RT.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3MT.__sub = function(a, b)
	return RT.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

Vector3MT.__mul = function(a, b)
	return RT.Vector3.new(a.X * b, a.Y * b, a.Z * b)
end

RT.Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT)
	end,
}

RT.Vector2 = {
	new = function(x, y) return { X = x, Y = y } end,
}

RT.UDim = {
	new = function(scale, offset) return { Scale = scale, Offset = offset } end,
}

RT.Color3 = {
	fromRGB = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}

RT.UDim2 = {
	new = function(xs, xo, ys, yo)
		return { XScale = xs or 0, XOffset = xo or 0, YScale = ys or 0, YOffset = yo or 0 }
	end,
	fromScale = function(xs, ys)
		return { XScale = xs or 0, XOffset = 0, YScale = ys or 0, YOffset = 0 }
	end,
	fromOffset = function(xo, yo)
		return { XScale = 0, XOffset = xo or 0, YScale = 0, YOffset = yo or 0 }
	end,
}

local CFrameMT = {}
CFrameMT.__index = CFrameMT

function CFrameMT:PointToObjectSpace(point)
	local offset = point - self.Position
	local x, y, z = offset.X, offset.Y, offset.Z
	local cx, sx = math.cos(self.RotX), math.sin(self.RotX)
	local cy, sy = math.cos(self.RotY), math.sin(self.RotY)
	local cz, sz = math.cos(self.RotZ), math.sin(self.RotZ)
	y, z = cx * y + sx * z, -sx * y + cx * z
	x, z = cy * x - sy * z, sy * x + cy * z
	x, y = cz * x + sz * y, -sz * x + cz * y
	return RT.Vector3.new(x, y, z)
end

-- 平行移動を合成し、回転の検証用に右辺の角度を保持する。
CFrameMT.__add = function(frame, offset)
	local position = frame.Position + offset
	local moved = table.clone(frame)
	moved.Position = position
	moved.X, moved.Y, moved.Z = position.X, position.Y, position.Z
	return setmetatable(moved, CFrameMT)
end
CFrameMT.__mul = function(a, b)
	local x, y, z = b.X, b.Y, b.Z
	local cx, sx = math.cos(a.RotX), math.sin(a.RotX)
	local cy, sy = math.cos(a.RotY), math.sin(a.RotY)
	local cz, sz = math.cos(a.RotZ), math.sin(a.RotZ)
	x, y = cz * x - sz * y, sz * x + cz * y
	x, z = cy * x + sy * z, -sy * x + cy * z
	y, z = cx * y - sx * z, sx * y + cx * z
	local position = a.Position + RT.Vector3.new(x, y, z)
	return setmetatable({
		X = position.X,
		Y = position.Y,
		Z = position.Z,
		RotX = (b and b.RotX) or 0,
		RotY = (b and b.RotY) or 0,
		RotZ = (b and b.RotZ) or 0,
		LookVector = b.LookVector,
		Position = position,
	}, CFrameMT)
end
function CFrameMT:ToObjectSpace(frame)
	local relative = RT.CFrame.Angles(frame.RotX - self.RotX, frame.RotY - self.RotY, frame.RotZ - self.RotZ)
	return relative + self:PointToObjectSpace(frame.Position)
end

RT.CFrame = {
	new = function(x, y, z)
		if getmetatable(x) == Vector3MT then
			x, y, z = x.X, x.Y, x.Z
		end
		return setmetatable({
			X = x or 0,
			Y = y or 0,
			Z = z or 0,
			RotX = 0,
			RotY = 0,
			RotZ = 0,
			LookVector = RT.Vector3.new(0, 0, -1),
			Position = RT.Vector3.new(x or 0, y or 0, z or 0),
		}, CFrameMT)
	end,
	Angles = function(rx, ry, rz)
		local pitch, yaw = rx or 0, ry or 0
		return setmetatable({
			X = 0,
			Y = 0,
			Z = 0,
			RotX = rx or 0,
			RotY = ry or 0,
			RotZ = rz or 0,
			LookVector = RT.Vector3.new(-math.sin(yaw), math.sin(pitch) * math.cos(yaw), -math.cos(pitch) * math.cos(yaw)),
			Position = RT.Vector3.new(0, 0, 0),
		}, CFrameMT)
	end,
}

function RT.CFrame.lookAt(position, target)
	local frame = RT.CFrame.new(position)
	frame.LookVector = (target - position).Unit
	return frame
end

---------------------------------------------------------------------
-- Enum（値は文字列で代用。比較に使われない前提）
---------------------------------------------------------------------

RT.Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, name)
				return group .. "." .. name
			end,
		})
	end,
})

---------------------------------------------------------------------
-- Instance
---------------------------------------------------------------------

local fakeEvent = {
	Connect = function(_, _)
		return { Disconnect = function() end }
	end,
}

-- Touched / Heartbeat / DescendantAdded 用。Connect した関数は _Fire で呼べる。
local function makeSignal()
	local callbacks = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(callbacks, fn)
		local connected = true
		return {
			Disconnect = function()
				if not connected then
					return
				end
				connected = false
				for index = #callbacks, 1, -1 do
					if callbacks[index] == fn then
						table.remove(callbacks, index)
					end
				end
			end,
		}
	end
	function signal:_Fire(...)
		local snapshot = {}
		for index, fn in ipairs(callbacks) do
			snapshot[index] = fn
		end
		for _, fn in ipairs(snapshot) do
			fn(...)
		end
	end
	return signal
end

RT.PhysicalProperties = { new = function(...) return { ... } end }
RT.OverlapParams = { new = function() return {} end }
RT.RaycastParams = { new = function() return {} end }

local instanceMethods = {}

function instanceMethods.GetPropertyChangedSignal()
	return fakeEvent
end
function instanceMethods.GetAttributeChangedSignal(self, name)
	self._attributeSignals = self._attributeSignals or {}
	if not self._attributeSignals[name] then
		self._attributeSignals[name] = makeSignal()
	end
	return self._attributeSignals[name]
end
function instanceMethods.SetAttribute(self, name, value)
	if self._attributes[name] ~= value then
		self._attributes[name] = value
		local signal = self._attributeSignals and self._attributeSignals[name]
		if signal then
			signal:_Fire()
		end
	end
end
function instanceMethods.GetAttribute(self, name)
	return self._attributes[name]
end
function instanceMethods.GetServerTimeNow()
	return os.clock()
end
function instanceMethods.GetPartsInPart(self, part, params)
	return self._overlap and self._overlap(part, params) or {}
end
function instanceMethods.Raycast(self, origin, direction, params)
	return self._raycast and self._raycast(origin, direction, params)
end
function instanceMethods.GetPivot(self)
	local root = self:FindFirstChild("HumanoidRootPart")
	return RT.CFrame.new(root.Position.X, root.Position.Y, root.Position.Z)
end
function instanceMethods.GetBoundingBox(self)
	return self:GetPivot(), RT.Vector3.new(2, 5, 2)
end
function instanceMethods.GetPartBoundsInBox(self, frame, size, params)
	return self._bounds and self._bounds(frame, size, params) or {}
end
function instanceMethods.PivotTo(self, pivot)
	local root = self:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = pivot
		root.Position = pivot.Position
	elseif self.ClassName == "Model" then
		self.WorldPivot = pivot
	end
end
function instanceMethods.FindFirstChild(self, name, recursive)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(self:GetChildren()) do
			local match = child:FindFirstChild(name, true)
			if match then
				return match
			end
		end
	end
	return nil
end
function instanceMethods.WaitForChild(self, name)
	local found = instanceMethods.FindFirstChild(self, name)
	if found then
		return found
	end
	-- 子がなければ「モジュール名の目印」を返す（fakeRequire が解決する）
	return { __moduleName = name }
end
function instanceMethods.FindFirstChildOfClass(self, className)
	for _, child in ipairs(rawget(self, "_children") or {}) do
		if instanceMethods.IsA(child, className) then
			return child
		end
	end
	return nil
end
function instanceMethods.FindFirstChildWhichIsA(self, className, recursive)
	local children = recursive and self:GetDescendants() or self:GetChildren()
	for _, child in ipairs(children) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end
function instanceMethods.FindFirstAncestorOfClass(self, className)
	local current = rawget(self, "_parent")
	while type(current) == "table" and rawget(current, "ClassName") do
		if instanceMethods.IsA(current, className) then
			return current
		end
		current = rawget(current, "_parent")
	end
	return nil
end
function instanceMethods.GetChildren(self)
	local list = {}
	for _, child in ipairs(rawget(self, "_children") or {}) do
		table.insert(list, child)
	end
	return list
end
function instanceMethods.GetDescendants(self)
	local list = {}
	local function walk(node)
		for _, child in ipairs(rawget(node, "_children") or {}) do
			table.insert(list, child)
			walk(child)
		end
	end
	walk(self)
	return list
end
-- BasePart として扱うクラス（Part の仲間）
local BASE_PART_CLASSES = {
	Part = true,
	WedgePart = true,
	SpawnLocation = true,
	TrussPart = true,
	MeshPart = true,
}
function instanceMethods.IsA(self, className)
	if className == "BasePart" then
		return BASE_PART_CLASSES[rawget(self, "ClassName")] == true
	end
	return rawget(self, "ClassName") == className
end
-- 親の子リストから外す（Destroy と親の付け替えで使う）
local function detachFromParent(self)
	local parent = rawget(self, "_parent")
	if type(parent) == "table" and rawget(parent, "_children") then
		local children = rawget(parent, "_children")
		for index = #children, 1, -1 do
			if children[index] == self then
				table.remove(children, index)
			end
		end
	end
end
function instanceMethods.Clone(self)
	local copy = RT.Instance.new(self.ClassName)
	for key, value in pairs(self) do
		if key ~= "Parent" and string.sub(key, 1, 1) ~= "_" then
			copy[key] = value
		end
	end
	copy._attributes = table.clone(self._attributes)
	for _, child in ipairs(self:GetChildren()) do
		child:Clone().Parent = copy
	end
	return copy
end
function instanceMethods.Destroy(self)
	detachFromParent(self)
	rawset(self, "_parent", nil)
end
function instanceMethods.SetStateEnabled(self, state, enabled)
	self._enabledStates = self._enabledStates or {}
	self._enabledStates[state] = enabled
end
function instanceMethods.GetStateEnabled(self, state)
	return not self._enabledStates or self._enabledStates[state] ~= false
end
function instanceMethods.ChangeState(self, state)
	if self:GetStateEnabled(state) then
		self._state = state
	end
end
function instanceMethods.GetState(self)
	return self._state or RT.Enum.HumanoidStateType.Running
end
function instanceMethods.FireServer(_, ...)
end
function instanceMethods.FireClient(_, ...)
end
function instanceMethods.FireAllClients(_, ...)
end

local instanceMT = {
	__index = function(self, key)
		if key == "Parent" then
			return rawget(self, "_parent")
		end
		local method = instanceMethods[key]
		if method then
			return method
		end
		if key == "Activated" or key == "InputBegan" then
			return fakeEvent
		end
		if key == "OnServerEvent" or key == "OnClientEvent" or key == "Touched"
			or key == "Heartbeat" or key == "PostSimulation" or key == "DescendantAdded"
			or key == "CharacterAdded" or key == "CharacterRemoving" then
			local signals = rawget(self, "_signals")
			if not signals then
				signals = {}
				rawset(self, "_signals", signals)
			end
			if not signals[key] then
				signals[key] = makeSignal()
			end
			return signals[key]
		end
		return nil
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			detachFromParent(self)
			if type(value) == "table" and rawget(value, "_children") then
				table.insert(rawget(value, "_children"), self)
			end
			rawset(self, "_parent", value)
			return
		end
		-- 本物の Roblox と同じく、Material に Enum 以外（数値など）を入れたらエラーにする
		if key == "Material" and not (type(value) == "string" and string.sub(value, 1, 9) == "Material.") then
			error("Unable to assign property Material. Invalid value " .. tostring(value) .. " for enum Material", 2)
		end
		rawset(self, key, value)
	end,
}

RT.Instance = {
	new = function(className)
		local obj = { ClassName = className, Name = className, _children = {}, _attributes = {} }
		if BASE_PART_CLASSES[className] then
			obj.CollisionGroup = "Default"
			obj.Size = RT.Vector3.new(1, 1, 1)
			obj.AssemblyLinearVelocity = RT.Vector3.new(0, 0, 0)
		elseif className == "ScreenGui" then
			obj.AbsoluteSize = RT.Vector2.new(360, 640)
		elseif className == "Humanoid" then
			obj.HipHeight = 0
		end
		return setmetatable(obj, instanceMT)
	end,
}

---------------------------------------------------------------------
-- サービスと game / workspace
---------------------------------------------------------------------

local playersService = {
	GetPlayers = function(_)
		return {}
	end,
	GetPlayerFromCharacter = function(_, _)
		return nil
	end,
	PlayerAdded = makeSignal(),
	PlayerRemoving = makeSignal(),
}

local replicatedStorage = RT.Instance.new("ReplicatedStorage")
local sharedFolder = RT.Instance.new("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = replicatedStorage

---------------------------------------------------------------------
-- DataStore（メモリ上の表）
-- RT.DataStoreShouldFail が true のあいだ、GetAsync / SetAsync / UpdateAsync は失敗する。
---------------------------------------------------------------------

RT.DataStoreShouldFail = false

local function cloneData(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneData(child)
	end
	return copy
end

local dataStores = {}

local function makeDataStore()
	local records = {}
	local store = {}
	function store:GetAsync(key)
		if RT.DataStoreShouldFail then
			error("DataStore の取得に失敗しました")
		end
		return cloneData(records[tostring(key)])
	end
	function store:SetAsync(key, value)
		if RT.DataStoreShouldFail then
			error("DataStore への保存に失敗しました")
		end
		records[tostring(key)] = cloneData(value)
	end
	function store:RemoveAsync(key)
		self:SetAsync(key, nil)
	end
	function store:ListKeysAsync(_, pageSize)
		local keys = {}
		for key in pairs(records) do
			table.insert(keys, key)
		end
		table.sort(keys)
		local start = 1
		local pages = { IsFinished = #keys <= pageSize }
		function pages:GetCurrentPage()
			local page = {}
			for index = start, math.min(start + pageSize - 1, #keys) do
				table.insert(page, { KeyName = keys[index] })
			end
			return page
		end
		function pages:AdvanceToNextPageAsync()
			start += pageSize
			self.IsFinished = start + pageSize > #keys
		end
		return pages
	end
	function store:UpdateAsync(key, transform)
		if RT.DataStoreShouldFail then
			error("DataStore の更新に失敗しました")
		end
		local newValue = transform(cloneData(records[tostring(key)]))
		if newValue == nil then
			return nil
		end
		records[tostring(key)] = cloneData(newValue)
		return cloneData(records[tostring(key)])
	end
	return store
end

local dataStoreService = {
	GetOrderedDataStore = function(_, storeName)
		local name = "ordered:" .. tostring(storeName)
		local store = dataStores[name]
		if not store then
			store = makeDataStore()
			dataStores[name] = store
		end
		return store
	end,
	GetDataStore = function(_, storeName)
		local name = tostring(storeName)
		local store = dataStores[name]
		if not store then
			store = makeDataStore()
			dataStores[name] = store
		end
		return store
	end,
}

local collisionGroups = {}
local collisions = {}
local nextGuid = 0
local services = {
	Lighting = { Brightness = 2 },
	PhysicsService = {
		IsCollisionGroupRegistered = function(_, group) return collisionGroups[group] == true end,
		RegisterCollisionGroup = function(_, group) collisionGroups[group] = true end,
		CollisionGroupSetCollidable = function(_, a, b, collidable)
			collisions[a .. ":" .. b] = collidable
		end,
		CollisionGroupsAreCollidable = function(_, a, b)
			return collisions[a .. ":" .. b] ~= false and collisions[b .. ":" .. a] ~= false
		end,
	},
	Players = playersService,
	ReplicatedStorage = replicatedStorage,
	DataStoreService = dataStoreService,
	HttpService = {
		GenerateGUID = function()
			nextGuid += 1
			return "test-guid-" .. nextGuid
		end,
	},
	TextService = {
		FilterStringAsync = function(_, text)
			return { GetNonChatStringForBroadcastAsync = function()
				return "[filtered] " .. text
			end }
		end,
	},
}

RT.workspace = RT.Instance.new("Workspace")

-- 光線：テストが _raycast を差し込んでいればそれを使う。
-- なければ、除外リスト型（ボックスの空き地探し・送還位置）は高さ 0 の平らな地面に当たり、
-- 対象リスト型（足場の判定など）は何にも当たらない
RT.RaycastParams = {
	new = function()
		return {}
	end,
}
RT.workspace.Blockcast = function(self, frame, size, direction, params)
	if self._blockcast then
		return self._blockcast(frame, size, direction, params)
	end
end
RT.workspace.Raycast = function(self, origin, direction, params)
	if self._raycast then
		return self._raycast(origin, direction, params)
	end
	if params and params.FilterType == RT.Enum.RaycastFilterType.Include then
		return nil
	end
	-- 水平・斜めの視線が床を横切らない場合は何にも当たらない。
	if direction.Y >= 0 or origin.Y < 0 or origin.Y + direction.Y > 0 then
		return nil
	end
	local floorHit = origin + direction * (-origin.Y / direction.Y)
	return {
		Position = floorHit,
		Normal = RT.Vector3.new(0, 1, 0),
		Instance = { CanCollide = true },
	}
end

RT.game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			service = RT.Instance.new("Service")
			service.Name = name
			services[name] = service
		end
		return service
	end,
	BindToClose = function(_, callback)
		RT._bindToClose = callback
	end,
}

---------------------------------------------------------------------
-- その他
---------------------------------------------------------------------

RT.task = {
	wait = function(_)
		return 0
	end,
	spawn = function(_)
	end,
	delay = function(_, _)
	end,
	defer = function(_)
	end,
}

RT.warn = function(...)
	print("[warn]", ...)
end

-- 各モジュール用の script（Parent.WaitForChild がモジュール名の目印を返す）
function RT.scriptFor(_moduleName)
	return {
		Parent = {
			WaitForChild = function(_, childName)
				return { __moduleName = childName }
			end,
		},
	}
end

-- モジュールの読み込み表（run_tests.lua が依存順に登録する）
RT.modules = {}

function RT.fakeRequire(target)
	if type(target) == "table" and target.__moduleName then
		local module = RT.modules[target.__moduleName]
		if module == nil then
			error("モック未登録のモジュール: " .. tostring(target.__moduleName))
		end
		return module
	end
	error("fakeRequire: 想定外の引数 " .. tostring(target))
end

return RT
