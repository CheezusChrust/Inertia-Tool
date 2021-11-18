TOOL.Category = "Construction"
TOOL.Name = "#Inertia"
TOOL.ClientConVar["mode"] = "direct"
TOOL.ClientConVar["x"] = "1"
TOOL.ClientConVar["y"] = "1"
TOOL.ClientConVar["z"] = "1"
TOOL.ClientConVar["xyz"] = "1"
TOOL.ClientConVar["tooltipscale"] = "1"
TOOL.ClientConVar["lock"] = "0"

if CLIENT then
    TOOL.Information = {
        {
            name = "left"
        },
        {
            name = "right"
        },
        {
            name = "reload"
        }
    }

    language.Add("tool.inertia.name", "Inertia")
    language.Add("tool.inertia.desc", "Sets an entity's rotational inertia (resistance to rotation) without changing its mass")
    language.Add("tool.inertia.left", "Set inertia")
    language.Add("tool.inertia.right", "Get inertia")
    language.Add("tool.inertia.reload", "Reset inertia to default")
    language.Add("tool.inertia.mode", "Mode")
    language.Add("tool.inertia.modehelp", "If mode is set to 'DIRECTLY SET', inertia is set per-axis according to each slider.\n\nIf mode is set to 'MULTIPLE OF DEFAULT', inertia is set per-axis as a multiple of the prop's default inertia.")
    language.Add("tool.inertia.note", "NOTE: You can use higher or lower values by typing them manually.")
    language.Add("tool.inertia.x", "X axis inertia")
    language.Add("tool.inertia.y", "Y axis inertia")
    language.Add("tool.inertia.z", "Z axis inertia")
    language.Add("tool.inertia.xyz", "XYZ (all axes) inertia")
    language.Add("tool.inertia.inertialock", "Inertia lock")
    language.Add("tool.inertia.inertialock.help", "Keep set inertia the same even if the entity's mass changes")
    language.Add("tool.inertia.tooltipscale", "Tooltip Scale")
    language.Add("tool.inertia.warning", "WARNING: VERY HIGH VALUES ON ONE AXIS MAY CAUSE UNEXPECTED RESULTS!\nThis includes things such as props deleting themselves due to crazy physics. Be careful!")
end

local ENTITY = FindMetaTable("Entity")

--Regular vectors are heavily compressed, have to do this for accuracy
function ENTITY:SetNWVectorPrecise(key, value)
    self:SetNWFloat(key .. "_x", value[1])
    self:SetNWFloat(key .. "_y", value[2])
    self:SetNWFloat(key .. "_z", value[3])
end

function ENTITY:GetNWVectorPrecise(key, fallback)
    local x = self:GetNWFloat(key .. "_x", fallback[1])
    local y = self:GetNWFloat(key .. "_y", fallback[2])
    local z = self:GetNWFloat(key .. "_z", fallback[3])

    return Vector(x, y, z)
end

local function isReallyValid(ent)
    if not IsValid(ent) then return false end
    if not ent:IsValid() then return false end
    if ent:IsWorld() then return false end
    if ent:GetClass() ~= "prop_physics" then return false end

    if SERVER and not ent:GetPhysicsObject():IsValid() then return false end

    return true
end

local function setInertia(player, entity, data)
    if CLIENT then return end
    if not entity:GetPhysicsObject():IsValid() then return end

    if data.inertiaToSet then
        if data.inertiaLock then
            entity:GetPhysicsObject():SetInertia(data.inertiaLock)
        else
            entity:GetPhysicsObject():SetInertia(data.inertiaToSet * entity:GetPhysicsObject():GetMass())
        end

        entity.setInertia = data.inertiaToSet
        entity.inertiaLock = data.inertiaLock
        entity.defaultInertia = data.defaultInertia
    end

    --Accounting for the old version of the tool
    if data.inertia then
        entity:GetPhysicsObject():SetInertia(data.inertia)
        entity.defaultInertia = data.defaultInertia
    end

    duplicator.StoreEntityModifier(entity, "inertia", data)
end

duplicator.RegisterEntityModifier("inertia", setInertia)

if SERVER then
    if ENTITY.OldPhysicsInitSphere then
        ENTITY.PhysicsInitSphere = ENTITY.OldPhysicsInitSphere
    end

    ENTITY.OldPhysicsInitSphere = ENTITY.PhysicsInitSphere

    -- Making an entity spherical re-initializes the physics object, so we have to set everything again
    function ENTITY:PhysicsInitSphere(...)
        local ret = self:OldPhysicsInitSphere(...)

        if self.defaultInertia then
            self.defaultInertia = self:GetPhysicsObject():GetInertia() / self:GetPhysicsObject():GetMass()
        end

        if self.setInertia then
            self:GetPhysicsObject():SetInertia(self.setInertia * self:GetPhysicsObject():GetMass())
        end

        return ret
    end

    local PHYSOBJ = FindMetaTable("PhysObj")

    if PHYSOBJ.OldSetMass then
        PHYSOBJ.SetMass = PHYSOBJ.OldSetMass
    end

    PHYSOBJ.OldSetMass = PHYSOBJ.SetMass

    function PHYSOBJ:SetMass(...)
        local ret = self:OldSetMass(...)

        if self:GetEntity().inertiaLock then
            self:SetInertia(self:GetEntity().inertiaLock)
        end

        return ret
    end

    if PHYSOBJ.OldSetInertia then
        PHYSOBJ.SetInertia = PHYSOBJ.OldSetInertia
    end

    PHYSOBJ.OldSetInertia = PHYSOBJ.SetInertia

    function PHYSOBJ:SetInertia(v)
        if not self:GetEntity().defaultInertia then
            self:GetEntity().defaultInertia = self:GetInertia() / self:GetMass()
        end

        self:OldSetInertia(v)
    end
end

function TOOL:Think()
    if CLIENT then return end
    local owner = self:GetOwner()
    local ent = owner:GetEyeTrace().Entity
    if not isReallyValid(ent) then return end
    owner:SetNWVectorPrecise("Inertia", ent:GetPhysicsObject():GetInertia())
    owner:SetNWVectorPrecise("DefaultInertia", ent.defaultInertia or ent:GetPhysicsObject():GetInertia() / ent:GetPhysicsObject():GetMass())
    owner:SetNWFloat("InertiaTool::Mass", ent:GetPhysicsObject():GetMass())
end

local function vClamp(v, min, max)
    return Vector(math.Clamp(v.x, min, max), math.Clamp(v.y, min, max), math.Clamp(v.z, min, max))
end

function TOOL:LeftClick(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER then
        local ent = trace.Entity
        local entMass = trace.Entity:GetPhysicsObject():GetMass()
        local newInertia = Vector(self:GetClientInfo("x"), self:GetClientInfo("y"), self:GetClientInfo("z")) / entMass
        local defaultInertia = ent.defaultInertia or ent:GetPhysicsObject():GetInertia() / entMass

        if self:GetClientInfo("mode") == "direct" then
            newInertia = vClamp(newInertia * entMass, 0.001, 100000000) / entMass

            setInertia(nil, ent, {
                inertiaToSet = newInertia,
                defaultInertia = defaultInertia,
                inertiaLock = newInertia * ent:GetPhysicsObject():GetMass()
            })
        else
            newInertia = vClamp(defaultInertia * newInertia * entMass, 0.001, 100000000)

            setInertia(nil, ent, {
                inertiaToSet = newInertia,
                defaultInertia = defaultInertia,
                inertiaLock = newInertia * ent:GetPhysicsObject():GetMass()
            })
        end

        if self:GetClientInfo("lock") == "1" then
            ent.inertiaLock = newInertia * ent:GetPhysicsObject():GetMass()
        else
            ent.inertiaLock = nil
        end
    end

    return true
end

function TOOL:RightClick(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER then
        local finalInertia = trace.Entity:GetPhysicsObject():GetInertia()
        local defaultInertia = trace.Entity.defaultInertia and (trace.Entity.defaultInertia * trace.Entity:GetPhysicsObject():GetMass()) or finalInertia

        --Return the inertia multiplier instead of raw inertia values if using mode 2
        if self:GetClientInfo("mode") == "multiplier" then
            finalInertia = Vector(finalInertia.x / defaultInertia.x, finalInertia.y / defaultInertia.y, finalInertia.z / defaultInertia.z)
        end

        self:GetOwner():ConCommand("inertia_x " .. finalInertia.x)
        self:GetOwner():ConCommand("inertia_y " .. finalInertia.y)
        self:GetOwner():ConCommand("inertia_z " .. finalInertia.z)
    end

    return true
end

function TOOL:Reload(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER and trace.Entity.defaultInertia then
        trace.Entity:GetPhysicsObject():SetInertia(trace.Entity.defaultInertia * trace.Entity:GetPhysicsObject():GetMass())
        trace.Entity.inertiaLock = nil
        trace.Entity.setInertia = nil
        trace.Entity.defaultInertia = nil
        duplicator.ClearEntityModifier(trace.Entity, "inertia")
    end

    return true
end

local conVarsDefault = TOOL:BuildConVarList()

function TOOL.BuildCPanel(cp)
    cp:AddControl("Header", {
        Text = "#tool.inertia.name",
        Description = "#tool.inertia.desc"
    })

    cp:AddControl("ComboBox", {
        MenuButton = 1,
        Folder = "inertia",
        Options = {
            ["#preset.default"] = conVarsDefault
        },
        CVars = table.GetKeys(conVarsDefault)
    })

    cp:AddControl("ComboBox", {
        Label = "#tool.inertia.mode",
        MenuButton = 0,
        Options = {
            ["Directly set"] = {
                inertia_mode = "direct"
            },
            ["Multiple of default"] = {
                inertia_mode = "multiplier"
            }
        }
    })

    cp:ControlHelp("")
    cp:ControlHelp("#tool.inertia.modehelp")

    cp:AddControl("Slider", {
        Label = "#tool.inertia.x",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_x"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.y",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_y"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.z",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_z"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.xyz",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_xyz"
    })

    cp:ControlHelp("#tool.inertia.note")
    cp:ControlHelp("")
    cp:ControlHelp("#tool.inertia.warning")

    cp:AddControl("toggle", {
        Label = "#tool.inertia.inertialock",
        Command = "inertia_lock",
        Help = true
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.tooltipscale",
        Type = "Float",
        Min = "0.25",
        Max = "4",
        Command = "inertia_tooltipscale"
    })
end

if CLIENT then
    cvars.RemoveChangeCallback("inertia_xyz", "inertia_changecallback")

    hook.Add("InitPostEntity", "inertia::clientload", function()
        cvars.AddChangeCallback("inertia_xyz", function(_, _, newValue)
            LocalPlayer():ConCommand("inertia_x " .. newValue)
            LocalPlayer():ConCommand("inertia_y " .. newValue)
            LocalPlayer():ConCommand("inertia_z " .. newValue)
        end, "inertia_changecallback")
    end)

    surface.CreateFont("InertiaFont", {
        font = "coolvetica",
        size = 75,
        weight = 10,
        antialias = true
    })

    local function matrixToString(m)
        return "[" .. math.Round(m[1], 2) .. ", " .. math.Round(m[2], 2) .. ", " .. math.Round(m[3], 2) .. "]"
    end

    hook.Add("HUDPaint", "Inertia::HUD", function()
        local ply = LocalPlayer()
        if not ply:GetActiveWeapon():IsValid() or ply:GetActiveWeapon():GetClass() ~= "gmod_tool" or ply:GetInfo("gmod_toolmode") ~= "inertia" then return end

        local ent = LocalPlayer():GetEyeTrace().Entity
        if not isReallyValid(ent) then return end

        local obb = ent:OBBCenter()
        obb:Rotate(ent:GetAngles())
        local pos = (ent:GetPos() + obb):ToScreen()
        local str

        if GetConVar("inertia_mode"):GetString() == "multiplier" then
            local v1 = ply:GetNWVectorPrecise("Inertia", Vector())
            local v2 = ply:GetNWVectorPrecise("DefaultInertia", Vector()) * ply:GetNWFloat("InertiaTool::Mass")

            if v1:Length() > 4294967295 then
                v1 = Vector()
            end
            if v2:Length() > 4294967295 then
                v2 = Vector()
            end

            str = "Current: [" .. (v1 == Vector() and "Unknown]" or math.Round(v1.x / v2.x, 2) .. "x, " .. math.Round(v1.y / v2.y, 2) .. "x, " .. math.Round(v1.z / v2.z, 2) .. "x]")
        else
            local v = ply:GetNWVectorPrecise("Inertia", Vector())
            if v:Length() > 4294967295 then
                v = Vector()
            end

            str = "Current: " .. (v == Vector() and "[Unknown]" or matrixToString(v))
        end

        local default = ply:GetNWVectorPrecise("DefaultInertia", Vector()) * ply:GetNWFloat("InertiaTool::Mass")
        default = default:Length() > 4294967295 and Vector() or default

        local str2 = "Default: " .. (default == Vector() and "[Unknown]" or matrixToString(default))
        surface.SetFont("InertiaFont")
        local w, h = surface.GetTextSize(str)
        local w2, _ = surface.GetTextSize(str2)

        local mat = Matrix()
        mat:Translate(Vector(pos.x, pos.y))
        mat:Scale(Vector(1, 1, 1) * ply:GetInfoNum("inertia_tooltipscale", 1) / 2)
        mat:Translate(-Vector(pos.x, pos.y))

        surface.SetDrawColor(Color(0, 0, 0, 100))
        cam.Start3D()
            render.SetMaterial(Material("cable/red"))
            render.DrawBeam(ent:GetPos(), ent:LocalToWorld(Vector(25, 0, 0)), 0.5, 0, 1)
            render.SetMaterial(Material("cable/green"))
            render.DrawBeam(ent:GetPos(), ent:LocalToWorld(Vector(0, 25, 0)), 0.5, 0, 1)
            render.SetMaterial(Material("cable/blue"))
            render.DrawBeam(ent:GetPos(), ent:LocalToWorld(Vector(0, 0, 25)), 0.5, 0, 1)
        cam.End3D()

        local x = ent:LocalToWorld(Vector(27, 0, 0)):ToScreen()
        local y = ent:LocalToWorld(Vector(0, 27, 0)):ToScreen()
        local z = ent:LocalToWorld(Vector(0, 0, 27)):ToScreen()
        draw.SimpleTextOutlined("X", "DermaLarge", x.x, x.y, Color(255, 0, 0), 1, 1, 1, Color(0, 0, 0))
        draw.SimpleTextOutlined("Y", "DermaLarge", y.x, y.y, Color(0, 255, 0), 1, 1, 1, Color(0, 0, 0))
        draw.SimpleTextOutlined("Z", "DermaLarge", z.x, z.y, Color(0, 0, 255), 1, 1, 1, Color(0, 0, 0))

        cam.PushModelMatrix(mat)
            surface.DrawRect(pos.x - w / 2, pos.y - h, w, h)
            draw.DrawText(str, "InertiaFont", pos.x, pos.y - h, Color(255, 255, 255), 1)
            surface.DrawRect(pos.x - w2 / 2, pos.y, w2, h)
            draw.DrawText(str2, "InertiaFont", pos.x, pos.y, Color(255, 255, 255), 1)
        cam.PopModelMatrix()
    end)
end