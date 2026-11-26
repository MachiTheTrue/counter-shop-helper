-- Counter & Shop Helper: reading the game through Tempest's reflection API (types/tempest.d.lua).
--
-- A live UObject answers Object:has(name) for its declared properties, so a property is read only
-- when its class declares it: no "has no property" line in the Tempest log, no pcall per read.
-- A struct value (an array entry such as TempItemInfo or DeviceTeamInfo) has no has(): calling it
-- fails ("attempt to call method 'has'" in the LiveCheck log), so has() is looked up first and a
-- struct's declared fields are read directly. A plain value (number, string, boolean) has no fields.
-- UFunctions are called as methods (obj:Func(...)), only on a class that declares them (is_a first).
-- What can still fail (an object destroyed between two reads) is caught once per read by the
-- caller's poll, which logs it.

local G = {}

local function indexable(o)
	local t = type(o)
	return t == "userdata" or t == "table"
end

-- A property of an object, or a field of a struct; nil when the object's class does not declare it.
function G.field(o, name)
	if not indexable(o) then return nil end
	local has = o.has
	if has and not has(o, name) then return nil end
	return o[name]
end

-- true / false; nil when o is not an object (a struct, nil) and cannot say.
function G.is_a(o, class)
	if not indexable(o) or not o.is_a then return nil end
	return o:is_a(class)
end

function G.class_name(o)
	local c = indexable(o) and o.class and o:class()
	return c and c:name() or nil
end

function G.ptr(o)
	return indexable(o) and o.ptr and o:ptr() or nil
end

return G
