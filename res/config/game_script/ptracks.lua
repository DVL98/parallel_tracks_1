local dump = require "luadump"
local coor = require "ptracks/coor"
local func = require "ptracks/func"
local pipe = require "ptracks/pipe"

local state = {
    use = false,
    window = false,
    spacing = 0,
    nTracks = 2,
    fn = {}
}

local setWidth = function(ctrl, width)
    local tRect = ctrl:getContentRect()
    local tSize = api.gui.util.Size.new()
    tSize.h = tRect.h
    tSize.w = width
    ctrl:setGravity(-1, -1)
    ctrl:setMinimumSize(tSize)
end

local setSpacingText = function(spacing)
    return string.format("%0.1f%s", spacing, _("METER"))
end

local createWindow = function()
    if not api.gui.util.getById("ptracks.use") then
        local menu = api.gui.util.getById("menu.construction.rail.settings")
        local menuLayout = menu:getLayout()
        

        local useLayout = api.gui.layout.BoxLayout.new("VERTICAL")
        useLayout:setName("ParamsListComp::ButtonParam")

        local use = api.gui.comp.TextView.new(_("USE_PARALLEL_TRACKS"))
        local useNo = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("NO")), true)
        local useYes = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("YES")), true)

        useNo:setId("tb")
        -- useNo:setName("ToggleButton")
        -- useYes:setName("ToggleButton")
        
        local useButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
        useButtonLayout:addItem(useNo)
        useButtonLayout:addItem(useYes)
        useButtonLayout:setName("ToggleButtonGroup")

        useLayout:addItem(use)
        useLayout:addItem(useButtonLayout)

        useLayout:setId("ptracks.use")
        
        local ntracksLayout = api.gui.layout.BoxLayout.new("VERTICAL")
        local ntracksText = api.gui.comp.TextView.new(_("N_TRACK"))
        local ntracksValue = api.gui.comp.TextView.new(tostring(state.nTracks))
        local ntracksSlider = api.gui.comp.Slider.new(true)
        local ntracksSliderLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
        local ntracksComp = api.gui.comp.Component.new("ParamsListComp::SliderParam")
        ntracksComp:setLayout(ntracksLayout)
        ntracksComp:setId("ptracks.ntracks")
        
        ntracksSlider:setStep(1)
        ntracksSlider:setMinimum(2)
        ntracksSlider:setMaximum(20)
        ntracksSlider:setValue(state.nTracks, false)
        
        setWidth(ntracksSlider, 150)
        ntracksSliderLayout:addItem(ntracksSlider)
        ntracksSliderLayout:addItem(ntracksValue)
        ntracksLayout:addItem(ntracksText)
        ntracksLayout:addItem(ntracksSliderLayout)
        
        local spacingLayout = api.gui.layout.BoxLayout.new("VERTICAL")
        local spacingText = api.gui.comp.TextView.new(_("SPACING"))
        local spacingValue = api.gui.comp.TextView.new(setSpacingText(state.spacing))
        local spacingSlider = api.gui.comp.Slider.new(true)
        local spacingSliderLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
        local spacingComp = api.gui.comp.Component.new("ParamsListComp::SliderParam")
        spacingComp:setLayout(spacingLayout)
        ntracksComp:setId("ptracks.spacing")
        
        spacingSlider:setStep(1)
        spacingSlider:setMinimum(0)
        spacingSlider:setMaximum(20)
        spacingSlider:setValue(state.spacing * 2, false)
        
        setWidth(spacingSlider, 150)
        spacingSliderLayout:addItem(spacingSlider)
        spacingSliderLayout:addItem(spacingValue)
        spacingLayout:addItem(spacingText)
        spacingLayout:addItem(spacingSliderLayout)
        
        menuLayout:addItem(useLayout)
        menuLayout:addItem(ntracksComp)
        menuLayout:addItem(spacingComp)
        
        ntracksSlider:onValueChanged(function(value)
            table.insert(state.fn, function()
                ntracksValue:setText(tostring(value))
                game.interface.sendScriptEvent("__ptracks__", "ntracks", {nTracks = value})
            end)
        
        end)
        
        spacingSlider:onValueChanged(function(value)
            table.insert(state.fn, function()
                spacingValue:setText(setSpacingText(value * 0.5))
                game.interface.sendScriptEvent("__ptracks__", "spacing", {spacing = value * 0.5})
            end)
        end)
        
        useNo:onClick(function()
            table.insert(state.fn, function()
                game.interface.sendScriptEvent("__ptracks__", "use", {use = false})
                ntracksComp:setVisible(false, false)
                spacingComp:setVisible(false, false)
            end)
        end)
        
        useYes:onClick(function()
            table.insert(state.fn, function()
                game.interface.sendScriptEvent("__ptracks__", "use", {use = true})
                game.interface.sendScriptEvent("__edgeTool__", "off", {sender = "ptracks"})
                ntracksComp:setVisible(true, false)
                spacingComp:setVisible(true, false)
            
            end)
        end)
    end
end

local function calcVec(p0, p1, t0, t1)
    local q0 = t0:normalized()
    local q1 = t1:normalized()
    
    local v = p1 - p0
    local length = v:length()
    
    local cos = q0:dot(q1)
    local rad = math.acos(cos)
    if (rad < 0.05) then return q0 * length, q1 * length, p0, p1 end
    -- local hsin = math.sqrt((1 - cos) * 0.5)
    -- local r = 0.5 * length / hsin
    local r = length / math.sqrt(2 - 2 * cos)
    local scale = rad * r
    return q0 * scale, q1 * scale, p0, p1
end

local buildParallel = function(newSegments)
    local newIdCount = 0
    local newNodes = {}
    local function newId()newIdCount = newIdCount + 1 return -newIdCount end
    local proposal = api.type.SimpleProposal.new()
    
    local trackEdge = api.engine.getComponent(newSegments[1], api.type.ComponentType.BASE_EDGE_TRACK)
    
    local trackType = trackEdge.trackType
    local trackWidth = api.res.trackTypeRep.get(trackType).trackDistance
    
    local spacing = trackWidth + state.spacing
    
    local nTracks = state.nTracks
    
    local pos = pipe.new
        * (nTracks % 2 == 1 and
        func.seq(-(nTracks - 1) / 2, (nTracks - 1) / 2) or
        func.seq(-nTracks / 2, nTracks / 2 - 1))
        * pipe.filter(function(pos) return pos ~= 0 end)
    
    for n, seg in ipairs(newSegments) do
        newNodes[n] = {}
        
        local comp = api.engine.getComponent(seg, api.type.ComponentType.BASE_EDGE)
        
        local pos0 = coor.new(game.interface.getEntity(comp.node0).position)
        local pos1 = coor.new(game.interface.getEntity(comp.node1).position)
        local vec0 = coor.xyz(comp.tangent0[1], comp.tangent0[2], comp.tangent0[3])
        local vec1 = coor.xyz(comp.tangent1[1], comp.tangent1[2], comp.tangent1[3])
        
        for i, pos in ipairs(pos) do
            local rot = coor.xyz(0, 0, 1)
            local disp0 = vec0:cross(rot):normalized() * pos * spacing
            local disp1 = vec1:cross(rot):normalized() * pos * spacing
            local vec0, vec1, pos0, pos1 = calcVec(pos0 + disp0, pos1 + disp1, vec0, vec1)
            local entity = api.type.SegmentAndEntity.new()
            entity.entity = newId()
            entity.playerOwned = {player = api.engine.util.getPlayer()}
            for i = 1, 3 do
                entity.comp.tangent0[i] = vec0[i]
                entity.comp.tangent1[i] = vec1[i]
            end
            
            entity.comp.type = comp.type
            entity.comp.typeIndex = comp.typeIndex
            
            entity.type = 1
            entity.trackEdge.trackType = trackEdge.trackType
            entity.trackEdge.catenary = trackEdge.catenary
            
            local newNode = function(pos)
                local node = api.type.NodeAndEntity.new()
                node.entity = newId()
                for i = 1, 3 do
                    node.comp.position[i] = pos[i]
                end
                proposal.streetProposal.nodesToAdd[#proposal.streetProposal.nodesToAdd + 1] = node
                return node.entity
            end
            
            local catchNode = function(pos)
                return pipe.new
                    * game.interface.getEntities({pos = pos:toTuple(), radius = 1}, {type = "BASE_NODE"})
                    * pipe.map(game.interface.getEntity)
                    * pipe.sort(function(e) return (coor.new(e.position) - pos):length() end)
                    * (function(r) return #r > 0 and r[1].id or nil end)
            end
            
            if n == 1 then
                entity.comp.node0 = catchNode(pos0) or newNode(pos0)
            else
                entity.comp.node0 = newNodes[n - 1][i]
            end
            
            if n == #newSegments then
                entity.comp.node1 = catchNode(pos1) or newNode(pos1)
            else
                entity.comp.node1 = newNode(pos1)
                newNodes[n][i] = entity.comp.node1
            end
            proposal.streetProposal.edgesToAdd[#proposal.streetProposal.edgesToAdd + 1] = entity
        end
    end
    local build = api.cmd.make.buildProposal(proposal, nil, false)
    api.cmd.sendCommand(build, function(x) end)
end

local script = {
    handleEvent = function(src, id, name, param)
        if (id == "__edgeTool__" and param.sender ~= "ptracks") then
            if (name == "off") then
                state.use = false
            end
        elseif (id == "__ptracks__") then
            if (name == "use") then
                state.use = param.use
            elseif (name == "spacing") then
                state.spacing = param.spacing
            elseif (name == "ntracks") then
                state.nTracks = param.nTracks
            elseif (name == "build") then
                buildParallel(param.newSegments)
            end
        end
    end,
    save = function()
        return state
    end,
    load = function(data)
        if data then
            state.use = data.use or false
            state.spacing = data.spacing
            state.nTracks = data.nTracks
        end
    end,
    guiInit = function()
    end,
    guiUpdate = function()
        for _, fn in ipairs(state.fn) do fn() end
        state.fn = {}
    end,
    guiHandleEvent = function(source, name, param)
        if source == "trackBuilder" then
            createWindow()
        end
        if name == "builder.apply" then
            local proposal = param.proposal.proposal
            local toRemove = param.proposal.toRemove
            local toAdd = param.proposal.toAdd
            if state.use
                and (not toAdd or #toAdd == 0)
                and (not toRemove or #toRemove == 0)
                and proposal.addedSegments
                and proposal.new2oldSegments
                and proposal.removedSegments
                and #proposal.addedSegments > 0
                and #proposal.new2oldSegments == 0
                and #proposal.removedSegments == 0
            then
                local newSegments = {}
                for i = 1, #proposal.addedSegments do
                    local seg = proposal.addedSegments[i]
                    if seg.type == 1 then
                        table.insert(newSegments, seg.entity)
                    end
                end
                
                if #newSegments > 0 then
                    game.interface.sendScriptEvent("__ptracks__", "build", {newSegments = newSegments})
                end
            end
        end
    end
}

function data()
    return script
end
